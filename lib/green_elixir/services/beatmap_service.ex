defmodule GreenElixir.Services.BeatmapService do
  @moduledoc """
  Manages beatmap data, integrates with Observatory API.
  """
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_beatmap_set(beatmap_hash, beatmap_id \\ nil) do
    GenServer.call(__MODULE__, {:get_beatmap_set, beatmap_hash, beatmap_id})
  end

  def get_beatmap_difficulty(beatmap_id, mods \\ 0) do
    GenServer.call(__MODULE__, {:get_difficulty, beatmap_id, mods})
  end

  @impl true
  def init(_opts) do
    observatory_url =
      Application.get_env(:Green_elixir, :observatory_url, "http://localhost:5000")

    {:ok, %{observatory_url: observatory_url}}
  end

  @impl true
  def handle_call({:get_beatmap_set, beatmap_hash, beatmap_id}, _from, state) do
    case fetch_from_observatory(state.observatory_url, beatmap_hash, beatmap_id) do
      {:ok, beatmap_data} ->
        # Cache the beatmap data
        cache_beatmap_data(beatmap_data)
        {:reply, {:ok, beatmap_data}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_difficulty, beatmap_id, mods}, _from, state) do
    case calculate_difficulty_with_mods(beatmap_id, mods) do
      {:ok, difficulty} -> {:reply, {:ok, difficulty}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp fetch_from_observatory(base_url, beatmap_hash, beatmap_id) do
    url = "#{base_url}/api/beatmap"
    params = if beatmap_id, do: %{id: beatmap_id}, else: %{hash: beatmap_hash}

    case HTTPoison.get(url, [], params: params) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, :beatmap_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp calculate_difficulty_with_mods(beatmap_id, mods) do
    # Implement difficulty calculation with mods
    # This would typically call a difficulty calculator service
    # Check if we can calculate difficulty for this beatmap
    if beatmap_exists?(beatmap_id) do
      {:ok,
       %{
         aim_difficulty: 5.0,
         speed_difficulty: 5.0,
         overall_difficulty: 8.0,
         max_combo: 1000
       }}
    else
      {:error, :beatmap_not_found}
    end
  end

  # Helper function to check if beatmap exists
  defp beatmap_exists?(beatmap_id) when is_integer(beatmap_id) or is_binary(beatmap_id) do
    # Replace with actual implementation that checks if the beatmap exists
    # For now, assume all beatmaps exist
    true
  end

  defp cache_beatmap_data(beatmap_data) do
    Cachex.put(:Green_cache, "beatmap:#{beatmap_data["id"]}", beatmap_data, ttl: :timer.hours(1))
  end
end
