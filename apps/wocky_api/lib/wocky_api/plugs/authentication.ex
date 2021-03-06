defmodule WockyAPI.Plugs.Authentication do
  @moduledoc "Plugs for performing token authentication"

  import Plug.Conn

  alias Plug.Conn
  alias Wocky.Account

  @spec check_location_auth(Conn.t(), Keyword.t()) :: Conn.t()
  def check_location_auth(conn, _opts \\ []) do
    authenticate(conn, &Account.authenticate_for_location/1)
  end

  @spec check_auth(Conn.t(), Keyword.t()) :: Conn.t()
  def check_auth(conn, _opts \\ []) do
    authenticate(conn, &Account.authenticate/1)
  end

  defp authenticate(conn, auth) do
    header = conn |> get_req_header("authentication") |> List.first()

    case parse_jwt_header(header) do
      {:ok, nil} -> conn
      {:ok, token} -> do_authenticate(conn, token, auth)
      {:error, error} -> fail_authentication(conn, error)
    end
  end

  defp parse_jwt_header(nil), do: {:ok, nil}

  defp parse_jwt_header("Bearer " <> token), do: {:ok, String.trim(token)}

  defp parse_jwt_header(_header), do: {:error, :bad_request}

  defp do_authenticate(conn, token, auth) do
    case auth.(token) do
      {:ok, %{user: user, device: device}} ->
        conn
        |> assign(:current_user, user)
        |> assign(:current_user_id, user.id)
        |> assign(:device, device)

      {:ok, user_id} when is_binary(user_id) ->
        conn
        |> assign(:current_user_id, user_id)

      {:error, _} ->
        fail_authentication(conn)
    end
  end

  @spec ensure_authenticated(Conn.t(), Keyword.t()) :: Conn.t()
  def ensure_authenticated(conn, _opts \\ []) do
    if Map.get(conn.assigns, :current_user_id) do
      conn
    else
      fail_authentication(conn)
    end
  end

  defp fail_authentication(conn, reason \\ :unauthorized),
    do: conn |> send_resp(reason, "") |> halt()

  @spec ensure_owner(Conn.t(), Keyword.t()) :: Conn.t()
  def ensure_owner(conn, _opts \\ []) do
    path_user = conn.path_params["user_id"]
    user_id = Map.get(conn.assigns, :current_user_id)

    if is_nil(path_user) || user_id == path_user do
      conn
    else
      fail_authentication(conn, :forbidden)
    end
  end
end
