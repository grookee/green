defmodule GreenElixir.Services.SessionManager do
  use GenServer
  alias GreenElixir.Accounts
  alias GreenElixir.Bancho.Protocol

  defstruct [:user_id, :username, :token, :socket, :country, :action, :last_ping, :match_id]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def create_session(user_id, username, socket) do
    GenServer.call(__MODULE__, {:create_session, user_id, username, socket})
  end

  def get_session(token) do
    GenServer.call(__MODULE__, {:get_session, token})
  end

  def update_session(token, updates) do
    GenServer.call(__MODULE__, {:update_session, token, updates})
  end

  def remove_session(token) do
    GenServer.call(__MODULE__, {:remove_session, token})
  end

  def list_online_users do
    GenServer.call(__MODULE__, :list_online_users)
  end

  def broadcast_to_all(packet_type, data, exclude \\ []) do
    GenServer.cast(__MODULE__, {:broadcast_to_all, packet_type, data, exclude})
  end

  @impl true
  def init(_opts) do
    :ets.new(:sessions, [:set, :protected, :named_table])
    :ets.new(:user_sessions, [:set, :protected, :named_table])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:create_session, user_id, username, socket}, _from, state) do
    token = generate_token()

    session = %__MODULE__{
      user_id: user_id,
      username: username,
      token: token,
      socket: socket,
      last_ping: System.system_time(:second)
    }

    :ets.insert(:sessions, {token, session})
    :ets.insert(:user_sessions, {user_id, token})

    # Notify other users of new user online
    broadcast_user_presence(session)

    {:reply, {:ok, token}, state}
  end

  @impl true
  def handle_call({:get_session, token}, _from, state) do
    case :ets.lookup(:sessions, token) do
      [{_token, session}] -> {:reply, {:ok, session}, state}
      [] -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:update_session, token, updates}, _from, state) do
    case :ets.lookup(:sessions, token) do
      [{_token, session}] ->
        updated_session = struct(session, updates)
        :ets.insert(:sessions, {token, updated_session})
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:remove_session, token}, _from, state) do
    case :ets.lookup(:sessions, token) do
      [{_token, session}] ->
        :ets.delete(:sessions, token)
        :ets.delete(:user_sessions, session.user_id)

        # Notify other users that user went offline
        broadcast_user_logout(session)

        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:list_online_users, _from, state) do
    users =
      :ets.tab2list(:sessions)
      |> Enum.map(fn {_token, session} -> session end)

    {:reply, users, state}
  end

  @impl true
  def handle_cast({:broadcast_to_all, packet_type, data, exclude}, state) do
    :ets.tab2list(:sessions)
    |> Enum.each(fn {_token, session} ->
      unless session.user_id in exclude do
        send_packet_to_session(session, packet_type, data)
      end
    end)

    {:noreply, state}
  end

  defp broadcast_user_presence(session) do
    presence_data = %{
      user_id: session.user_id,
      username: session.username,
      country: session.country || 0
    }

    broadcast_to_all(:server_user_presence, presence_data, [session.user_id])
  end

  defp broadcast_user_logout(session) do
    logout_data = %{user_id: session.user_id}
    broadcast_to_all(:server_user_logout, logout_data)
  end

  defp send_packet_to_session(session, packet_type, data) do
    packet = Protocol.encode_packet(packet_type, data)
    send(session.socket, {:send_data, packet})
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32) |> Base.encode64()
  end

  def authenticate_by_credentials(username, password_hash) do
    case Accounts.authenticate_user(username, password_hash) do
      {:ok, user} ->
        session = %{
          user_id: user.id,
          username: user.username,
          privileges: user.privileges || 1
        }

        {:ok, session}

      {:error, _reason} ->
        {:error, :invalid_credentials}
    end
  end

  def get_user_session(user_id) do
    case :ets.match(:user_sessions, {user_id, :"$1"}) do
      [[token]] ->
        get_session(token)

      [] ->
        {:error, :not_found}
    end
  end

  def send_to_user(user_id, packet_type, data) do
    case get_user_session(user_id) do
      {:ok, session} ->
        packet = Protocol.encode_packet(packet_type, data)
        send(session.socket, {:send_data, packet})
        :ok

      {:error, _} ->
        {:error, :user_not_online}
    end
  end
end
