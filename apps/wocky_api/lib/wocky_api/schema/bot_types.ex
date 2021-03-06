defmodule WockyAPI.Schema.BotTypes do
  @moduledoc """
  Absinthe types for wocky bot
  """

  use WockyAPI.Schema.Notation

  alias WockyAPI.Resolvers.Bot
  alias WockyAPI.Resolvers.Media

  # -------------------------------------------------------------------
  # Objects

  enum :subscription_type do
    @desc "A user who is subscribed to the bot"
    value :subscriber

    @desc """
    A user who is subscribed to the bot and who is currently visiting it
    """
    value :visitor
  end

  @desc "A Wocky bot"
  object :bot do
    @desc "The bot's unique ID"
    field :id, non_null(:uuid)

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
    field :media, :media, resolve: &Media.get_media/3

    @desc "The type of the bot (freeform string, client-side use only)"
    field :type, :string

    @desc "The icon for the bot (freeform string, client-side use only)"
    field :icon, :string

    @desc "The bot's street address"
    field :address, :string

    @desc "Extra address data (freeform string, client-side use only)"
    field :address_data, :string

    @desc "The bot's owner"
    field :owner, non_null(:user), resolve: dataloader(Wocky, :user)

    @desc "Initial creation time of the bot"
    field :created_at, non_null(:datetime)

    @desc "Last time the bot was updated"
    field :updated_at, non_null(:datetime)

    @desc "Posts made to the bot"
    connection field :items, node_type: :bot_items do
      connection_complexity()
      resolve &Bot.get_items/3
    end

    @desc """
    Subscribers to the bot, filtered by either subscription type or user ID
    """
    connection field :subscribers, node_type: :subscribers do
      connection_complexity()
      arg :type, :subscription_type
      arg :id, :uuid
      resolve &Bot.get_subscribers/3
    end
  end

  @desc "A post (comment, etc) to a bot"
  object :bot_item do
    @desc "The unique ID of this post"
    field :id, non_null(:string)

    @desc "The post's content"
    field :content, :string

    @desc "Media contained in the post"
    field :media, :media, do: resolve(&Media.get_media/3)

    @desc "Initial creation time of the post"
    field :created_at, non_null(:datetime)

    @desc "Last time the post was updated"
    field :updated_at, non_null(:datetime)

    @desc "The post's owner"
    field :owner, :user, resolve: dataloader(Wocky, :user)
  end

  @desc "An invitation to subscribe to a bot"
  object :bot_invitation do
    @desc "The unique ID of the invitation"
    field :id, non_null(:aint)

    @desc "The user who sent the invitation"
    field :user, non_null(:user), resolve: dataloader(Wocky)

    @desc "The recipient of the invitation"
    field :invitee, non_null(:user), resolve: dataloader(Wocky)

    @desc "The bot to which the recipient has been invited"
    field :bot, non_null(:bot), resolve: dataloader(Wocky)

    @desc """
    Whether the invitation has been accepted (true), declined (false), or
    not yet responded to (null)
    """
    field :accepted, :boolean
  end

  object :local_bots do
    @desc "The bots found in the requested area"
    field :bots, non_null(list_of(:bot))

    @desc """
    If true, the area requested was too large to search and no bots will be
    returned
    """
    field :area_too_large, :boolean
  end

  object :local_bots_cluster do
    @desc "Individual bots that have not been clustered"
    field :bots, non_null(list_of(:bot))

    @desc "Clusters of geographically proximate bots"
    field :clusters, non_null(list_of(:bot_cluster))

    @desc """
    If true, the area requested was too large to search and no bots will be
    returned
    """
    field :area_too_large, :boolean
  end

  object :bot_cluster do
    @desc "The number of bots in this cluster"
    field :count, non_null(:integer)

    @desc "The cluster's latitude in degrees"
    field :lat, non_null(:float), resolve: &Bot.get_lat/3

    @desc "The cluster's longitude in degrees"
    field :lon, non_null(:float), resolve: &Bot.get_lon/3
  end

  # -------------------------------------------------------------------
  # Connections

  connection :bots, node_type: :bot do
    total_count_field()

    edge do
      @desc "The set of relationships between the user and the bot"
      field :relationships, list_of(:user_bot_relationship) do
        resolve &Bot.get_bot_relationships/3
      end
    end
  end

  connection :bot_items, node_type: :bot_item do
    total_count_field()

    edge do
    end
  end

  connection :subscribers, node_type: :user do
    total_count_field()

    edge do
      @desc "The set of relationships this subscriber has to the bot"
      field :relationships, non_null(list_of(:user_bot_relationship)) do
        resolve &Bot.get_bot_relationships/3
      end
    end
  end

  # -------------------------------------------------------------------
  # Queries

  @desc "A point on the globe"
  input_object :point do
    @desc "Latitude in degrees"
    field :lat, non_null(:float)

    @desc "Longitude in degrees"
    field :lon, non_null(:float)
  end

  object :bot_queries do
    @desc "Retrieve a single bot by ID"
    field :bot, :bot do
      arg :id, non_null(:uuid)
      resolve &Bot.get_bot/2
    end

    @desc """
    Retrieve owned and subscribed bots in a given region. The query will return
    an empty list of bots if the search radius (the diagonal of the rectangle)
    exceeds #{Bot.max_local_bots_search_radius()} meters.
    """
    field :local_bots, non_null(:local_bots) do
      @desc "Top left of the rectangle in which to search"
      arg :point_a, non_null(:point)

      @desc "Bottom right point of the rectangle in which to search"
      arg :point_b, non_null(:point)

      @desc """
      Maximum bots to return (default is #{Bot.default_local_bots()},
      maximum is #{Bot.max_local_bots()})
      """
      arg :limit, :integer

      resolve &Bot.get_local_bots/2
    end

    @desc """
    Similar to localBots, however multiple geographically proximate bots are
    clustered into single results. Clustering is controlled by the latDivs and
    lonDivs arguments. The search area is divided up into a grid of
    latDivs by lonDivs points and bots are grouped to the nearest point to them.
    Points that have more than one grouped bot are reported as clusters, while
    bots that were the only ones grouped to their point are reported
    individually.

    Like localBots, the search radius is limited to
    #{Bot.max_local_bots_search_radius()} meters.
    """
    field :local_bots_cluster, non_null(:local_bots_cluster) do
      @desc "Top left of the rectangle in which to search"
      arg :point_a, non_null(:point)

      @desc "Bottom right point of the rectangle in which to search"
      arg :point_b, non_null(:point)

      @desc """
      The number of divisions along the latitudinal axis into which to group
      clusters
      """
      arg :lat_divs, non_null(:integer)

      @desc """
      The number of divisions along the longitudinal axis into which to group
      clusters
      """
      arg :lon_divs, non_null(:integer)

      resolve &Bot.get_local_bots_cluster/2
    end
  end

  # -------------------------------------------------------------------
  # Mutations

  @desc "Parameters for creating and updating a bot"
  input_object :bot_params do
    field :title, :string

    field :lat, :float
    field :lon, :float
    field :radius, :float
    field :description, :string
    field :shortname, :string
    field :image_url, :string
    field :type, :string
    field :icon, :string
    field :address, :string
    field :address_data, :string
  end

  input_object :bot_create_input do
    field :values, non_null(:bot_params)

    @desc "Optional location to immediately apply to user against bot"
    field :user_location, :user_location_update_input
  end

  payload_object(:bot_create_payload, :bot)

  input_object :bot_update_input do
    @desc "ID of bot to update"
    field :id, non_null(:uuid)

    field :values, non_null(:bot_params)

    @desc "Optional location to immediately apply to user against bot"
    field :user_location, :user_location_update_input
  end

  payload_object(:bot_update_payload, :bot)

  input_object :bot_delete_input do
    @desc "ID of bot to delete"
    field :id, non_null(:uuid)
  end

  payload_object(:bot_delete_payload, :boolean)

  input_object :bot_subscribe_input do
    @desc "ID of bot to which to subscribe"
    field :id, non_null(:uuid)

    @desc "Optional location to immediately apply to user against bot"
    field :user_location, :user_location_update_input

    @desc "Whether to enable guest functionality for the user (default: false)"
    field :guest, :boolean
  end

  payload_object(:bot_subscribe_payload, :boolean)

  input_object :bot_unsubscribe_input do
    @desc "ID of the bot from which to unsubscribe"
    field :id, non_null(:uuid)
  end

  payload_object(:bot_unsubscribe_payload, :boolean)

  input_object :bot_item_publish_input do
    @desc "ID of the bot containing the item"
    field :bot_id, non_null(:uuid)

    @desc """
    ID for the item. If this is not supplied, a new one will be generated.
    NOTE: For backwards compatability, supplying a non-existant ID will
    create a new item with an unrelated ID different from the one provided.
    """
    field :id, :string

    @desc "Content of the item"
    field :content, :string

    @desc "URL for an image attached to the item"
    field :image_url, :string
  end

  payload_object(:bot_item_publish_payload, :bot_item)

  input_object :bot_item_delete_input do
    @desc "ID of the bot containing the item"
    field :bot_id, non_null(:uuid)

    @desc "ID of the item to delete"
    field :id, non_null(:uuid)
  end

  payload_object(:bot_item_delete_payload, :boolean)

  input_object :bot_invite_input do
    @desc "ID of the bot to which the user is invited"
    field :bot_id, non_null(:uuid)

    @desc "Users to invite"
    field :user_ids, non_null(list_of(non_null(:uuid)))
  end

  payload_object(:bot_invite_payload, :bot_invitation)

  input_object :bot_invitation_respond_input do
    @desc "ID of the invitation being replied to"
    field :invitation_id, non_null(:aint)

    @desc "Whether the invitation is accepted (true) or declined (false)"
    field :accept, non_null(:boolean)

    @desc "Optional location to immediately apply to user against bot"
    field :user_location, :user_location_update_input
  end

  payload_object(:bot_invitation_respond_payload, :boolean)

  object :bot_mutations do
    @desc "Create a new bot"
    field :bot_create, type: :bot_create_payload do
      arg :input, :bot_create_input
      resolve &Bot.bot_create/2
      middleware WockyAPI.Middleware.RefreshCurrentUser
      changeset_mutation_middleware()
    end

    @desc "Update an existing bot"
    field :bot_update, type: :bot_update_payload do
      arg :input, non_null(:bot_update_input)
      resolve &Bot.bot_update/2
      changeset_mutation_middleware()
    end

    @desc "Delete a bot"
    field :bot_delete, type: :bot_delete_payload do
      arg :input, non_null(:bot_delete_input)
      resolve &Bot.bot_delete/2
      changeset_mutation_middleware()
    end

    @desc "Subscribe the current user to a bot"
    field :bot_subscribe, type: :bot_subscribe_payload do
      arg :input, non_null(:bot_subscribe_input)
      resolve &Bot.bot_subscribe/2
      changeset_mutation_middleware()
    end

    @desc "Unsubscribe the current user from a bot"
    field :bot_unsubscribe, type: :bot_unsubscribe_payload do
      arg :input, non_null(:bot_unsubscribe_input)
      resolve &Bot.bot_unsubscribe/2
      changeset_mutation_middleware()
    end

    @desc "Publish an item to a bot"
    field :bot_item_publish, type: :bot_item_publish_payload do
      arg :input, non_null(:bot_item_publish_input)
      resolve &Bot.bot_item_publish/2
      changeset_mutation_middleware()
    end

    @desc "Delete an item from a bot"
    field :bot_item_delete, type: :bot_item_delete_payload do
      arg :input, non_null(:bot_item_delete_input)
      resolve &Bot.bot_item_delete/2
      changeset_mutation_middleware()
    end

    @desc "Invite users to a bot"
    field :bot_invite, type: list_of(:bot_invite_payload) do
      arg :input, non_null(:bot_invite_input)
      resolve &Bot.bot_invite/2
      changeset_list_mutation_middleware()
    end

    @desc "Respond to an invititation"
    field :bot_invitation_respond, type: :bot_invitation_respond_payload do
      arg :input, non_null(:bot_invitation_respond_input)
      resolve &Bot.bot_invitation_respond/2
      changeset_mutation_middleware()
    end
  end

  # -------------------------------------------------------------------
  # Subscriptions

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

    @desc "The time at which this visitor action occurred"
    field :updated_at, :datetime
  end

  object :bot_subscriptions do
    @desc """
    Receive updates on all visitors to all bots of which the current user is
    a guest
    """
    field :bot_guest_visitors, non_null(:visitor_update) do
      user_subscription_config(&Bot.visitor_subscription_topic/1)
    end
  end
end
