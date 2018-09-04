defmodule WockyAPI.GraphQL.NotificationSubscriptionTest do
  use WockyAPI.SubscriptionCase, async: false

  import WockyAPI.ChannelHelper

  alias Wocky.Bot
  alias Wocky.Bot.{Invitation, Subscription}
  alias Wocky.Repo
  alias Wocky.Repo.Factory
  alias Wocky.Roster
  alias Wocky.User
  alias Wocky.Watcher.Client
  alias Wocky.Callbacks, as: WockyCallbacks
  alias WockyAPI.Callbacks

  setup_all do
    Client.clear_all_subscriptions()
    WockyCallbacks.register()
    Callbacks.register()
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    Application.start(:wocky_db_watcher)

    on_exit(fn ->
      Application.stop(:wocky_db_watcher)
      Repo.delete_all(User)
    end)
  end

  setup %{user: user} do
    user2 = Factory.insert(:user)
    bot = Factory.insert(:bot, user: user)
    Subscription.put(user2, bot)

    {:ok, user2: user2, bot: bot}
  end

  @subscription """
  subscription {
    notifications {
      data {
        __typename
        ... on BotItemNotification {
          user { id }
          bot { id }
          bot_item { id }
        }
        ... on GeofenceEventNotification {
          user { id }
          bot { id }
          event
        }
        ... on InvitationNotification {
          invitation { id }
          user { id }
          bot { id }
        }
        ... on InvitationResponseNotification {
          invitation { id }
          user { id }
          bot { id }
          accepted
        }
        ... on UserFollowNotification {
          user { id }
        }
      }
      created_at
    }
  }
  """
  describe "event notifications" do
    setup %{
      socket: socket,
      user: %{id: user_id},
      token: token
    } do
      authenticate(user_id, token, socket)
      ref = push_doc(socket, @subscription)
      assert_reply ref, :ok, %{subscriptionId: subscription_id}, 1000

      {:ok, ref: ref, subscription_id: subscription_id}
    end

    test "user posts item to bot", %{
      user2: user2,
      bot: bot,
      subscription_id: subscription_id
    } do
      item = Factory.insert(:item, user: user2, bot: bot)

      assert_push "subscription:data", push, 2000

      assert_notification_update(push, subscription_id, %{
        "__typename" => "BotItemNotification",
        "bot" => %{"id" => bot.id},
        "bot_item" => %{"id" => item.id},
        "user" => %{"id" => user2.id}
      })
    end

    test "user enters bot", %{
      user2: user2,
      bot: bot,
      subscription_id: subscription_id
    } do
      Bot.visit(bot, user2)

      assert_push "subscription:data", push, 2000

      assert_notification_update(push, subscription_id, %{
        "__typename" => "GeofenceEventNotification",
        "bot" => %{"id" => bot.id},
        "user" => %{"id" => user2.id},
        "event" => "ENTER"
      })
    end

    test "user exits bot", %{
      user2: user2,
      bot: bot,
      subscription_id: subscription_id
    } do
      Bot.depart(bot, user2)

      assert_push "subscription:data", push, 2000

      assert_notification_update(push, subscription_id, %{
        "__typename" => "GeofenceEventNotification",
        "bot" => %{"id" => bot.id},
        "user" => %{"id" => user2.id},
        "event" => "EXIT"
      })
    end

    test "user receives an invitation", %{
      user: user,
      user2: user2,
      subscription_id: subscription_id
    } do
      bot2 = Factory.insert(:bot, user: user2)
      {:ok, invitation} = Invitation.put(user, bot2, user2)

      assert_push "subscription:data", push, 2000

      assert_notification_update(push, subscription_id, %{
        "__typename" => "InvitationNotification",
        "invitation" => %{"id" => to_string(invitation.id)},
        "bot" => %{"id" => bot2.id},
        "user" => %{"id" => user2.id}
      })
    end

    test "user responds to an invitation", %{
      user: user,
      user2: user2,
      bot: bot,
      subscription_id: subscription_id
    } do
      invitation =
        Factory.insert(:invitation, user: user, invitee: user2, bot: bot)

      Invitation.respond(invitation, true, user2)

      assert_push "subscription:data", push, 2000

      assert_notification_update(push, subscription_id, %{
        "__typename" => "InvitationResponseNotification",
        "invitation" => %{"id" => to_string(invitation.id)},
        "bot" => %{"id" => bot.id},
        "user" => %{"id" => user2.id},
        "accepted" => true
      })
    end

    test "user follows", %{
      user: user,
      user2: user2,
      subscription_id: subscription_id
    } do
      Roster.follow(user2.id, user.id)

      assert_push "subscription:data", push, 2000

      assert_notification_update(push, subscription_id, %{
        "__typename" => "UserFollowNotification",
        "user" => %{"id" => user2.id}
      })
    end
  end

  defp assert_notification_update(push, subscription_id, data) do
    assert %{
             result: %{
               data: %{
                 "notifications" => %{
                   "created_at" => _,
                   "data" => ^data
                 }
               }
             },
             subscriptionId: ^subscription_id
           } = push
  end
end