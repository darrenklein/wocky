defmodule Wocky.LocationTest do
  use Wocky.DataCase

  alias Wocky.{Bot, Location, Repo, Repo.Factory, Repo.Timestamp, Roster}
  alias Wocky.Location.{BotEvent, Share, UserLocation}

  setup do
    user = Factory.insert(:user)

    {:ok, user: user, id: user.id}
  end

  describe "set_location/2" do
    setup ctx do
      user2 = Factory.insert(:user)
      bot = Factory.insert(:bot, user: user2)

      Roster.befriend(ctx.user, user2)
      Bot.subscribe(bot, ctx.user)

      {:ok, bot: bot, lat: Bot.lat(bot), lon: Bot.lon(bot)}
    end

    test "should save the location to the database", ctx do
      location = %UserLocation{
        lat: ctx.lat,
        lon: ctx.lon,
        accuracy: 10,
        device: "testing",
        captured_at: DateTime.utc_now()
      }

      assert {:ok, %UserLocation{id: id}} =
               Location.set_user_location(ctx.user, location)

      assert Repo.get(UserLocation, id)
    end

    test "should initiate geofence processing", ctx do
      assert Location.set_user_location(
               ctx.user,
               "testing",
               ctx.lat,
               ctx.lon,
               10
             ) == :ok

      assert BotEvent.get_last_event_type(ctx.id, ctx.bot.id) == :transition_in
    end
  end

  describe "set_location_for_bot/3" do
    setup ctx do
      user2 = Factory.insert(:user)
      bot = Factory.insert(:bot, user: user2)

      Roster.befriend(ctx.user, user2)
      Bot.subscribe(bot, ctx.user)

      location = %UserLocation{
        lat: Bot.lat(bot),
        lon: Bot.lon(bot),
        accuracy: 10,
        device: "testing",
        captured_at: DateTime.utc_now()
      }

      {:ok, bot: bot, location: location}
    end

    test "should save the location to the database", ctx do
      assert {:ok, %UserLocation{id: id}} =
               Location.set_user_location_for_bot(
                 ctx.user,
                 ctx.location,
                 ctx.bot
               )

      assert Repo.get(UserLocation, id)
    end

    test "should initiate geofence processing for that bot", ctx do
      assert {:ok, _} =
               Location.set_user_location_for_bot(
                 ctx.user,
                 ctx.location,
                 ctx.bot
               )

      assert Bot.subscription(ctx.bot, ctx.user) == :visiting
    end
  end

  describe "get_current_location/1" do
    test "should return the user's current location if known", ctx do
      location = Factory.build(:location)
      {:ok, _} = Location.set_user_location(ctx.user, location)

      loc2 = Location.get_current_user_location(ctx.user)
      assert loc2
      assert loc2.lat == location.lat
      assert loc2.lon == location.lon
      assert loc2.accuracy == location.accuracy
    end

    test "should return nil if the user's location is unknown", ctx do
      refute Location.get_current_user_location(ctx.user)
    end
  end

  describe "get_locations_query/2" do
    setup ctx do
      Factory.insert_list(5, :location, user_id: ctx.id, device: "test")

      :ok
    end

    test "should return a query for retrieving user locations", ctx do
      query = Location.get_user_locations_query(ctx.user, "test")

      assert query |> Repo.all() |> length() == 5
    end
  end

  defp setup_location_sharing(%{user: user}) do
    user2 = Factory.insert(:user)
    Roster.befriend(user, user2)

    {:ok, user2: user2}
  end

  defp sharing_expiry(days \\ 5) do
    Timestamp.shift(days: days)
    |> DateTime.truncate(:second)
  end

  describe "start_sharing_location/3" do
    setup :setup_location_sharing

    test "should create a share record", ctx do
      expiry = sharing_expiry()

      assert {:ok, _} =
               Location.start_sharing_location(ctx.user, ctx.user2, expiry)

      assert [%Share{} = share] = Location.get_location_shares(ctx.user)
      assert [%Share{} = ^share] = Location.get_location_sharers(ctx.user2)
      assert share.shared_with_id == ctx.user2.id
      assert share.expires_at == expiry
    end

    test "should update an existing share record", ctx do
      expiry1 = sharing_expiry(5)
      Location.start_sharing_location(ctx.user, ctx.user2, expiry1)

      expiry2 = sharing_expiry(6)

      assert {:ok, _} =
               Location.start_sharing_location(ctx.user, ctx.user2, expiry2)

      assert [%Share{} = share] = Location.get_location_shares(ctx.user)
      assert share.expires_at == expiry2
    end

    test "should not share location with a stranger", ctx do
      expiry = sharing_expiry()
      stranger = Factory.insert(:user)

      assert {:error, _} =
               Location.start_sharing_location(ctx.user, stranger, expiry)

      assert Location.get_location_shares(ctx.user) == []
    end

    test "should not create an expired share", ctx do
      expiry = sharing_expiry(-1)

      assert {:error, _} =
               Location.start_sharing_location(ctx.user, ctx.user2, expiry)

      assert Location.get_location_shares(ctx.user) == []
    end

    test "should not share with self", ctx do
      expiry = sharing_expiry()

      assert {:error, _} =
               Location.start_sharing_location(ctx.user, ctx.user, expiry)

      assert Location.get_location_shares(ctx.user) == []
    end
  end

  describe "stop_sharing_location/2" do
    setup :setup_location_sharing

    test "should remove existing location share", ctx do
      expiry = sharing_expiry()
      Location.start_sharing_location(ctx.user, ctx.user2, expiry)

      assert :ok = Location.stop_sharing_location(ctx.user, ctx.user2)
      assert Location.get_location_shares(ctx.user) == []
    end

    test "should succeed if no location share exists", ctx do
      stranger = Factory.insert(:user)

      assert :ok = Location.stop_sharing_location(ctx.user, stranger)
    end
  end

  describe "stop_sharing_location/1" do
    setup :setup_location_sharing

    test "should remove existing location share", ctx do
      expiry = sharing_expiry()
      Location.start_sharing_location(ctx.user, ctx.user2, expiry)

      assert :ok = Location.stop_sharing_location(ctx.user)
      assert Location.get_location_shares(ctx.user) == []
    end

    test "should succeed if no location share exists", ctx do
      assert :ok = Location.stop_sharing_location(ctx.user)
    end
  end

  describe "get_location_shares/1" do
    setup :setup_location_sharing

    test "should not return expired location shares", ctx do
      share = %Share{
        user: ctx.user,
        shared_with: ctx.user2,
        expires_at: sharing_expiry(-1)
      }

      Repo.insert!(share)

      assert Location.get_location_shares(ctx.user) == []
    end
  end

  describe "get_location_sharers/1" do
    setup :setup_location_sharing

    test "should not return expired location shares", ctx do
      share = %Share{
        user: ctx.user,
        shared_with: ctx.user2,
        expires_at: sharing_expiry(-1)
      }

      Repo.insert!(share)

      assert Location.get_location_sharers(ctx.user2) == []
    end
  end
end
