defmodule Wocky.BotSpec do
  use ESpec, async: true
  use ModelHelpers
  use Wocky.JID

  alias Wocky.Bot
  alias Wocky.Bot.Subscription
  alias Wocky.Bot.TempSubscription
  alias Wocky.Index.TestIndexer
  alias Wocky.Repo.Factory
  alias Wocky.Repo.ID

  before do
    TestIndexer.reset
  end

  describe "helper functions" do
    let :bot, do: Factory.build(:bot)

    describe "make_node/1" do
      subject do: Bot.make_node(bot())

      it do: should(eq "bot/" <> bot().id)
    end

    describe "to_jid/1" do
      subject do: Bot.to_jid(bot())

      it do: jid(subject(), :luser) |> should(eq "")
      it do: jid(subject(), :lserver) |> should(eq bot().server)
      it do: jid(subject(), :lresource) |> should(eq Bot.make_node(bot()))
    end

    describe "get_id_from_jid/1" do
      it do: bot() |> Bot.to_jid |> Bot.get_id_from_jid |> should(eq bot().id)
      it do: "bogus" |> Bot.get_id_from_jid |> should(be_nil())

      it do
        "bogus"
        |> JID.make("localhost", "testing")
        |> Bot.get_id_from_jid
        |> should(be_nil())
      end
    end

    describe "get_id_from_node/1" do
      it do
        bot()
        |> Bot.make_node
        |> Bot.get_id_from_node
        |> should(eq bot().id)
      end

      it do: "bogus" |> Bot.get_id_from_node |> should(be_nil())
    end

    describe "public?" do
      it do: bot() |> Bot.public? |> should(eq bot().public)
    end
  end

  describe "validations" do
    let :attrs do
      %{id: ID.new, server: "localhost", user_id: ID.new,
        title: "test bot", lat: 1.0, lon: 1.0, radius: 1000}
    end

    it "should pass with valid attributes" do
      %Bot{}
      |> Bot.changeset(attrs())
      |> should(be_valid())
    end

    it "should fail with missing fields" do
      %Bot{}
      |> Bot.changeset(%{})
      |> should(have_errors Map.keys(attrs()))
    end

    it "should fail with negative radius" do
      %Bot{}
      |> Bot.changeset(Map.put(attrs(), :radius, -1))
      |> should(have_errors [:radius])
    end

    it "should normalize latitude" do
      attrs = Map.put(attrs(), :lat, -95.0)
      changeset = Bot.changeset(%Bot{}, attrs)
      changeset.changes.lat |> should(eq 85.0)
    end

    it "should normalize longitude" do
      attrs = Map.put(attrs(), :lon, -185.0)
      changeset = Bot.changeset(%Bot{}, attrs)
      changeset.changes.lon |> should(eq 175.0)
    end

    it "should set pending to 'false'" do
      changeset = Bot.changeset(%Bot{}, attrs())
      changeset.changes.pending |> should(be_false())
    end
  end

  describe "database interactions" do
    let :user, do: Factory.insert(:user)
    let! :bot, do: Factory.insert(:bot, user: user())

    describe "preallocate/2" do
      let :preallocated, do: Bot.preallocate(user().id, user().server)

      it "returns a pending bot" do
        preallocated().pending |> should(be_true())
      end

      it "creates a bot in the database" do
        db_bot = Repo.get(Bot, preallocated().id)

        db_bot.server |> should(eq preallocated().server)
        db_bot.user_id |> should(eq preallocated().user_id)
      end

      it "raises on error" do
        fn -> Bot.preallocate(ID.new, "localhost") end
        |> should(raise_exception())
      end
    end

    describe "insert/1" do
      it "returns an ok result on success" do
        :bot
        |> Factory.params_for(user: user())
        |> Bot.insert
        |> should(be_ok_result())
      end

      it "returns an error result on failure" do
        %{} |> Bot.insert |> should(be_error_result())
      end

      context "full text search index", async: false do
        before do
          :bot |> Factory.params_for(user: user()) |> Bot.insert
          :ok
        end

        it "should be updated" do
          TestIndexer.get_index_operations |> should_not(be_empty())
        end
      end
    end

    describe "update/2" do
      it "returns an ok result on success" do
        bot()
        |> Bot.update(%{title: "updated bot"})
        |> should(be_ok_result())
      end

      it "returns an error result on failure" do
        %Bot{} |> Bot.update(%{}) |> should(be_error_result())
      end

      context "full text search index", async: false do
        before do
          Bot.update(bot(), %{title: "updated bot"})
          :ok
        end

        it "should be updated" do
          TestIndexer.get_index_operations |> should_not(be_empty())
        end
      end
    end

    describe "delete/1" do
      let! :result, do: Bot.delete(bot())

      it "should retun :ok" do
        result() |> should(eq :ok)
      end

      it "should remove the bot" do
        Repo.get(Bot, bot().id) |> should(be_nil())
      end

      it "should remove the bot from the full text search index" do
        TestIndexer.get_index_operations |> should_not(be_empty())
      end
    end

    describe "owner/1" do
      subject do: Bot.owner(bot())

      it do: should(eq user())
    end

    context "subscribers" do
      before do
        sub = Factory.insert(:user)
        temp_sub = Factory.insert(:user, resource: "testing")

        Subscription.put(sub, bot())
        TempSubscription.put(temp_sub, bot(), node())
      end

      describe "subscribers/1" do
        subject do: Bot.subscribers(bot())

        it do: should(have_length 2)
        it do: should_not(have user())
      end

      describe "subscriber_count/1" do
        subject do: Bot.subscriber_count(bot())

        it do: should(eq 3)
      end
    end
  end
end