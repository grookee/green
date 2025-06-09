defmodule GreenElixir.Beatmaps.UserFavourite do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_favourites" do
    field :user_id, :integer
    field :beatmapset_id, :integer

    timestamps()
  end

  def changeset(user_favourite, attrs) do
    user_favourite
    |> cast(attrs, [:user_id, :beatmapset_id])
    |> validate_required([:user_id, :beatmapset_id])
    |> unique_constraint([:user_id, :beatmapset_id])
  end
end
