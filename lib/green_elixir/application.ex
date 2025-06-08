defmodule GreenElixir.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      GreenElixir.Repo,
      {Phoenix.PubSub, name: GreenElixir.PubSub},
      {Redix, name: :redix},
      {Cachex, name: :green_cache},
      {Registry, keys: :unique, name: GreenElixir.SessionRegistry},
      {Registry, keys: :unique, name: GreenElixir.MatchRegistry},
      {Oban, Application.fetch_env!(:green_elixir, Oban)},

      # Start the Telemetry supervisor
      GreenElixirWeb.Telemetry,
      # Start the Endpoint (http/https)
      GreenElixirWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GreenElixir.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    GreenElixirWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
