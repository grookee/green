defmodule GreenElixir.Bancho.Protocol do
  @moduledoc """
  Bancho protocol implementation for osu! client communication.
  """

  # Packet types from the original C# implementation
  @packet_types %{
    # Client -> Server
    client_change_action: 0,
    client_send_public_message: 1,
    client_logout: 2,
    client_request_status_update: 3,
    client_pong: 4,
    # ... more packet types

    # Server -> Client
    server_user_id: 5,
    server_command_error: 6,
    server_send_message: 7,
    server_ping: 8,
    server_handle_irc_change_username: 9
    # ... more packet types
  }

  def packet_type(name) when is_atom(name) do
    Map.get(@packet_types, name)
  end

  def decode_packet(
        <<packet_id::little-16, _::8, length::little-32, data::binary-size(length), rest::binary>>
      ) do
    packet_name = packet_name_from_id(packet_id)
    decoded_data = decode_packet_data(packet_name, data)

    {%{
       id: packet_id,
       type: packet_name,
       data: decoded_data
     }, rest}
  end

  def encode_packet(packet_type, data) when is_atom(packet_type) do
    packet_id = packet_type(packet_type)
    encoded_data = encode_packet_data(packet_type, data)
    data_length = byte_size(encoded_data)

    <<packet_id::little-16, 0::8, data_length::little-32, encoded_data::binary>>
  end

  # Packet data encoding/decoding functions
  defp encode_packet_data(:server_user_id, user_id) when is_integer(user_id) do
    <<user_id::little-32>>
  end

  defp encode_packet_data(:server_send_message, %{
         sender: sender,
         message: message,
         target: target,
         sender_id: sender_id
       }) do
    sender_bytes = encode_string(sender)
    message_bytes = encode_string(message)
    target_bytes = encode_string(target)

    <<sender_bytes::binary, message_bytes::binary, target_bytes::binary, sender_id::little-32>>
  end

  defp encode_packet_data(:server_user_presence, user_data) do
    # Encode user presence data
    user_id = Map.get(user_data, :user_id, 0)
    username = Map.get(user_data, :username, "")
    country = Map.get(user_data, :country, 0)

    username_bytes = encode_string(username)
    <<user_id::little-32, username_bytes::binary, country::8>>
  end

  defp decode_packet_data(:client_send_public_message, data) do
    {message, rest} = decode_string(data)
    {target, _rest} = decode_string(rest)

    %{message: message, target: target}
  end

  defp decode_packet_data(
         :client_change_action,
         <<action::8, action_text_length::8, action_text::binary-size(action_text_length),
           beatmap_md5_length::8, beatmap_md5::binary-size(beatmap_md5_length), mods::little-32,
           game_mode::8, beatmap_id::little-32>>
       ) do
    %{
      action: action,
      action_text: action_text,
      beatmap_md5: beatmap_md5,
      mods: mods,
      game_mode: game_mode,
      beatmap_id: beatmap_id
    }
  end

  # String encoding/decoding helpers
  defp encode_string(""), do: <<0::8>>

  defp encode_string(str) when is_binary(str) do
    length = byte_size(str)
    <<11::8, length::8, str::binary>>
  end

  defp decode_string(<<0::8, rest::binary>>), do: {"", rest}

  defp decode_string(<<11::8, length::8, str::binary-size(length), rest::binary>>) do
    {str, rest}
  end

  defp packet_name_from_id(id) do
    @packet_types
    |> Enum.find(fn {_name, packet_id} -> packet_id == id end)
    |> case do
      {name, _id} -> name
      nil -> :unknown
    end
  end
end
