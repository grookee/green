defmodule GreenElixir.Cache.BeatmapCache do
  @moduledoc """
  Caching layer for beatmap data to reduce Observatory API calls.
  """
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get(key) do
    case Cachex.get(:beatmap_cache, key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, value} -> {:ok, value}
      {:error, _} = error -> error
    end
  end

  def put(key, value, opts \\ []) do
    Cachex.put(:beatmap_cache, key, value, opts)
  end

  def delete(key) do
    Cachex.del(:beatmap_cache, key)
  end

  def clear do
    Cachex.clear(:beatmap_cache)
  end

  def stats do
    Cachex.stats(:beatmap_cache)
  end

  @impl true
  def init(_opts) do
    # Start the cache
    cache_opts = [
      # Maximum 10k cached items
      limit: 10000,
      # Default 2 hour expiration
      expiration: :timer.hours(2),
      stats: true
    ]

    {:ok, _pid} = Cachex.start_link(:beatmap_cache, cache_opts)

    {:ok, %{}}
  end
end
