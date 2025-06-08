defmodule GreenElixirWeb.Router do
  alias GreenElixirWeb.ScoreController
  alias Hex.API.User
  alias Credo.Execution.Task.UseColors
  use GreenElixirWeb, :router

  pipeline :api do
    plug :accepts, ["json", "html", "text"]
    plug :put_secure_browser_headers
  end

  pipeline :osu_client do
    plug :accepts, ["html", "text"]
    plug GreenElixirWeb.Plugs.OsuAuth
  end

  scope "/web", GreenElixirWeb do
    pipe_through :osu_client

    post "/osu-submit-modular-selector.php", ScoreController, :submit_score
    post "/osu-getscores.php", ScoreController, :get_scores
    get "/osu-getreplay.php", ScoreController, :get_replay
  end

  scope "/api/v1", GreenElixirWeb do
    pipe_through :api

    resources "/users", UserController, only: [:show, :index]
    get "/users/:id/scores", UserController, :scores
    get "/users/:id/stats", UserController, :stats

    get "/beatmaps/:id/scores", LeaderboardController, :beatmap_scores
    get "/rankings/:mode", LeaderboardController, :global_rankings

    resources "/beatmaps", BeatmapController, only: [:show, :index]
    get "/beatmapsets/:id", BeatmapController, :beatmapset
  end

  scope "/admin", GreenElixirWeb.Admin do
    pipe_through [:api, :admin_auth]

    resources "/users", UserController
    resources "/scores", ScoreController
    get "/stats", DashboardController, :stats
  end

  scope "/socket" do
    pipe_through :api

    get "/websocket", GreenElixirWeb.UserSocket, :websocket
  end

  get "/health", GreenElixirWeb.HealthController, :check
end
