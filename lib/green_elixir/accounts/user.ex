defmodule GreenElixir.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [:id, :username, :email, :country, :privilege, :register_date, :account_status]}

  schema "users" do
    field :username, :string
    field :email, :string
    field :password_hash, :string
    field :description, :string
    field :country, :integer, default: 0
    field :registration_ip, :string
    # UserPrivilege enum
    field :privilege, :integer, default: 1
    field :register_date, :utc_datetime
    field :last_online_time, :utc_datetime
    # UserAccountStatus enum
    field :account_status, :integer, default: 0
    field :silenced_until, :utc_datetime
    # GameMode enum
    field :default_game_mode, :integer, default: 0

    has_many :user_stats, GreenElixir.Stats.UserStats
    has_many :scores, GreenElixir.Scores.Score
    has_many :user_files, GreenElixir.Assets.UserFile

    timestamps()
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :email, :password_hash, :registration_ip])
    |> validate_required([:username, :email, :password_hash, :registration_ip])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> validate_length(:username, min: 2, max: 15)
    |> unique_constraint(:username)
    |> unique_constraint(:email)
    |> put_timestamps()
  end

  defp put_timestamps(changeset) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    changeset
    |> put_change(:register_date, now)
    |> put_change(:last_online_time, now)
  end

  def is_restricted?(%__MODULE__{account_status: 1}), do: true
  def is_restricted?(_), do: false

  def is_active?(%__MODULE__{account_status: 0}), do: true
  def is_active?(_), do: false
end
