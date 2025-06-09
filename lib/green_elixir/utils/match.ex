defmodule GreenElixir.Multiplayer.Match do
  defstruct [
    :id,
    :name,
    :host_id,
    :password,
    :max_players,
    :game_mode,
    :scoring_type,
    :team_type,
    :mods,
    :players,
    :slots,
    :in_progress
  ]

  def add_player(match, session) do
    %{match | players: Map.put(match.players, session.user_id, session)}
  end

  def remove_player(match, session) do
    %{match | players: Map.delete(match.players, session.user_id)}
  end

  def can_join?(match, session, password) do
    cond do
      Map.has_key?(match.players, session.user_id) ->
        false

      map_size(match.players) >= match.max_players ->
        false

      match.password && match.password != password ->
        false

      match.in_progress ->
        false

      true ->
        true
    end
  end
end
