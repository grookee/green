defmodule GreenElixir.Services.BanchoServer do
  @moduledoc """
  TCP server handling Bancho protocol connections from osu! clients.
  """
  use GenServer
  require Logger

  alias GreenElixir.Services.SessionManager
  alias GreenElixir.Bancho.Protocol
  alias GreenElixir.Accounts

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, 13381)

    {:ok, listen_socket} =
      :gen_tcp.listen(port, [
        :binary,
        {:active, false},
        {:reuseaddr, true},
        {:keepalive, true}
      ])

    Logger.info("Bancho server listening on port #{port}")

    # Start accepting connections
    send(self(), :accept)

    {:ok, %{listen_socket: listen_socket}}
  end

  @impl true
  def handle_info(:accept, %{listen_socket: listen_socket} = state) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        # Spawn a process to handle this client
        {:ok, _pid} = Task.start_link(fn -> handle_client(client_socket) end)

        # Continue accepting new connections
        send(self(), :accept)

      {:error, reason} ->
        Logger.error("Failed to accept connection: #{inspect(reason)}")
        # Retry after a short delay
        Process.send_after(self(), :accept, 1000)
    end

    {:noreply, state}
  end

  defp handle_client(socket) do
    :inet.setopts(socket, [{:active, true}])

    # Wait for login
    receive do
      {:tcp, ^socket, data} ->
        case handle_login(data) do
          {:ok, session_token} ->
            client_loop(socket, session_token)

          {:error, reason} ->
            Logger.warning("Login failed: #{reason}")
            :gen_tcp.close(socket)
        end

      {:tcp_closed, ^socket} ->
        Logger.info("Client disconnected during login")

      {:tcp_error, ^socket, reason} ->
        Logger.error("TCP error during login: #{reason}")
    after
      30_000 ->
        Logger.warning("Login timeout")
        :gen_tcp.close(socket)
    end
  end

  defp handle_login(data) do
    # Parse login data (username, password hash, client info)
    lines = String.split(data, "\n", trim: true)

    if length(lines) >= 3 do
      [username, password_hash | client_info] = lines

      case Accounts.authenticate_user(username, password_hash) do
        {:ok, user} ->
          {:ok, token} = SessionManager.create_session(user.id, user.username, self())

          # Send login response packets
          send_login_success(user)

          {:ok, token}

        {:error, _reason} ->
          send_login_failure()
          {:error, :invalid_credentials}
      end
    else
      {:error, :invalid_login_format}
    end
  end

  defp client_loop(socket, session_token) do
    receive do
      {:tcp, ^socket, data} ->
        handle_packets(data, session_token)
        client_loop(socket, session_token)

      {:send_data, packet_data} ->
        :gen_tcp.send(socket, packet_data)
        client_loop(socket, session_token)

      {:tcp_closed, ^socket} ->
        Logger.info("Client disconnected")
        SessionManager.remove_session(session_token)

      {:tcp_error, ^socket, reason} ->
        Logger.error("TCP error: #{reason}")
        SessionManager.remove_session(session_token)
    after
      # 5 minute timeout
      300_000 ->
        Logger.warning("Client timeout")
        :gen_tcp.close(socket)
        SessionManager.remove_session(session_token)
    end
  end

  defp handle_packets(data, session_token) do
    handle_packets_recursive(data, session_token)
  end

  defp handle_packets_recursive(<<>>, _session_token), do: :ok

  defp handle_packets_recursive(data, session_token) do
    case Protocol.decode_packet(data) do
      {packet, rest} ->
        handle_packet(packet, session_token)
        handle_packets_recursive(rest, session_token)

      :error ->
        Logger.warning("Failed to decode packet")
    end
  end

  defp handle_packet(%{type: :client_send_public_message, data: message_data}, session_token) do
    {:ok, session} = SessionManager.get_session(session_token)

    # Handle chat message
    GreenElixir.Services.ChatManager.send_message(
      session.user_id,
      message_data.target,
      message_data.message
    )
  end

  defp handle_packet(%{type: :client_change_action, data: action_data}, session_token) do
    SessionManager.update_session(session_token, %{action: action_data})

    # Broadcast user stats update
    {:ok, session} = SessionManager.get_session(session_token)
    broadcast_user_stats(session, action_data)
  end

  defp handle_packet(%{type: :client_pong}, session_token) do
    SessionManager.update_session(session_token, %{last_ping: System.system_time(:second)})
  end

  defp handle_packet(_packet, _session_token) do
    # Handle other packet types
    :ok
  end

  defp send_login_success(user) do
    # Send user ID
    user_id_packet = Protocol.encode_packet(:server_user_id, user.id)
    :gen_tcp.send(self(), user_id_packet)

    # Send other login success packets
    # (privileges, friends list, etc.)
  end

  defp send_login_failure do
    error_packet = Protocol.encode_packet(:server_command_error, "Invalid credentials")
    :gen_tcp.send(self(), error_packet)
  end

  defp broadcast_user_stats(session, action_data) do
    stats_data = %{
      user_id: session.user_id,
      action: action_data.action,
      action_text: action_data.action_text,
      beatmap_md5: action_data.beatmap_md5,
      mods: action_data.mods,
      game_mode: action_data.game_mode,
      beatmap_id: action_data.beatmap_id
    }

    SessionManager.broadcast_to_all(:server_user_stats, stats_data, [session.user_id])
  end
end
