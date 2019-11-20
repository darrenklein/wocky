defmodule Wocky.Events.LocationShare do
  @moduledoc "A user has started to share their location to the recipient"

  alias Wocky.Account.User

  defstruct [
    :to,
    :from,
    :share_id,
    :expires_at
  ]

  @type t :: %__MODULE__{
          to: User.t(),
          from: User.t(),
          share_id: non_neg_integer(),
          expires_at: DateTime.t()
        }
end

defimpl Wocky.Notifier.Push.Event, for: Wocky.Events.LocationShare do
  import Wocky.Notifier.Push.Utils

  @impl true
  def notify?(_), do: true

  @impl true
  def recipient(%{to: to}), do: to

  @impl true
  def message(%{from: from} = _event) do
    get_handle(from) <> " is sharing their location with you"
  end

  @impl true
  def uri(%{from: from} = _event), do: make_uri(:livelocation, from.id)

  @impl true
  def ignore_block?(_event), do: false

  @impl true
  def opts(_), do: []
end

defimpl Wocky.Notifier.InBand.Event, for: Wocky.Events.LocationShare do
  @impl true
  def notify?(_), do: true

  @impl true
  def event_type(_), do: :location_share

  @impl true
  def required_fields(_),
    do: [
      :expires_at,
      :other_user_id,
      :share_id,
      :user_id
    ]

  @impl true
  def transform(event),
    do: %{
      expires_at: event.expires_at,
      other_user_id: event.from.id,
      share_id: event.share_id,
      user_id: event.to.id
    }

  @impl true
  def ignore_block?(_event), do: false
end
