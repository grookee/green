defmodule GreenElixir.Services.ChatManager do
  use GenServer

  alias GreenElixir.Services.SessionManager

  defstruct [:name, :description, :auto_join, :read_privileges, :write_privileges, :users]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def send_message(user_id, channel, message) do
    GenServer.cast(__MODULE__, {:send_message, user_id, channel, message})
  end

  def join_channel(user_id, channel) do
    GenServer.call(__MODULE__, {:join_channel, user_id, channel})
  end

  def leave_channel(user_id, channel) do
    GenServer.call(__MODULE__, {:leave_channel, user_id, channel})
  end

  def create_channel(channel_name, opts \\ []) do
    GenServer.call(__MODULE__, {:create_channel, channel_name, opts})
  end

  @impl true
  def init(_opts) do
    :ets.new(:channels, [:set, :protected, :named_table])
    :ets.new(:user_channels, [:bag, :protected, :named_table])

    # Create default channels
    create_default_channels()

    {:ok, %{}}
  end

  @impl true
  def handle_call({:join_channel, user_id, channel_name}, _from, state) do
    case :ets.lookup(:channels, channel_name) do
      [{_name, channel}] ->
        if can_join_channel?(user_id, channel) do
          :ets.insert(:user_channels, {user_id, channel_name})

          # Send channel join success
          SessionManager.send_to_user(user_id, :channel_join_success, %{channel: channel_name})

          {:reply, :ok, state}
        else
          {:reply, {:error, :insufficient_privileges}, state}
        end

      [] ->
        {:reply, {:error, :channel_not_found}, state}
    end
  end

  @impl true
  def handle_call({:leave_channel, user_id, channel_name}, _from, state) do
    :ets.delete_object(:user_channels, {user_id, channel_name})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:create_channel, channel_name, opts}, _from, state) do
    channel = %__MODULE__{
      name: channel_name,
      description: Keyword.get(opts, :description, ""),
      auto_join: Keyword.get(opts, :auto_join, false),
      read_privileges: Keyword.get(opts, :read_privileges, 1),
      write_privileges: Keyword.get(opts, :write_privileges, 1),
      users: MapSet.new()
    }

    :ets.insert(:channels, {channel_name, channel})
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:send_message, user_id, channel_name, message}, state) do
    case :ets.lookup(:channels, channel_name) do
      [{_name, channel}] ->
        if can_write_to_channel?(user_id, channel) and user_in_channel?(user_id, channel_name) do
          # Get sender info
          {:ok, session} = SessionManager.get_user_session(user_id)

          # Handle commands
          case handle_chat_command(message, session, channel_name) do
            :not_command ->
              # Regular message - broadcast to all users in channel
              broadcast_message_to_channel(channel_name, session.username, message, user_id)

            :handled ->
              # Command was handled
              :ok
          end
        end

      [] ->
        # Channel doesn't exist
        :ok
    end

    {:noreply, state}
  end

  defp create_default_channels do
    channels = [
      {"#osu", description: "Main chat channel", auto_join: true},
      {"#announce", description: "Announcements", read_privileges: 1, write_privileges: 8},
      {"#lobby", description: "Multiplayer lobby", auto_join: false}
    ]

    Enum.each(channels, fn {name, opts} ->
      create_channel(name, opts)
    end)
  end

  defp can_join_channel?(user_id, channel) do
    user_privileges = get_user_privileges(user_id)
    user_privileges >= channel.read_privileges
  end

  defp can_write_to_channel?(user_id, channel) do
    user_privileges = get_user_privileges(user_id)
    user_privileges >= channel.write_privileges
  end

  defp user_in_channel?(user_id, channel_name) do
    case :ets.lookup(:user_channels, user_id) do
      channels -> Enum.any?(channels, fn {_id, chan} -> chan == channel_name end)
    end
  end

  defp broadcast_message_to_channel(channel_name, sender_username, message, sender_id) do
    # Get all users in channel
    channel_users =
      :ets.match(:user_channels, {~c"$1", channel_name})
      |> List.flatten()

    message_data = %{
      sender: sender_username,
      message: message,
      target: channel_name,
      sender_id: sender_id
    }

    Enum.each(channel_users, fn user_id ->
      SessionManager.send_to_user(user_id, :server_send_message, message_data)
    end)
  end

  defp handle_chat_command("!" <> command, session, channel) do
    [cmd | args] = String.split(command, " ", trim: true)

    case cmd do
      "roll" ->
        max = if args != [], do: String.to_integer(List.first(args)), else: 100
        result = :rand.uniform(max)

        broadcast_message_to_channel(
          channel,
          "Greenie",
          "#{session.username} rolls #{result} point(s)",
          -1
        )

        :handled

      "help" ->
        help_message = "Available commands: !roll [max], !help"

        SessionManager.send_to_user(session.user_id, :server_send_message, %{
          sender: "Greenie",
          message: help_message,
          target: session.username,
          sender_id: -1
        })

        :handled

      _ ->
        :not_command
    end
  end

  defp handle_chat_command(_, _, _), do: :not_command

  defp get_user_privileges(user_id) do
    # Get user privileges from database or session
    case SessionManager.get_user_session(user_id) do
      {:ok, session} -> session.privileges || 1
      _ -> 1
    end
  end
end
