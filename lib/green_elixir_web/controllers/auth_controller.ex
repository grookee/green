defmodule GreenElixirWeb.AuthController do
  use GreenElixirWeb, :controller

  alias GreenElixir.{Accounts, Services.RegionService}

  def register(conn, params) do
    case extract_registration_data(conn) do
      {:ok, registration_data} ->
        handle_registration(conn, registration_data)

      {:error, reason} ->
        text(conn, "error: #{reason}")
    end
  end

  defp extract_registration_data(conn) do
    # Extract form data from request body
    case conn.body_params do
      %{"user" => %{"username" => username, "user_email" => email, "password" => password}} ->
        {:ok, %{username: username, email: email, password: password}}

      # Alternative form format
      %{"username" => username, "email" => email, "password" => password} ->
        {:ok, %{username: username, email: email, password: password}}

      _ ->
        # Try to parse from raw body if needed
        parse_raw_registration_data(conn.body_params)
    end
  end

  defp parse_raw_registration_data(params) when is_map(params) do
    required_fields = ["username", "email", "password"]

    case Enum.all?(required_fields, &Map.has_key?(params, &1)) do
      true ->
        {:ok,
         %{
           username: params["username"],
           email: params["email"],
           password: params["password"]
         }}

      false ->
        {:error, "missing_fields"}
    end
  end

  defp parse_raw_registration_data(_), do: {:error, "invalid_format"}

  defp handle_registration(conn, %{username: username, email: email, password: password}) do
    user_ip = get_user_ip(conn)

    # Check if IP is banned
    if RegionService.is_ip_banned?(user_ip) do
      text(conn, "error: banned")
    else
      case Accounts.register_user(username, email, password, user_ip) do
        {:ok, user} ->
          # Registration successful
          text(conn, "ok")

        {:error, :username_taken} ->
          text(conn, "error: username")

        {:error, :email_taken} ->
          text(conn, "error: email")

        {:error, :invalid_username} ->
          text(conn, "error: username")

        {:error, :invalid_email} ->
          text(conn, "error: email")

        {:error, :weak_password} ->
          text(conn, "error: password")

        {:error, reason} ->
          text(conn, "error: #{reason}")
      end
    end
  end

  defp get_user_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [ip | _] ->
        ip |> String.split(",") |> List.first() |> String.trim()

      [] ->
        case get_req_header(conn, "x-real-ip") do
          [ip | _] -> ip
          [] -> to_string(:inet.ntoa(conn.remote_ip))
        end
    end
  end
end
