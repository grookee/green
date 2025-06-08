defmodule GreenElixir.Repo do
  use Ecto.Repo,
    otp_app: :green_elixir,
    adapter: Ecto.Adapters.Postgres
end
