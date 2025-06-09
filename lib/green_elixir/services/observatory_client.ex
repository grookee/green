defmodule GreenElixir.Services.ObservatoryClient do
  @moduledoc """
  Client for communicating with Observatory beatmap manager.
  Handles beatmap fetching, caching, and difficulty calculations.
  """
  use GenServer
  require Logger

  alias GreenElixir.Cache.BeatmapCache
  alias HTTPoison.Response

  defstruct [:base_url, :api_key, :timeout]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Public API
  def get_beatmap_set(beatmap_hash, beatmap_id \\ nil, retries \\ 3) do
    GenServer.call(__MODULE__, {:get_beatmap_set, beatmap_hash, beatmap_id, retries}, 30_000)
  end

  def get_beatmap_difficulty(beatmap_id, mods \\ 0) do
    GenServer.call(__MODULE__, {:get_difficulty, beatmap_id, mods}, 15_000)
  end

  def search_beatmaps(query, limit \\ 50) do
    GenServer.call(__MODULE__, {:search_beatmaps, query, limit}, 15_000)
  end

  def get_beatmap_ranking_status(beatmap_id) do
    GenServer.call(__MODULE__, {:get_ranking_status, beatmap_id}, 10_000)
  end

  @impl true
  def init(opts) do
    config = Application.get_env(:green_elixir, :observatory, [])

    state = %__MODULE__{
      base_url: Keyword.get(config, :url, "http://localhost:5000"),
      api_key: Keyword.get(config, :api_key),
      timeout: Keyword.get(config, :timeout, 30_000)
    }

    # Test connection on startup
    case test_connection(state) do
      :ok ->
        Logger.info("Observatory connection established: #{state.base_url}")
        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to connect to Observatory: #{reason}")
        # Continue anyway, will retry on requests
        {:ok, state}
    end
  end

  @impl true
  def handle_call({:get_beatmap_set, beatmap_hash, beatmap_id, retries}, _from, state) do
    # Check cache first
    cache_key = "beatmapset:#{beatmap_hash || beatmap_id}"

    case BeatmapCache.get(cache_key) do
      {:ok, cached_data} ->
        {:reply, {:ok, cached_data}, state}

      {:error, :not_found} ->
        case fetch_beatmap_set(state, beatmap_hash, beatmap_id, retries) do
          {:ok, beatmap_data} ->
            # Cache for 1 hour
            BeatmapCache.put(cache_key, beatmap_data, ttl: :timer.hours(1))
            {:reply, {:ok, beatmap_data}, state}

          {:error, reason} = error ->
            Logger.warning("Failed to fetch beatmap set: #{inspect(reason)}")
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call({:get_difficulty, beatmap_id, mods}, _from, state) do
    cache_key = "difficulty:#{beatmap_id}:#{mods}"

    case BeatmapCache.get(cache_key) do
      {:ok, cached_difficulty} ->
        {:reply, {:ok, cached_difficulty}, state}

      {:error, :not_found} ->
        case fetch_difficulty(state, beatmap_id, mods) do
          {:ok, difficulty} ->
            # Cache difficulty for 24 hours (doesn't change often)
            BeatmapCache.put(cache_key, difficulty, ttl: :timer.hours(24))
            {:reply, {:ok, difficulty}, state}

          {:error, reason} = error ->
            Logger.warning("Failed to fetch difficulty: #{inspect(reason)}")
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call({:search_beatmaps, query, limit}, _from, state) do
    case search_beatmaps_api(state, query, limit) do
      {:ok, results} ->
        {:reply, {:ok, results}, state}

      {:error, reason} = error ->
        Logger.warning("Beatmap search failed: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get_ranking_status, beatmap_id}, _from, state) do
    case get_ranking_status_api(state, beatmap_id) do
      {:ok, status} ->
        {:reply, {:ok, status}, state}

      {:error, reason} = error ->
        Logger.warning("Failed to get ranking status: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  # Private functions
  defp test_connection(state) do
    url = "#{state.base_url}/api/health"

    case make_request(:get, url, "", [], state) do
      {:ok, %{status_code: 200}} -> :ok
      {:ok, %{status_code: status}} -> {:error, "HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_beatmap_set(state, beatmap_hash, beatmap_id, retries) when retries > 0 do
    url = "#{state.base_url}/api/beatmapset"

    params =
      cond do
        beatmap_id -> [{"beatmap_id", beatmap_id}]
        beatmap_hash -> [{"beatmap_hash", beatmap_hash}]
        true -> []
      end

    case make_request(:get, url, "", [], state, params: params) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} -> process_beatmap_set_response(data)
          {:error, _} -> {:error, :invalid_json}
        end

      {:ok, %{status_code: 404}} ->
        {:error, :beatmap_not_found}

      {:ok, %{status_code: 429}} ->
        # Rate limited, retry after delay
        :timer.sleep(1000)
        fetch_beatmap_set(state, beatmap_hash, beatmap_id, retries - 1)

      {:ok, %{status_code: status}} ->
        {:error, "HTTP #{status}"}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        :timer.sleep(500)
        fetch_beatmap_set(state, beatmap_hash, beatmap_id, retries - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_beatmap_set(_state, _beatmap_hash, _beatmap_id, 0) do
    {:error, :max_retries_exceeded}
  end

  defp fetch_difficulty(state, beatmap_id, mods) do
    url = "#{state.base_url}/api/beatmap/#{beatmap_id}/difficulty"

    params = [{"mods", mods}]

    case make_request(:get, url, "", [], state, params: params) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} -> {:ok, process_difficulty_response(data)}
          {:error, _} -> {:error, :invalid_json}
        end

      {:ok, %{status_code: 404}} ->
        {:error, :beatmap_not_found}

      {:ok, %{status_code: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp search_beatmaps_api(state, query, limit) do
    url = "#{state.base_url}/api/beatmaps/search"

    params = [
      {"q", query},
      {"limit", limit}
    ]

    case make_request(:get, url, "", [], state, params: params) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} -> {:ok, data}
          {:error, _} -> {:error, :invalid_json}
        end

      {:ok, %{status_code: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_ranking_status_api(state, beatmap_id) do
    url = "#{state.base_url}/api/beatmap/#{beatmap_id}/status"

    case make_request(:get, url, "", [], state) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} -> {:ok, data}
          {:error, _} -> {:error, :invalid_json}
        end

      {:ok, %{status_code: 404}} ->
        {:error, :beatmap_not_found}

      {:ok, %{status_code: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp make_request(method, url, body, headers, state, opts \\ []) do
    request_headers = build_headers(headers, state)
    request_opts = [timeout: state.timeout, recv_timeout: state.timeout] ++ opts

    HTTPoison.request(method, url, body, request_headers, request_opts)
  end

  defp build_headers(headers, state) do
    base_headers = [
      {"Content-Type", "application/json"},
      {"User-Agent", "GreenElixir/1.0"}
    ]

    auth_headers =
      if state.api_key do
        [{"Authorization", "Bearer #{state.api_key}"}]
      else
        []
      end

    base_headers ++ auth_headers ++ headers
  end

  defp process_beatmap_set_response(data) do
    # Transform Observatory response to our internal format
    beatmap_set = %{
      id: data["beatmapset_id"],
      artist: data["artist"],
      title: data["title"],
      creator: data["creator"],
      source: data["source"],
      tags: data["tags"],
      status: parse_ranking_status(data["ranked"]),
      beatmaps: Enum.map(data["beatmaps"] || [], &process_beatmap_data/1)
    }

    {:ok, beatmap_set}
  end

  defp process_beatmap_data(beatmap) do
    %{
      id: beatmap["beatmap_id"],
      beatmapset_id: beatmap["beatmapset_id"],
      difficulty_name: beatmap["version"],
      mode: beatmap["mode"],
      checksum: beatmap["file_md5"],
      total_length: beatmap["total_length"],
      hit_length: beatmap["hit_length"],
      count_circles: beatmap["count_normal"],
      count_sliders: beatmap["count_slider"],
      count_spinners: beatmap["count_spinner"],
      circle_size: beatmap["diff_size"],
      overall_difficulty: beatmap["diff_overall"],
      approach_rate: beatmap["diff_approach"],
      hp_drain: beatmap["diff_drain"],
      bpm: beatmap["bpm"],
      max_combo: beatmap["max_combo"],
      status: parse_ranking_status(beatmap["ranked"]),
      # Difficulty attributes (will be calculated separately)
      aim_difficulty: beatmap["diff_aim"] || 0.0,
      speed_difficulty: beatmap["diff_speed"] || 0.0,
      star_rating: beatmap["difficultyrating"] || 0.0
    }
  end

  defp process_difficulty_response(data) do
    %{
      aim_difficulty: data["aim"],
      speed_difficulty: data["speed"],
      overall_difficulty: data["od"],
      star_rating: data["star_rating"],
      max_combo: data["max_combo"],
      performance_max: data["performance_max"]
    }
  end

  defp parse_ranking_status(status) when is_integer(status) do
    case status do
      4 -> :loved
      3 -> :qualified
      2 -> :approved
      1 -> :ranked
      0 -> :pending
      -1 -> :wip
      -2 -> :graveyard
      _ -> :unknown
    end
  end

  defp parse_ranking_status(_), do: :unknown
end
