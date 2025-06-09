defmodule GreenElixirWeb.WebController do
  use GreenElixirWeb, :controller
  import Bitwise

  alias GreenElixir.Services.SessionManager
  alias GreenElixir.{Accounts, Beatmaps, Assets}

  # Social Features
  def get_friends(conn, %{"u" => username, "h" => password_hash}) do
    with {:ok, session} <- authenticate_user(username, password_hash),
         {:ok, friends} <- Accounts.get_user_friends(session.user_id) do
      friends_list = format_friends_list(friends)
      text(conn, friends_list)
    else
      {:error, :authentication_failed} ->
        text(conn, "error: pass")

      {:error, _} ->
        text(conn, "error: no")
    end
  end

  def upload_screenshot(conn, %{"u" => username, "p" => password_hash, "ss" => screenshot}) do
    with {:ok, session} <- authenticate_user(username, password_hash),
         {:ok, screenshot_url} <- Assets.save_screenshot(session, screenshot) do
      text(conn, screenshot_url)
    else
      {:error, :authentication_failed} ->
        text(conn, "error: pass")

      {:error, _} ->
        text(conn, "error: upload")
    end
  end

  def lastfm_check(conn, %{"us" => username, "ha" => password_hash, "b" => query}) do
    with {:ok, session} <- authenticate_user(username, password_hash) do
      case handle_lastfm_flags(query, session) do
        :ok -> text(conn, "")
        {:error, reason} -> text(conn, reason)
      end
    else
      {:error, :authentication_failed} ->
        text(conn, "error: pass")
    end
  end

  # Beatmap Management
  def add_favourite(conn, %{"u" => username, "h" => password_hash, "a" => beatmapset_id}) do
    with {:ok, session} <- authenticate_user(username, password_hash),
         {beatmapset_id, ""} <- Integer.parse(beatmapset_id),
         {:ok, _} <- Beatmaps.add_favourite(session.user_id, beatmapset_id) do
      text(conn, "")
    else
      {:error, :authentication_failed} ->
        text(conn, "error: pass")

      {:error, :beatmap_not_found} ->
        text(conn, "error: beatmap")

      _ ->
        text(conn, "error: beatmap")
    end
  end

  def get_favourites(conn, %{"u" => username, "h" => password_hash}) do
    with {:ok, session} <- authenticate_user(username, password_hash),
         {:ok, favourites} <- Beatmaps.get_user_favourites(session.user_id) do
      favourites_list = Enum.join(favourites, "\n")
      text(conn, favourites_list)
    else
      {:error, :authentication_failed} ->
        text(conn, "error: pass")

      {:error, _} ->
        text(conn, "")
    end
  end

  def get_beatmap_info(conn, _params) do
    # This is a dummy response for multiplayer matches
    # Based on Sunrise implementation - returns dummy data to satisfy client
    dummy_response =
      0..99
      |> Enum.map(fn i -> "#{i}||||1|N|N|N|N" end)
      |> Enum.join("\n")

    text(conn, dummy_response)
  end

  # Client Integration
  def bancho_connect(conn, _params) do
    # Simple OK response for bancho connection check
    text(conn, "")
  end

  def osu_session(conn, _params) do
    # Session endpoint - just return OK
    text(conn, "")
  end

  def mark_as_read(conn, _params) do
    # Mark messages as read - just return OK
    text(conn, "")
  end

  def check_updates(conn, _params) do
    # Redirect to official osu! update check to maintain compatibility
    query_string = if conn.query_string != "", do: "?" <> conn.query_string, else: ""
    redirect(conn, external: "https://osu.ppy.sh/web/check-updates.php#{query_string}")
  end

  def get_seasonal(conn, _params) do
    # Get seasonal backgrounds
    case Assets.get_seasonal_backgrounds() do
      {:ok, backgrounds} ->
        text(conn, backgrounds)

      {:error, _reason} ->
        # Fallback to official osu! seasonal backgrounds
        redirect(conn, external: "https://osu.ppy.sh/web/osu-getseasonal.php")
    end
  end

  def osu_error(conn, _params) do
    # Error reporting endpoint - just acknowledge
    text(conn, "")
  end

  # Helper functions
  defp authenticate_user(username, password_hash) do
    case SessionManager.authenticate_by_credentials(username, password_hash) do
      {:ok, session} -> {:ok, session}
      {:error, _} -> {:error, :authentication_failed}
    end
  end

  defp format_friends_list(friends) do
    friends
    |> Enum.map(fn friend -> "#{friend.id}\t#{friend.username}" end)
    |> Enum.join("\n")
  end

  defp handle_lastfm_flags(query, session) do
    if String.length(query) < 2 or String.at(query, 0) != "a" do
      {:error, "-3"}
    else
      flags_str = String.slice(query, 1..-1)

      case Integer.parse(flags_str) do
        {flags, ""} ->
          check_lastfm_flags(flags, session)

        _ ->
          {:error, "-3"}
      end
    end
  end

  defp check_lastfm_flags(flags, session) do
    # Check for specific flags and restrict user if necessary
    cond do
      # HqAssembly or HqFile flags
      (flags &&& 0x10) != 0 or (flags &&& 0x20) != 0 ->
        Accounts.restrict_user(session.user_id, "hq!osu found running")
        {:error, "-3"}

      # Registry edits flag
      (flags &&& 0x08) != 0 ->
        Accounts.restrict_user(session.user_id, "Registry edits detected")
        {:error, "-3"}

      true ->
        :ok
    end
  end
end
