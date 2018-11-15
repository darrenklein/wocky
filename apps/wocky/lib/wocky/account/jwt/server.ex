defmodule Wocky.Account.JWT.Server do
  @moduledoc """
  Generates and validates JWTs used for uploading user location updates.
  """
  use Guardian,
    otp_app: :wocky,
    issuer: "Wocky",
    verify_issuer: true,
    secret_key:
      "+K+XxznYgxCGLa5hZo9Qyb7QtpmmRPOgNXM4UYfKViYnuiIjTySItwSk7rH+Uv2g",
    ttl: {4, :weeks},
    token_verify_module: Wocky.Account.JWT.Verify

  alias Wocky.Repo
  alias Wocky.User

  def default_token_type, do: "location"

  def subject_for_token(%User{} = user, _claims) do
    {:ok, user.id}
  end

  def subject_for_token(_resource, _claims) do
    {:error, :unknown_resource}
  end

  def resource_from_claims(%{"sub" => user_id} = _claims) do
    case Repo.get(User, user_id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  def resource_from_claims(_claims) do
    {:error, :not_possible}
  end

  def build_claims(claims, _resource, _opts), do: {:ok, claims}
end
