defmodule Wocky.Notifier.Push.Backend.APNS do
  @moduledoc """
  Apple Push Notification Service implementation for wocky push system.
  """

  @behaviour Wocky.Notifier.Push.Backend

  use ModuleConfig, otp_app: :wocky

  alias Pigeon.APNS
  alias Pigeon.APNS.Error
  alias Pigeon.APNS.Notification
  alias Wocky.Notifier.Push.Event
  alias Wocky.Notifier.Push.Token
  alias Wocky.Notifier.Push.Utils

  require Logger

  @impl true
  def push(params) do
    :ok =
      params.event
      |> build_notification(params.token)
      |> APNS.push(on_response: params.on_response)

    :ok
  end

  @spec build_notification(Event.t(), Token.token()) :: Notification.t()
  def build_notification(event, token) do
    uri = Event.uri(event)
    opts = Event.opts(event)

    event
    |> Event.message()
    |> Utils.maybe_truncate_message()
    |> Notification.new(token, topic())
    |> Notification.put_custom(%{"uri" => uri})
    |> add_opts(opts)
  end

  @impl true
  def get_response(%Notification{response: response}), do: response

  @impl true
  def get_id(%Notification{id: id}), do: id

  @impl true
  def get_payload(%Notification{payload: payload}), do: payload

  @impl true
  def handle_error(:bad_device_token), do: :invalidate_token

  def handle_error(:unregistered), do: :invalidate_token

  def handle_error(_), do: :retry

  @impl true
  def error_msg(resp), do: Error.msg(resp)

  defp topic, do: get_config(:topic)

  defp add_opts(notification, opts) do
    notification
    |> maybe_add_badge(Keyword.get(opts, :badge))
    |> maybe_add_content_avail(Keyword.get(opts, :background, false))
    |> maybe_put(&Notification.put_sound/2, Keyword.get(opts, :sound))
    |> Notification.put_custom(Keyword.get(opts, :extra_fields, %{}))
  end

  defp maybe_add_badge(notification, nil), do: notification

  defp maybe_add_badge(notification, count),
    do: Notification.put_badge(notification, count)

  defp maybe_add_content_avail(notification, false), do: notification

  defp maybe_add_content_avail(notification, true) do
    %Notification{notification | priority: 5, push_type: "background"}
    |> Notification.put_content_available()
  end

  defp maybe_put(notification, _fun, nil),
    do: notification

  defp maybe_put(notification, fun, val),
    do: fun.(notification, val)
end
