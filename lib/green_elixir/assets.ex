defmodule GreenElixir.Assets do
  @moduledoc """
  Context for handling assets like screenshots and seasonal backgrounds.
  """

  alias GreenElixir.Services.SessionManager

  def save_screenshot(session, screenshot) do
    screenshots_dir = Path.join([:code.priv_dir(:green_elixir), "static", "screenshots"])
    File.mkdir_p!(screenshots_dir)

    timestamp = System.system_time(:second)
    filename = "#{session.user_id}_#{timestamp}_#{screenshot.filename}.png"
    file_path = Path.join(screenshots_dir, filename)

    case File.cp(screenshot.path, file_path) do
      :ok ->
        screenshot_url = "/screenshots/#{filename}"
        {:ok, screenshot_url}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_seasonal_backgrounds do
    backgrounds = [
      "https://assets.ppy.sh/seasonal/2024-winter-1.jpg",
      "https://assets.ppy.sh/seasonal/2024-winter-2.jpg"
    ]

    formatted_backgrounds = Enum.join(backgrounds, "|")
    {:ok, formatted_backgrounds}
  end
end
