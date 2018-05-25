defmodule WockyAPI.Schema.BotTypes do
  @moduledoc """
  Absinthe types for wocky bot
  """

  use WockyAPI.Schema.Notation
  use Absinthe.Ecto, repo: Wocky.Repo

  import Kronky.Payload

  alias WockyAPI.Resolvers.Bot
  alias WockyAPI.Resolvers.Collection
  alias WockyAPI.Resolvers.Media

  connection :bots, node_type: :bot do
    scope :public
    total_count_field

    edge do
      scope :public
      @desc "The set of relationships between the user and the bot"
      field :relationships, list_of(:user_bot_relationship) do
        resolve &Bot.get_bot_relationships/3
      end
    end
  end

  enum :subscription_type do
    @desc "A user who is subscribed to the bot"
    value :subscriber

    @desc """
    A user who is subscribed to the bot and is a guest
    (entry/exit will be reported)
    """
    value :guest

    @desc """
    A user who is subscribed to the bot and is a guest who is currently
    visiting the bot
    """
    value :visitor
  end

  @desc "A Wocky bot"
  object :bot do
    scope :public

    @desc "The bot's unique ID"
    field :id, non_null(:uuid)

    @desc "The server on which the bot resides"
    field :server, non_null(:string)

    @desc "The bot's title"
    field :title, non_null(:string)

    @desc "The bot's latitude in degrees"
    field :lat, non_null(:float), resolve: &Bot.get_lat/3

    @desc "The bot's longitude in degrees"
    field :lon, non_null(:float), resolve: &Bot.get_lon/3

    @desc "The bot's geofence radius in metres"
    field :radius, non_null(:float)

    @desc "The full description of the bot"
    field :description, :string

    @desc "The bot's unique short name"
    field :shortname, :string

    @desc "The bot's cover image"
    field :image, :media, resolve: &Media.get_media/3

    @desc "The type of the bot (freeform string, client-side use only)"
    field :type, :string

    @desc "The bot's street address"
    field :address, :string

    @desc "Extra address data (freeform string, client-side use only)"
    field :address_data, :string

    @desc "Whether the bot is publicly visible"
    field :public, non_null(:boolean)

    @desc "Whether the bot has geofence (visitor reporting) enabled"
    field :geofence, non_null(:boolean)

    @desc "The bot's owner"
    field :owner, non_null(:user), resolve: assoc(:user)

    @desc "Posts made to the bot"
    connection field :items, node_type: :bot_items do
      connection_complexity
      resolve &Bot.get_items/3
    end

    @desc "Subscribers to the bot, filtered by either subscription type or ID"
    connection field :subscribers, node_type: :subscribers do
      connection_complexity
      arg :type, :subscription_type
      arg :id, :uuid
      resolve &Bot.get_subscribers/3
    end

    @desc "Collections of which this bot is a member"
    connection field :collections, node_type: :collections do
      connection_complexity
      resolve &Collection.get_collections/3
    end
  end

  @desc "A post (comment, etc) to a bot"
  object :bot_item do
    scope :public

    @desc "The bot-unique ID of this post"
    field :id, non_null(:string)

    @desc "The post's content"
    field :stanza, :string

    @desc "Media contained in the post"
    field :media, :media, do: resolve(&Media.get_media/3)

    @desc "True if the post is an image post"
    field :image, :boolean

    @desc "The post's owner"
    field :owner, :user, resolve: assoc(:user)
  end

  connection :bot_items, node_type: :bot_item do
    scope :public
    total_count_field

    edge do
      scope :public
    end
  end

  connection :subscribers, node_type: :user do
    scope :public
    total_count_field

    edge do
      scope :public

      @desc "The set of relationships this subscriber has to the bot"
      field :relationships, non_null(list_of(:user_bot_relationship)) do
        resolve &Bot.get_bot_relationships/3
      end
    end
  end

  @desc "Parameters for creating and updating a bot"
  input_object :bot_params do
    field :title, :string
    field :server, :string
    field :lat, :float
    field :lon, :float
    field :radius, :float
    field :description, :string
    field :shortname, :string
    field :image, :string
    field :type, :string
    field :address, :string
    field :address_data, :string
    field :public, :boolean
    field :geofence, :boolean
  end

  input_object :bot_create_input do
    field :values, non_null(:bot_params)
  end

  input_object :bot_update_input do
    field :id, non_null(:uuid)
    field :values, non_null(:bot_params)
    field :user_location, :user_location_update_input
  end

  input_object :bot_item_params do
    @desc "ID for the item. If this is not supplied one will be generated"
    field :id, :string

    @desc "Content of them item"
    field :stanza, :string
  end

  input_object :bot_item_publish_input do
    @desc "ID of the bot containing the item"
    field :bot_id, non_null(:uuid)

    field :values, non_null(:bot_item_params)
  end

  input_object :bot_item_delete_input do
    @desc "ID of the bot containing the item"
    field :bot_id, non_null(:uuid)

    @desc "ID of the item to delete"
    field :id, non_null(:uuid)
  end

  payload_object(:bot_create_payload, :bot)
  payload_object(:bot_update_payload, :bot)
  payload_object(:bot_item_publish_payload, :bot_item)
  payload_object(:bot_item_delete_payload, :boolean)

  object :bot_queries do
    @desc "Retrive a single bot by ID"
    field :bot, :bot do
      scope :public
      arg :id, non_null(:uuid)
      resolve &Bot.get_bot/3
    end
  end

  object :bot_mutations do
    @desc "Create a new bot"
    field :bot_create, type: :bot_create_payload do
      arg :input, non_null(:bot_create_input)
      resolve &Bot.create_bot/3
      changeset_mutation_middleware
    end

    @desc "Update an existing bot"
    field :bot_update, type: :bot_update_payload do
      arg :input, non_null(:bot_update_input)
      resolve &Bot.update_bot/3
      changeset_mutation_middleware
    end

    @desc "Subscribe the current user to a bot"
    payload field :bot_subscribe do
      input do
        @desc "ID of bot to which to subscribe"
        field :id, non_null(:uuid)

        @desc """
        Whether to enable guest functionality for the user (default: false)
        """
        field :guest, :boolean
      end

      output do
        field :result, :boolean
      end

      resolve &Bot.subscribe/3
    end

    @desc "Unsubscribe the current user from a bot"
    payload field :bot_unsubscribe do
      input do
        @desc "ID of the bot from which to unsubscribe"
        field :id, non_null(:uuid)
      end

      output do
        field :result, :boolean
      end

      resolve &Bot.unsubscribe/3
    end

    @desc "Delete a bot"
    payload field :bot_delete do
      input do
        @desc "ID of bot to delete"
        field :id, non_null(:uuid)
      end

      output do
        field :result, :boolean
      end

      resolve &Bot.delete/3
    end

    @desc "Publish an item to a bot"
    field :bot_item_publish, type: :bot_item_publish_payload do
      arg :input, non_null(:bot_item_publish_input)
      resolve &Bot.publish_item/3
      changeset_mutation_middleware
    end

    @desc "Delete an item from a bot"
    field :bot_item_delete, type: :bot_item_delete_payload do
      arg :input, non_null(:bot_item_delete_input)
      resolve &Bot.delete_item/3
      changeset_mutation_middleware
    end
  end

  enum :visitor_action do
    @desc "A visitor newly arriving at a bot"
    value :arrive

    @desc "A visitor newly departing from a bot"
    value :depart
  end

  @desc "An update on the state of a visitor to a bot"
  object :visitor_update do
    @desc "The bot with the visitor"
    field :bot, :bot

    @desc "The user visiting"
    field :visitor, :user

    @desc "Whether the user has arrived or departed"
    field :action, :visitor_action
  end

  object :bot_subscriptions do
    @desc """
    Receive updates on all visitors to all bots of which the current user is
    a guest
    """
    field :bot_guest_visitors, non_null(:visitor_update) do
      config fn
        _, %{context: %{current_user: user}} ->
          {:ok, topic: Bot.visitor_subscription_topic(user.id)}

        _, _ ->
          {:error, "This operation requires an authenticated user"}
      end
    end
  end
end
