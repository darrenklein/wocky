defmodule Wocky.Audit do
  @moduledoc "Context for user audit logging"

  use Wocky.Config

  import Ecto.Query

  alias Ecto.Changeset
  alias Timex.Duration
  alias Wocky.Account
  alias Wocky.Account.User
  alias Wocky.Audit.TrafficLog
  alias Wocky.Repo

  # ===================================================================
  # Traffic logging

  @doc "Write a packet record to the database"
  @spec log_traffic(map(), User.t(), Keyword.t()) ::
          {:ok, TrafficLog.t() | nil} | {:error, Changeset.t()}
  def log_traffic(fields, user, opts \\ []) do
    config = config(opts)

    if should_log?(:traffic, user, config) do
      fields
      |> TrafficLog.changeset()
      |> Repo.insert()
    else
      {:ok, nil}
    end
  end

  @spec get_traffic_by_period(User.id(), DateTime.t(), Duration.t()) ::
          [TrafficLog.t()]
  def get_traffic_by_period(user_id, start, duration) do
    TrafficLog
    |> users_traffic(user_id, start, duration)
    |> Repo.all()
  end

  @spec get_traffic_by_device(User.id(), binary, DateTime.t(), Duration.t()) ::
          [TrafficLog.t()]
  def get_traffic_by_device(user_id, device, start, duration) do
    TrafficLog
    |> device_traffic(user_id, device, start, duration)
    |> Repo.all()
  end

  defp users_traffic(query, user_id, startt, duration) do
    endt = Timex.add(startt, duration)

    from t in query,
      where: t.user_id == ^user_id,
      where: t.created_at >= ^startt,
      where: t.created_at <= ^endt,
      select: t,
      order_by: [asc: :created_at]
  end

  defp device_traffic(query, user_id, device, startt, duration) do
    query = users_traffic(query, user_id, startt, duration)
    from t in query, where: t.device == ^device
  end

  # ===================================================================
  # Helpers

  defp should_log?(mode, user, config) do
    (user && Account.hippware?(user)) || Map.get(config, config_key(mode))
  end

  defp config_key(mode), do: String.to_existing_atom("log_#{mode}")
end
