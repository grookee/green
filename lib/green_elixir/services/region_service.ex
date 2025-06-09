defmodule GreenElixir.Services.RegionService do
  @moduledoc """
  Service for handling IP geolocation and region-based restrictions.
  """

  @banned_ips Application.compile_env(:green_elixir, :banned_ips, [])

  def is_ip_banned?(ip) do
    ip in @banned_ips
  end

  def get_region(ip) do
    # Oversimplified
    {:ok,
     %{
       ip: ip,
       country: "XX",
       region: "Unknown"
     }}
  end

  def get_user_ip_from_conn(conn) do
    # Extract IP from connection, considering proxies if needed
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [ip | _] ->
        ip |> String.split(",") |> List.first() |> String.trim()

      [] ->
        case Plug.Conn.get_req_header(conn, "x-real-ip") do
          [ip | _] -> ip |> String.split(",") |> List.first() |> String.trim()
          [] -> to_string(:inet.ntoa(conn.remote_ip))
        end
    end
  end
end
