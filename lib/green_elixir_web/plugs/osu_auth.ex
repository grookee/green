defmodule GreenElixirWeb.Plugs.OsuAuth do
  import Plug.Conn
  alias GreenElixir.Services.SessionManager

  def init(opts), do: opts

  def call(conn, _opts) do
    case extract_credentials(conn) do
      {:ok, username, password_hash} ->
        case SessionManager.authenticate_by_credentials(username, password_hash) do
          {:ok, session} ->
            assign(conn, :current_session, session)

          {:error, _} ->
            conn
            |> send_resp(200, "error: pass")
            |> halt()
        end

      {:error, _} ->
        conn
        |> send_resp(200, "error: pass")
        |> halt()
    end
  end

  defp extract_credentials(conn) do
    case conn.params do
      %{"us" => username, "ha" => password_hash} ->
        {:ok, username, password_hash}

      %{"pass" => password_hash} ->
        case extract_username_from_score(conn.params) do
          {:ok, username} -> {:ok, username, password_hash}
          {:error, _} -> {:error, :missing_credentials}
        end

      _ ->
        {:error, :missing_credentials}
    end
  end

  defp extract_username_from_score(%{
         "score" => score_encoded,
         "iv" => iv,
         "osuver" => osu_version
       }) do
    case GreenElixir.Utils.OsuCrypto.decode_score_data(score_encoded, iv, osu_version) do
      {:ok, decrypted} ->
        case String.split(decrypted, "|") do
          [_hash, username | _] -> {:ok, username}
          _ -> {:error, :invalid_format}
        end

      {:error, _} ->
        {:error, :decryption_failed}
    end
  end

  defp extract_username_from_score(_) do
    {:error, :missing_score_data}
  end
end
