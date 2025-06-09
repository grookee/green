defmodule GreenElixir.Beatmaps do
  @moduledoc """
  Context for beatmap-related operations
  """

  alias GreenElixir.Repo
  alias GreenElixir.Beatmaps.{Beatmap, BeatmapSet, UserFavourite}
  import Ecto.Query

  def add_favourite(user_id, beatmapset_id) do
    case get_beatmapset(beatmapset_id) do
      {:ok, _beatmapset} ->
        case Repo.get_by(UserFavourite, user_id: user_id, beatmapset_id: beatmapset_id) do
          nil ->
            %UserFavourite{user_id: user_id, beatmapset_id: beatmapset_id}
            |> Repo.insert()

          _existing ->
            {:error, :already_favourited}
        end

      {:error, :not_found} ->
        {:error, :beatmap_not_found}
    end
  end

  def get_user_favourites(user_id) do
    favourites =
      from(f in UserFavourite,
        where: f.user_id == ^user_id,
        select: f.beatmapset_id
      )
      |> Repo.all()

    {:ok, favourites}
  end

  defp get_beatmapset(beatmapset_id) do
    case Repo.get(BeatmapSet, beatmapset_id) do
      nil -> {:error, :not_found}
      beatmapset -> {:ok, beatmapset}
    end
  end
end
