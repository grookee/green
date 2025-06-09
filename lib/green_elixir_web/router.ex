defmodule GreenElixirWeb.Router do
  use GreenElixirWeb, :router

  pipeline :api do
    plug :accepts, ["json", "html", "text"]
    plug :put_secure_browser_headers
  end

  pipeline :osu_client do
    plug :accepts, ["html", "text"]
    plug GreenElixirWeb.Plugs.OsuAuth
  end

  # osu! client endpoints (subdomain: osu.Green.local)
  scope "/web", GreenElixirWeb do
    pipe_through :osu_client

    # Score endpoints
    post "/osu-submit-modular-selector.php", ScoreController, :submit_score
    get "/osu-getscores.php", ScoreController, :get_scores
    get "/osu-getreplay.php", ScoreController, :get_replay

    # User endpoints
    get "/osu-getfriends.php", WebController, :get_friends
    post "/osu-screenshot.php", WebController, :upload_screenshot
    get "/lastfm.php", WebController, :lastfm_check

    # Beatmap endpoints
    get "/osu-addfavourite.php", WebController, :add_favourite
    get "/osu-getfavourites.php", WebController, :get_favourites
    post "/osu-getbeatmapinfo.php", WebController, :get_beatmap_info

    # Client endpoints
    get "/bancho_connect.php", WebController, :bancho_connect
    post "/osu-session.php", WebController, :osu_session
    get "/osu-markasread.php", WebController, :mark_as_read
    get "/check-updates.php", WebController, :check_updates
    get "/osu-getseasonal.php", WebController, :get_seasonal
    post "/osu-error.php", WebController, :osu_error

    # Registration
    post "/register.php", AuthController, :register
  end

  # API endpoints (subdomain: api.Green.local)
  scope "/api/v1", GreenElixirWeb do
    pipe_through :api

    # User management
    resources "/users", UserController, only: [:show, :index]
    get "/users/:id/scores", UserController, :scores
    get "/users/:id/stats", UserController, :stats

    # Leaderboards
    get "/beatmaps/:id/scores", LeaderboardController, :beatmap_scores
    get "/rankings/:mode", LeaderboardController, :global_rankings

    # Beatmaps
    resources "/beatmaps", BeatmapController, only: [:show, :index]
    get "/beatmapsets/:id", BeatmapController, :beatmapset
  end

  # pipeline :admin_auth do
  #   plug GreenElixirWeb.Plugs.AdminAuth
  # end

  # # Admin endpoints
  # scope "/admin", GreenElixirWeb.Admin do
  #   pipe_through [:api, :admin_auth]

  #   resources "/users", UserController
  #   resources "/scores", ScoreController
  #   get "/stats", DashboardController, :stats
  # end

  # WebSocket for real-time features
  scope "/socket" do
    pipe_through :api

    # WebSocket endpoint for live updates
    get "/websocket", GreenElixirWeb.UserSocket, :websocket
  end

  # Health check
  get "/health", GreenElixirWeb.HealthController, :check
end
