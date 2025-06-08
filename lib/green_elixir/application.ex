defmodule GreenElixir.Application do
  @moduledoc """
  The GreenElixir Application.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Database
      GreenElixir.Repo,

      # PubSub
      {Phoenix.PubSub, name: GreenElixir.PubSub},

      # Cache
      {Redix, name: :redix},
      {Cachex, name: :Green_cache},

      # Registry for sessions and matches
      {Registry, keys: :unique, name: GreenElixir.SessionRegistry},
      {Registry, keys: :unique, name: GreenElixir.MatchRegistry},

      # Core services
      GreenElixir.Services.SessionManager,
      GreenElixir.Services.BanchoServer,
      GreenElixir.Services.MultiplayerManager,
      GreenElixir.Services.ChatManager,
      GreenElixir.Services.BeatmapManager,

      # Background Jobs
      {Oban, Application.fetch_env!(:Green_elixir, Oban)},

      # Web endpoints
      GreenElixirWeb.Endpoint,

      # Telemetry
      GreenElixirWeb.Telemetry
    ]

    opts = [strategy: :one_for_one, name: GreenElixir.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    GreenElixirWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
