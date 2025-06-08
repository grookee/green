defmodule GreenElixir.Utils.OsuCrypto do
  @moduledoc """
  Cryptographic functions for osu! client communication.
  Handles Rijndael decryption and client validation.
  """

  @stable_key "osu!-scoreburgr---------"

  def decrypt_score_data(encoded_string, iv, osu_version) do
    try do
      key = @stable_key <> osu_version
      key_bytes = :binary.bin_to_list(key)
      iv_bytes = Base.decode64!(iv)
      encoded_bytes = Base.decode64!(encoded_string)

      # Use Erlang's crypto module for AES/Rijndael decryption
      decrypted =
        :crypto.crypto_one_time(
          :aes_256_cbc,
          :binary.list_to_bin(key_bytes),
          iv_bytes,
          encoded_bytes,
          false
        )

      # Remove PKCS7 padding
      decrypted = remove_pkcs7_padding(decrypted)

      {:ok, decrypted}
    rescue
      _ -> {:error, :decryption_failed}
    end
  end

  def verify_client_hash(client_hash, expected_values) do
    # Implement client hash verification logic
    # This is crucial for anti-cheat measures
    true
  end

  def generate_session_token do
    :crypto.strong_rand_bytes(32) |> Base.encode64()
  end

  defp remove_pkcs7_padding(data) do
    if byte_size(data) > 0 do
      padding_length = :binary.last(data)
      data_length = byte_size(data) - padding_length
      :binary.part(data, 0, data_length)
    else
      data
    end
  end
end
