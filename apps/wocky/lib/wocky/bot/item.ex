defmodule Wocky.Bot.Item do
  @moduledoc "Represents an item published to a bot"

  use Wocky.Repo.Model

  alias Wocky.Bot
  alias Wocky.User
  alias __MODULE__, as: Item

  @foreign_key_type :binary_id
  @primary_key false
  schema "bot_items" do
    field :id,     :string, primary_key: true
    field :bot_id, :binary_id, primary_key: true
    field :stanza, :string
    field :image,  :boolean, default: false

    timestamps()

    belongs_to :bot, Bot, define_field: false
    belongs_to :user, User
  end

  @type id :: binary
  @type t :: %Item{}

  @spec changeset(t, map) :: Changeset.t
  def changeset(struct, params) do
    struct
    |> cast(params, [:id, :bot_id, :user_id, :stanza, :image])
    |> validate_required([:id, :bot_id, :user_id, :stanza])
    |> foreign_key_constraint(:bot_id)
    |> foreign_key_constraint(:user_id)
  end

  @spec get(Bot.t) :: [t]
  def get(bot) do
    bot
    |> items_query()
    |> order_by(asc: :updated_at)
    |> Repo.all
  end

  @spec get_count(Bot.t) :: non_neg_integer
  def get_count(bot) do
    bot
    |> assoc(:items)
    |> select([i], count(i.bot_id))
    |> Repo.one
  end

  @spec get_images(Bot.t) :: [t]
  def get_images(bot) do
    bot
    |> images_query()
    |> order_by(asc: :updated_at)
    |> Repo.all
  end

  @spec get_image_count(Bot.t) :: non_neg_integer
  def get_image_count(bot) do
    bot
    |> assoc(:items)
    |> where(image: true)
    |> select([i], count(i.bot_id))
    |> Repo.one
  end

  @spec get(Bot.t, id) :: t | nil
  def get(bot, id) do
    Repo.get_by(Item, id: id, bot_id: bot.id)
  end

  @spec put(Bot.t, User.t, id, binary, boolean) :: :ok | no_return
  def put(bot, user, id, stanza, image? \\ false) do
    %Item{}
    |> changeset(%{id: id, bot_id: bot.id, user_id: user.id,
                   stanza: stanza, image: image?})
    |> Repo.insert!(on_conflict: :replace_all, conflict_target: [:id, :bot_id])

    Bot.bump_update_time(bot)
  end

  @spec publish(Bot.t, User.t, id, binary, boolean) :: {:ok, t}
  def publish(bot, user, id, stanza, image?) do
    :ok = put(bot, user, id, stanza, image?)
    {:ok, get(bot, id)}
  end

  @spec delete(Bot.t) :: :ok
  def delete(bot) do
    bot
    |> assoc(:items)
    |> Repo.delete_all

    :ok
  end

  @spec delete(Bot.t, id) :: :ok
  def delete(bot, id) do
    bot
    |> assoc(:items)
    |> where(id: ^id)
    |> Repo.delete_all

    :ok
  end

  def items_query(bot) do
    bot
    |> assoc(:items)
  end

  def images_query(bot) do
    bot
    |> assoc(:items)
    |> where(image: true)
  end
end
