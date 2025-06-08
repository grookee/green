defmodule GreenElixir.Stats.UserStats do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_stats" do
    belongs_to :user, GreenElixir.Accounts.User
    field :game_mode, :integer
    field :accuracy, :float, default: 0.0
    field :total_score, :integer, default: 0
    field :ranked_score, :integer, default: 0
    field :play_count, :integer, default: 0
    field :performance_points, :float, default: 0.0
    field :max_combo, :integer, default: 0
    field :play_time, :integer, default: 0
    field :total_hits, :integer, default: 0
    field :best_global_rank, :integer
    field :best_global_rank_date, :utc_datetime
    field :best_country_rank, :integer
    field :best_country_rank_date, :utc_datetime

    timestamps()
  end

  def changeset(user_stats, attrs) do
    user_stats
    |> cast(attrs, [
      :user_id,
      :game_mode,
      :accuracy,
      :total_score,
      :ranked_score,
      :play_count,
      :performance_points,
      :max_combo,
      :play_time,
      :total_hits
    ])
    |> validate_required([:user_id, :game_mode])
    |> unique_constraint([:user_id, :game_mode])
  end
end
