defmodule GreenElixir.Accounts do
  @moduledoc """
  COntext for user accounts and authentication.
  """

  @password_min_length 8
  @username_regex ~r/^[a-zA-Z0-9_]{3,20}$/

  alias GreenElixir.Repo
  alias GreenElixir.Accounts.User
  import Ecto.Query

  def register_user(username, email, password, ip) do
    if not valid_username?(username) do
      {:error, :invalid_username}
    else
      case check_existing_user(username, email) do
        {:error, reason} ->
          {:error, reason}

        :ok ->
          if String.length(password) < @password_min_length do
            {:error, :weak_password}
          else
            hashed_password = hash_password(password)

            changeset =
              User.changeset(%User{}, %{
                username: username,
                email: email,
                password_hash: hashed_password,
                registration_ip: ip
              })

            case Repo.insert(changeset) do
              {:ok, user} -> {:ok, user}
              {:error, changeset} -> {:error, :database_error}
            end
          end
      end
    end
  end

  defp valid_username?(username) do
    Regex.match?(@username_regex, username)
  end

  defp check_existing_user(username, email) do
    query =
      from u in User,
        where: u.username == ^username or u.email == ^email,
        select: u

    case Repo.one(query) do
      nil -> :ok
      user when user.username == username -> {:error, :username_taken}
      user when user.email == email -> {:error, :email_taken}
    end
  end

  defp hash_password(password) do
    Argon2.hash_pwd_salt(password)
  end
end
