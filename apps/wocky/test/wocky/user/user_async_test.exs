defmodule Wocky.User.UserAsyncTest do
  use Wocky.DataCase, async: false

  import Mock

  alias Wocky.{Block, User}
  alias Wocky.Repo.Factory

  setup do
    user =
      Factory.insert(:user,
        device: "testing",
        name: "name",
        handle: "handle"
      )

    {:ok,
     user: user,
     id: user.id,
     external_id: user.external_id,
     phone_number: user.phone_number}
  end

  describe "user deletion" do
    setup_with_mocks([
      {FirebaseAdminEx.Auth, [], [delete_user: fn _ -> :ok end]}
    ]) do
      :ok
    end

    test "should delete user's firebase account if they have one" do
      user = Factory.insert(:user, provider: "firebase")
      assert User.delete(user.id) == :ok

      assert_called(FirebaseAdminEx.Auth.delete_user(user.external_id))
    end

    test "should not delete user's firebase account if they don't have one" do
      user = Factory.insert(:user)
      assert User.delete(user.id) == :ok

      refute called(FirebaseAdminEx.Auth.delete_user(user.external_id))
    end
  end

  describe "search_by_name/3" do
    setup do
      users =
        [
          {"Alice Sanders", "Xena"},
          {"Alison Smith", "Yaniv"},
          {"Bob Jones", "Zena"},
          {"acéñtîâ CAPITAL", "1345"}
        ]
        |> Enum.map(fn {n, h} ->
          Factory.insert(:user, name: n, handle: h)
        end)

      {:ok, users: users}
    end

    test "should return all users with the search prefix in either name", ctx do
      assert User.search_by_name("a", ctx.user, 50) |> length() == 3
      assert User.search_by_name("b", ctx.user, 50) |> length() == 1
      assert User.search_by_name("s", ctx.user, 50) |> length() == 2
      assert User.search_by_name("smi", ctx.user, 50) |> length() == 1
      assert User.search_by_name("q", ctx.user, 50) |> length() == 0
      assert User.search_by_name("z", ctx.user, 50) |> length() == 1
      assert User.search_by_name("13", ctx.user, 50) |> length() == 1
    end

    test "should ignore accents in both search and data", ctx do
      assert User.search_by_name("acent", ctx.user, 50) |> length() == 1
      assert User.search_by_name("â", ctx.user, 50) |> length() == 3
    end

    test "should ignore capitalisation in both search and data", ctx do
      assert User.search_by_name("A", ctx.user, 50) |> length() == 3
      assert User.search_by_name("c", ctx.user, 50) |> length() == 1
    end

    test "should respect the limit parameter", ctx do
      assert User.search_by_name("a", ctx.user, 2) |> length() == 2
    end

    test "should ignore empty search terms and return an empty list", ctx do
      assert User.search_by_name("", ctx.user, 50) |> length() == 0
    end

    test "should work on multiple partial terms", ctx do
      assert User.search_by_name("ali s", ctx.user, 50) |> length() == 2
      assert User.search_by_name("ali sm", ctx.user, 50) |> length() == 1
    end

    test "should not choke on punctuation or other unicode weirdness", ctx do
      assert User.search_by_name("''ali", ctx.user, 50) |> length() == 2
      assert User.search_by_name("al-s", ctx.user, 50) |> length() == 0
      assert User.search_by_name("al''i", ctx.user, 50) |> length() == 2
      assert User.search_by_name("al''i", ctx.user, 50) |> length() == 2
      assert User.search_by_name("''-al''i", ctx.user, 50) |> length() == 2
    end

    test "should not return a blocking user", ctx do
      # Alice Sanders
      blocking_user = hd(ctx.users)
      Block.block(blocking_user, ctx.user)

      result = User.search_by_name("a", ctx.user, 50)

      assert length(result) == 2
      refute Enum.any?(result, fn %{id: id} -> id == blocking_user.id end)
    end
  end
end
