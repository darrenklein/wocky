defmodule Wocky.POI do
  @moduledoc "Schema and API for working with points of interest."

  use Elixometer

  import Ecto.Changeset
  import Ecto.Query

  alias Ecto.Multi
  alias Ecto.Queryable
  alias Geocalc.Point
  alias Wocky.Account
  alias Wocky.Account.User
  alias Wocky.Errors
  alias Wocky.POI.Bot
  alias Wocky.POI.Item
  alias Wocky.Repo
  alias Wocky.Repo.ID
  alias Wocky.Waiter

  require Logger
  require Record

  # ----------------------------------------------------------------------
  # Database interaction

  @spec get(Bot.id(), boolean()) :: Bot.t() | nil
  def get(id, include_pending \\ false)

  def get(id, include_pending) when is_binary(id) do
    id
    |> get_query(include_pending)
    |> Repo.one()
  end

  @doc false
  @spec get_query(Bot.id(), boolean()) :: Queryable.t()
  def get_query(id, include_pending \\ false) do
    Bot
    |> where(id: ^id)
    |> maybe_filter_pending(not include_pending)
  end

  @doc false
  @spec maybe_filter_pending(Queryable.t(), boolean()) :: Queryable.t()
  def maybe_filter_pending(queryable, false), do: queryable

  def maybe_filter_pending(queryable, true),
    do: where(queryable, pending: false)

  @spec preallocate(User.tid()) :: Repo.result(Bot.t())
  def preallocate(user) do
    params = %{id: ID.new(), user_id: User.id(user), pending: true}

    %Bot{}
    |> cast(params, [:id, :user_id, :pending])
    |> foreign_key_constraint(:user_id)
    |> Repo.insert()
  end

  @spec insert(map(), User.t()) :: {:ok, Bot.t()} | {:error, any()}
  def insert(params, requestor) do
    with {:ok, t} <- do_update(%Bot{}, params, &Repo.insert/1) do
      update_counter("bot.created", 1)

      Errors.log_on_failure(
        "Flagging bot created on user",
        fn -> Account.flag_bot_created(requestor) end
      )

      {:ok, t}
    end
  end

  @spec update(Bot.t(), map()) :: {:ok, Bot.t()} | {:error, any()}
  def update(bot, params) do
    do_update(bot, params, &Repo.update/1)
  end

  defp do_update(struct, params, op) do
    struct |> Bot.changeset(params) |> op.()
  end

  @spec delete(Bot.t()) :: :ok
  def delete(bot) do
    Repo.delete(bot)
    update_counter("bot.deleted", 1)
    :ok
  end

  @spec sub_setup_event(Bot.t()) :: Waiter.event()
  def sub_setup_event(bot), do: "bot_sub_setup-" <> bot.id

  # ----------------------------------------------------------------------
  # Location

  @spec lat(Bot.t()) :: float()
  def lat(%Bot{location: %Geo.Point{coordinates: {_, lat}}})
      when not is_nil(lat),
      do: lat

  @spec lon(Bot.t()) :: float()
  def lon(%Bot{location: %Geo.Point{coordinates: {lon, _}}})
      when not is_nil(lon),
      do: lon

  @spec location(Bot.t()) :: Point.t()
  def location(bot), do: %{lat: lat(bot), lon: lon(bot)}

  @doc "Returns the bot's distance from the specified location in meters."
  @spec distance_from(Bot.t(), Point.t()) :: float()
  def distance_from(bot, loc), do: Geocalc.distance_between(location(bot), loc)

  @doc "Returns true if the location is within the bot's radius."
  @spec contains?(Bot.t(), Point.t()) :: boolean()
  def contains?(bot, loc), do: Geocalc.within?(bot.radius, location(bot), loc)

  # ----------------------------------------------------------------------
  # Bot items

  @spec get_items(Bot.t()) :: [Item.t()]
  def get_items(bot) do
    bot |> get_items_query() |> Repo.all()
  end

  @spec get_items_query(Bot.t()) :: Queryable.t()
  def get_items_query(bot) do
    Ecto.assoc(bot, :items)
  end

  @spec get_item(Bot.t(), Item.id()) :: Item.t() | nil
  def get_item(bot, id) do
    Item
    |> where(id: ^id, bot_id: ^bot.id)
    |> Repo.one()
  end

  @spec put_item(Bot.t(), Item.id(), String.t(), String.t(), User.tid()) ::
          {:ok, Item.t()} | {:error, any()}
  def put_item(%{id: bot_id} = bot, id, content, image_url, user) do
    id_valid? = ID.valid?(id)
    id = if id_valid?, do: id, else: ID.new()
    user_id = User.id(user)

    case id_valid? && do_get_item(id) do
      x when is_nil(x) or x == false ->
        bot
        |> Ecto.build_assoc(:items)
        |> Item.changeset(%{
          id: id,
          user_id: user_id,
          content: content,
          image_url: image_url
        })
        |> do_upsert_item(bot)

      %Item{user_id: ^user_id, bot_id: ^bot_id} = old_item ->
        old_item
        |> Item.changeset(%{content: content, image_url: image_url})
        |> do_upsert_item(bot)

      _ ->
        {:error, :permission_denied}
    end
  end

  defp do_get_item(id) do
    # For some reason that I can't quite suss out, the upsert fails unless
    # the associations have been preloaded.
    Repo.one(
      from i in Item,
        where: i.id == ^id,
        preload: [:user, :bot]
    )
  end

  defp do_upsert_item(item_cs, bot) do
    opts = [
      on_conflict: {:replace, [:content, :image_url]},
      conflict_target: :id
    ]

    bot_cs = cast(bot, %{updated_at: DateTime.utc_now()}, [:updated_at])

    multi =
      Multi.new()
      |> Multi.insert(:item, item_cs, opts)
      |> Multi.update(:bot, bot_cs)

    case Repo.transaction(multi) do
      {:ok, %{item: item}} -> {:ok, item}
      {:error, _, cs, _} -> {:error, cs}
    end
  end

  @spec delete_item(Bot.t(), Item.id(), User.tid()) ::
          :ok | {:error, :not_found | :permission_denied}
  def delete_item(bot, id, user), do: do_delete_item(bot, id, User.id(user))

  defp do_delete_item(%Bot{user_id: user_id} = bot, id, user_id) do
    {deleted, _} =
      bot
      |> Ecto.assoc(:items)
      |> where(id: ^id)
      |> Repo.delete_all()

    case deleted do
      0 -> {:error, :not_found}
      1 -> :ok
    end
  end

  defp do_delete_item(bot, id, user_id) do
    case get_item(bot, id) do
      %Item{user_id: ^user_id} = item ->
        Repo.delete(item)
        :ok

      nil ->
        {:error, :not_found}

      _ ->
        {:error, :permission_denied}
    end
  end

  @spec delete_items(Bot.t(), User.tid()) :: :ok
  def delete_items(bot, user) do
    bot
    |> Ecto.assoc(:items)
    |> where(user_id: ^User.id(user))
    |> Repo.delete_all()

    :ok
  end
end
