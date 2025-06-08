defmodule GreenElixir.Workers.BeatmapProcessor do
  @moduledoc """
  Background job for processing beatmap data and difficulty calculations.
  """
  use Oban.Worker, queue: :beatmaps, max_attempts: 3

  alias GreenElixir.Services.ObservatoryClient
  alias GreenElixir.Services.PerformanceCalculator

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"type" => "calculate_difficulty", "beatmap_id" => beatmap_id, "mods" => mods}
      }) do
    case ObservatoryClient.get_beatmap_difficulty(beatmap_id, mods) do
      {:ok, difficulty} ->
        # Store difficulty in database if needed
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "refresh_beatmap", "beatmap_hash" => beatmap_hash}}) do
    case ObservatoryClient.get_beatmap_set(beatmap_hash) do
      {:ok, _beatmap_set} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def schedule_difficulty_calculation(beatmap_id, mods) do
    %{
      "type" => "calculate_difficulty",
      "beatmap_id" => beatmap_id,
      "mods" => mods
    }
    |> __MODULE__.new()
    |> Oban.insert()
  end

  def schedule_beatmap_refresh(beatmap_hash) do
    %{
      "type" => "refresh_beatmap",
      "beatmap_hash" => beatmap_hash
    }
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
