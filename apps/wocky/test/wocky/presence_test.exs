defmodule Wocky.PresenceTest do
  use Wocky.DataCase, async: false

  import Eventually

  alias Wocky.Account.User
  alias Wocky.Presence
  alias Wocky.Presence.Manager
  alias Wocky.Presence.PresenceEvent
  alias Wocky.Repo.Factory
  alias Wocky.Roster

  setup do
    [user, requestor] = Factory.insert_list(2, :user)
    Roster.befriend(user, requestor)

    {:ok, requestor: requestor, user: user}
  end

  describe "basic presence registration/deregistration" do
    test "presence registration", ctx do
      assert Presence.get(ctx.user, ctx.requestor).status == :offline

      {_, _} = connect(ctx.user)
      assert Presence.get(ctx.user, ctx.requestor).status == :offline

      Presence.set_status(ctx.user, :online)
      assert_eventually(Presence.get(ctx.user, ctx.requestor).status == :online)

      # Set the user's presence to offline and wait for it to register.
      # Doing this prevents a crash due to a db connection ownership error.
      Presence.set_status(ctx.user, :offline)

      assert_eventually(
        Presence.get(ctx.user, ctx.requestor).status == :offline
      )
    end

    test "presence deregistration on connection close", ctx do
      {conn, []} = connect(ctx.user)
      assert Presence.get(ctx.user, ctx.requestor).status == :offline

      Presence.set_status(ctx.user, :online)
      assert_eventually(Presence.get(ctx.user, ctx.requestor).status == :online)
      close_conn(conn)

      assert_eventually(
        Presence.get(ctx.user, ctx.requestor).status == :offline
      )
    end

    test "can get presence on self", ctx do
      {_, _} = connect(ctx.user)
      assert Presence.get(ctx.user, ctx.user).status == :offline

      Presence.set_status(ctx.user, :online)
      assert_eventually(Presence.get(ctx.user, ctx.user).status == :online)

      # Set the user's presence to offline and wait for it to register.
      # Doing this prevents a crash due to a db connection ownership error.
      Presence.set_status(ctx.user, :offline)

      assert_eventually(Presence.get(ctx.user, ctx.user).status == :offline)
    end
  end

  describe "initial manager response" do
    test "initial return value to `connect` should list online friends", ctx do
      uid = ctx.user.id

      assert {_, []} = connect(ctx.user)
      Presence.set_status(ctx.user, :online)

      assert {_, [%User{id: ^uid}]} = connect(ctx.requestor)
    end
  end

  defmodule TestHandler do
    @moduledoc false
    use Dawdle.Handler, only: [PresenceEvent]

    def handle_event(%{contact: u, recipient_id: c_id}) do
      Agent.update(:presence_proxy, fn _ -> {u.id, u.presence.status, c_id} end)
    end
  end

  defp get_presence_result do
    result = Agent.get(:presence_proxy, & &1)
    Agent.update(:presence_proxy, fn _ -> nil end)
    result
  end

  describe "publishing callback" do
    setup ctx do
      {:ok, _} = Agent.start_link(fn -> nil end, name: :presence_proxy)

      TestHandler.register()

      uid = ctx.user.id

      {_, []} = connect(ctx.user)
      Presence.set_status(ctx.user, :online)

      {conn_pid, [%User{id: ^uid}]} = connect(ctx.requestor)
      Presence.set_status(ctx.requestor, :online)

      on_exit(fn ->
        TestHandler.unregister()
      end)

      {:ok, conn_pid: conn_pid}
    end

    test "should publish an online state when a user sets themselves online",
         ctx do
      assert_eventually(
        {ctx.requestor.id, :online, ctx.user.id} ==
          get_presence_result()
      )
    end

    test "should not publish again when user sets their state online again",
         ctx do
      assert_eventually(
        {ctx.requestor.id, :online, ctx.user.id} ==
          get_presence_result()
      )

      Presence.set_status(ctx.requestor, :online)

      refute_eventually(get_presence_result())
    end

    test "should publish an offline state when a user sets themselves offline",
         ctx do
      Presence.set_status(ctx.requestor, :offline)

      assert_eventually(
        {ctx.requestor.id, :offline, ctx.user.id} ==
          get_presence_result()
      )
    end

    test "should not publish again if the user sets themselves offline twice",
         ctx do
      Presence.set_status(ctx.requestor, :offline)

      assert_eventually(
        {ctx.requestor.id, :offline, ctx.user.id} ==
          get_presence_result()
      )

      Presence.set_status(ctx.requestor, :offline)

      refute_eventually(get_presence_result())
    end

    test "should publish an offline state when a user disconnects", ctx do
      close_conn(ctx.conn_pid)

      assert_eventually(
        {ctx.requestor.id, :offline, ctx.user.id} ==
          get_presence_result()
      )
    end
  end

  describe "race condition tests" do
    test "get_presence race", ctx do
      {:ok, manager} = Manager.acquire(ctx.user)
      send(manager, {:exit_after, 1000})

      assert %Presence{status: :offline} =
               Manager.get_presence(manager, ctx.user)
    end
  end

  defp connect(user) do
    self = self()

    conn_pid =
      spawn_link(fn ->
        users = Presence.connect(user)
        send(self, {:connected, users})

        receive do
          :exit -> :ok
        end
      end)

    receive do
      {:connected, users} -> {conn_pid, users}
    end
  end

  defp close_conn(pid), do: send(pid, :exit)
end
