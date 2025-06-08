defmodule GreenElixirWeb.ScoreController do
  use GreenElixirWeb, :controller

  alias GreenElixir.Scores
  alias GreenElixir.Services.SessionManager
  alias GreenElixirWeb.Utils.OsuCrypto

  def submit_score(conn, params) do
    with {:ok, session} <- authenticate_request(params),
         {:ok, score_data} <- decode_score_data(params),
         {:ok, score} <- Scores.submit_score(session, score_data) do
      response = format_score_response(score)
      text(conn, response)
    else
      {:error, :authentication_failed} ->
        text(conn, "error: pass")

      {:error, :invalid_score} ->
        text(conn, "error: no")

      {:error, reason} ->
        text(conn, "Error: #{reason}")
    end
  end

  def get_scores(conn, params) do
    with {:ok, session} <- authenticate_request(params),
         {:ok, scores} <- Scores.get_beatmap_scores(params) do
      response = format_scores_response(scores, session)
      text(conn, response)
    else
      {:error, _} ->
        text(conn, "error: pass")
    end
  end

  def get_replay(conn, %{"c" => score_id}) do
    case Scores.get_replay_data(score_id) do
      {:ok, replay_data} ->
        conn
        |> put_resp_content_type("application/octet-stream")
        |> send_resp(200, replay_data)

      {:error, _} ->
        text(conn, "Error: no-replay")
    end
  end

  defp authenticate_request(%{"u" => username, "ha" => password_hash}) do
    case SessionManager.authenticate_by_credentials(username, password_hash) do
      {:ok, session} ->
        {:ok, session}

      {:error, _} ->
        {:error, :authentication_failed}
    end
  end

  defp authenticate_request(%{"pass" => password_hash} = params) do
    with {:ok, score_data} <- decode_score_data(params),
         username <- extract_username_from_score(score_data) do
      authenticate_request(%{"us" => username, "ha" => password_hash})
    end
  end

  defp decode_score_data(%{"score" => score_encoded, "iv" => iv, "osuver" => osu_version}) do
    case OsuCrypto.decrypt_score_data(score_encoded, iv, osu_version) do
      {:ok, decrypted} -> parse_score_data(decrypted)
      {:error, _} -> {:error, :invalid_score}
    end
  end

  defp parse_score_data(score_string) do
    parts = String.split(score_string, "|")

    if length(parts) >= 13 do
      {:ok,
       %{
         score_hash: Enum.at(parts, 0),
         username: Enum.at(parts, 1),
         beatmap_md5: Enum.at(parts, 2),
         count_300: String.to_integer(Enum.at(parts, 3)),
         count_100: String.to_integer(Enum.at(parts, 4)),
         count_50: String.to_integer(Enum.at(parts, 5)),
         count_miss: String.to_integer(Enum.at(parts, 6)),
         count_katu: String.to_integer(Enum.at(parts, 7)),
         count_geki: String.to_integer(Enum.at(parts, 8)),
         max_combo: String.to_integer(Enum.at(parts, 9)),
         perfect: Enum.at(parts, 10) == "1",
         grade: Enum.at(parts, 11),
         mods: String.to_integer(Enum.at(parts, 12)),
         passed: Enum.at(parts, 13) == "True"
       }}
    else
      {:error, :invalid_format}
    end
  end

  defp extract_username_from_score(score_data) do
    Map.get(score_data, :username, "")
  end

  defp format_score_response(score) do
    header =
      "1|false|#{score.beatmap_id}|beatmapSetId:0|beatmapPlayCount:1|beatmapPassCount:1|approvedDate:2023-01-01\n\n"
  end

  defp format_scores_response(scores, session) do
    header = "1|false|#{List.first(scores).beatmap_id}|0|#{length(scores)}"
    chart_info = "0\nArtist - Title\n10.0"

    personal_best = Enum.find(scores, fn score -> score.user_id == session.user_id end)

    pb_line =
      if personal_best,
        do: format_score_line(personal_best),
        else: ""

    score_lines =
      scores
      |> Enum.take(50)
      |> Enum.map(&format_score_line/1)

    [header, chart_info, pb_line | score_lines]
    |> Enum.join("\n")
  end

  defp format_score_line(score) do
    "#{score.id}|#{score.user.username}|#{score.total_score}|#{score.max_combo}|" <>
      "#{score.count_50}|#{score.count_100}|#{score.count_300}|" <>
      "#{score.count_miss}|#{score.count_katu}|#{score.count_geki}|" <>
      "#{if score.perfect, do: "1", else: "0"}|" <>
      "#{score.mods}|#{score.user_id}|1|#{DateTime.to_unix(score.when_played)}|1"
  end
end
