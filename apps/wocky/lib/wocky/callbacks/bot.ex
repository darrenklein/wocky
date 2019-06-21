defmodule Wocky.Callbacks.Bot do
  @moduledoc """
  Callbacks for DB bot changes
  """

  use DawdleDB.Handler, type: Wocky.POI.Bot

  alias Wocky.Location
  alias Wocky.POI
  alias Wocky.POI.Bot
  alias Wocky.Relation
  alias Wocky.Repo
  alias Wocky.Repo.Hydrator
  alias Wocky.Waiter

  def handle_insert(new) do
    Hydrator.with_assocs(new, [:user], fn rec = %{user: user} ->
      :ok = Relation.subscribe(user, rec)

      rec
      |> POI.sub_setup_event()
      |> Waiter.notify()
    end)
  end

  def handle_update(%Bot{location: new} = bot, %Bot{location: old})
      when new != old do
    bot_with_subs = Repo.preload(bot, [:subscribers])

    for user <- bot_with_subs.subscribers do
      Location.add_subscription(user, bot)
    end
  end

  def handle_update(_new, _old), do: :ok
end
