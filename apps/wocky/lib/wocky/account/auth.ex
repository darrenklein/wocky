defmodule Wocky.Account.Auth do
  @moduledoc """
  The Account context. Represents the backend bookkeeping required for users
  in the system (authentication, registration, deletion, etc).
  """

  use Elixometer

  alias FirebaseAdminEx.Auth, as: FirebaseAuth
  alias Wocky.Account.Agent
  alias Wocky.Account.ClientVersion
  alias Wocky.Account.JWT.Client, as: ClientJWT
  alias Wocky.Account.JWT.Firebase
  alias Wocky.Account.JWT.Server, as: ServerJWT
  alias Wocky.Account.Register
  alias Wocky.Account.User
  alias Wocky.Errors
  alias Wocky.PhoneNumber
  alias Wocky.Repo

  require Logger

  @type token :: String.t()

  @type auth_data :: %{user: User.t() | nil, device: User.device() | nil}

  # ====================================================================
  # JWT generation

  @spec get_location_jwt(User.t()) :: {:ok, String.t()} | {:error, any()}
  def get_location_jwt(%User{} = user) do
    with {:ok, token, _claims} <- ServerJWT.encode_and_sign(user) do
      {:ok, token}
    end
  end

  @spec authenticate_for_location(String.t()) ::
          {:ok, User.id()} | {:error, any()}
  def authenticate_for_location(token) do
    case JOSE.JWT.peek_payload(token).fields do
      %{"typ" => "location"} ->
        authenticate_with(:server_jwt, token, %{})

      %{"typ" => type} when type == "firebase" or type == "bypass" ->
        with {:ok, %{user: %User{id: id}}} <- authenticate(token) do
          {:ok, id}
        end

      _else ->
        {:error, :bad_token}
    end
  rescue
    ArgumentError -> {:error, :bad_token}
  end

  # ====================================================================
  # Authentication

  @spec authenticate(String.t()) :: {:ok, auth_data()} | {:error, any()}
  def authenticate(token) do
    case ClientJWT.decode_and_verify(token) do
      {:ok, %{"typ" => "firebase", "sub" => new_token} = claims} ->
        update_counter("auth.client_jwt.firebase.success", 1)
        authenticate_with(:firebase, new_token, claims)

      {:ok, %{"typ" => "bypass", "sub" => id, "phone_number" => phone} = claims} ->
        update_counter("auth.client_jwt.bypass.success", 1)
        authenticate_with(:bypass, {id, phone}, claims)

      {:ok, _claims} ->
        update_counter("auth.client_jwt.fail", 1)
        {:error, "Unable to authenticate wrapped entity"}

      {:error, reason} ->
        update_counter("auth.client_jwt.fail", 1)
        {:error, Errors.error_to_string(reason)}
    end
  end

  defp authenticate_with(:bypass, {external_id, phone_number}, opts) do
    if PhoneNumber.bypass?(phone_number) do
      find_or_create(:bypass, external_id, phone_number, opts)
    else
      provider_error(:bypass)
    end
  end

  defp authenticate_with(:firebase, token, opts) do
    case Firebase.decode_and_verify(token) do
      {:ok, %{"sub" => external_id, "phone_number" => phone_number}} ->
        update_counter("auth.firebase.success", 1)
        find_or_create(:firebase, external_id, phone_number, opts)

      {:error, reason} ->
        update_counter("auth.firebase.fail", 1)
        {:error, Errors.error_to_string(reason)}
    end
  end

  # Unlike the authenticate_with methods above, this only returns a user_id.
  # This is to avoid a DB lookup for each location upload.
  defp authenticate_with(:server_jwt, token, _opts) do
    case ServerJWT.decode_and_verify(token) do
      {:ok, %{"sub" => user_id}} ->
        update_counter("auth.server_jwt.success", 1)
        {:ok, user_id}

      {:error, reason} ->
        update_counter("auth.server_jwt.fail", 1)
        {:error, Errors.error_to_string(reason)}
    end
  end

  defp find_or_create(method, id, phone, opts) do
    with {:ok, {user, _}} <- Register.find_or_create(method, id, phone),
         {:ok, _} <- maybe_record_client_version(user, opts) do
      {:ok, %{user: user, device: opts["dvc"]}}
    end
  end

  defp maybe_record_client_version(user, %{"dvc" => device, "iss" => agent}) do
    with {:ok, version, attrs} <- Agent.parse(agent) do
      user
      |> Ecto.build_assoc(:client_versions)
      |> ClientVersion.changeset(%{
        device: device,
        version: version,
        attributes: attrs
      })
      |> Repo.insert(
        on_conflict: :replace_all,
        conflict_target: [:user_id, :device]
      )
    end
  end

  defp maybe_record_client_version(_, _), do: {:ok, nil}

  defp provider_error(p), do: {:error, "Unsupported provider: #{p}"}

  # ====================================================================
  # Account cleanup

  @spec cleanup(User.t()) :: :ok
  def cleanup(%{provider: "firebase", external_id: external_id, id: id}) do
    Errors.log_on_failure(
      "Deleting Firebase account for user #{id}",
      fn -> FirebaseAuth.delete_user(external_id) end
    )
  end

  def cleanup(_), do: :ok
end
