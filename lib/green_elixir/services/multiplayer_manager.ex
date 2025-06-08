defmodule GreenElixir.Services.MultiplayerManager do
  use GenServer

  alias GreenElixir.Multiplayer.Match
  alias GreenElixir.Services.SessionManager

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def create_match(host_session, match_settings) do
    GenServer.call(__MODULE__, {:create_match, host_session, match_settings})
  end

  def join_match(session, match_id, password \\ nil) do
    GenServer.call(__MODULE__, {:join_match, session, match_id, password})
  end

  def leave_match(session) do
    GenServer.call(__MODULE__, {:leave_match, session})
  end

  def get_match(match_id) do
    GenServer.call(__MODULE__, {:get_match, match_id})
  end

  def list_matches do
    GenServer.call(__MODULE__, :list_matches)
  end

  @impl true
  def init(_opts) do
    :ets.new(:matches, [:set, :protected, :named_table])
    {:ok, %{next_match_id: 1}}
  end

  @impl true
  def handle_call(
        {:create_match, host_session, match_settings},
        _from,
        %{next_match_id: match_id} = state
      ) do
    match = %Match{
      id: match_id,
      name: Map.get(match_settings, :name, "New Match"),
      host_id: host_session.user_id,
      password: Map.get(match_settings, :password),
      max_players: Map.get(match_settings, :max_players, 16),
      game_mode: Map.get(match_settings, :game_mode, 0),
      scoring_type: Map.get(match_settings, :scoring_type, 0),
      team_type: Map.get(match_settings, :team_type, 0),
      mods: Map.get(match_settings, :mods, 0),
      players: %{},
      slots: initialize_slots(16),
      in_progress: false
    }

    # Add host to match
    match = Match.add_player(match, host_session)

    :ets.insert(:matches, {match_id, match})

    # Broadcast new match to lobby
    broadcast_match_update(match)

    {:reply, {:ok, match}, %{state | next_match_id: match_id + 1}}
  end

  @impl true
  def handle_call({:join_match, session, match_id, password}, _from, state) do
    case :ets.lookup(:matches, match_id) do
      [{_id, match}] ->
        case Match.can_join?(match, session, password) do
          true ->
            updated_match = Match.add_player(match, session)
            :ets.insert(:matches, {match_id, updated_match})

            # Notify all players in match
            broadcast_to_match(updated_match, :match_join, session)

            {:reply, {:ok, updated_match}, state}

          false ->
            {:reply, {:error, :cannot_join}, state}
        end

      [] ->
        {:reply, {:error, :match_not_found}, state}
    end
  end

  @impl true
  def handle_call({:leave_match, session}, _from, state) do
    # Find match containing this session
    matches = :ets.tab2list(:matches)

    case Enum.find(matches, fn {_id, match} -> Map.has_key?(match.players, session.user_id) end) do
      {match_id, match} ->
        updated_match = Match.remove_player(match, session)

        if map_size(updated_match.players) == 0 do
          # Delete empty match
          :ets.delete(:matches, match_id)
          broadcast_match_removed(match_id)
        else
          :ets.insert(:matches, {match_id, updated_match})
          broadcast_to_match(updated_match, :match_leave, session)
        end

        {:reply, :ok, state}

      nil ->
        {:reply, {:error, :not_in_match}, state}
    end
  end

  defp initialize_slots(count) do
    0..(count - 1)
    |> Enum.map(fn i -> {i, %{status: :open, user_id: nil, team: :neutral, mods: 0}} end)
    |> Map.new()
  end

  defp broadcast_match_update(match) do
    # Broadcast to lobby users
    lobby_data = %{
      type: :match_update,
      match: serialize_match_for_lobby(match)
    }

    SessionManager.broadcast_to_all(:server_match_update, lobby_data)
  end

  defp broadcast_to_match(match, event_type, data) do
    match.players
    |> Map.keys()
    |> Enum.each(fn user_id ->
      SessionManager.send_to_user(user_id, event_type, data)
    end)
  end

  defp serialize_match_for_lobby(match) do
    %{
      id: match.id,
      name: match.name,
      host_username: get_username(match.host_id),
      player_count: map_size(match.players),
      max_players: match.max_players,
      has_password: !is_nil(match.password),
      game_mode: match.game_mode,
      in_progress: match.in_progress
    }
  end

  defp get_username(user_id) do
    # Get username from session or database
    case SessionManager.get_user_session(user_id) do
      {:ok, session} -> session.username
      _ -> "Unknown"
    end
  end

  defp broadcast_match_removed(match_id) do
    SessionManager.broadcast_to_all(:server_match_removed, %{match_id: match_id})
  end
end
