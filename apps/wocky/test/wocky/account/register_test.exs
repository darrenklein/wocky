defmodule Wocky.Account.RegisterTest do
  use Wocky.DataCase, async: true

  alias Wocky.Account.Register
  alias Wocky.Account.User
  alias Wocky.Repo
  alias Wocky.Repo.ID

  @required_attrs [:external_id]

  @create_attrs %{
    provider: "test_provider",
    external_id: "1234567890",
    phone_number: "+12104445484",
    password: "password",
    pass_details: "details"
  }

  describe "changeset/1" do
    test "should pass with valid attributes" do
      id = ID.new()

      changeset =
        Register.changeset(%{
          id: id,
          provider: "local",
          external_id: "bar"
        })

      assert changeset.valid?
      assert changeset.changes.id == id
    end

    test "should fail if missing required attributes" do
      changeset = Register.changeset(%{})
      refute changeset.valid?

      for a <- @required_attrs do
        assert "can't be blank" in errors_on(changeset)[a]
      end
    end
  end

  describe "get_external_id/1" do
    test "when the user has an external id" do
      %{external_id: external_id} = user = Factory.build(:user)
      assert {:ok, ^external_id} = Register.get_external_id(user)
    end

    test "when the user does not have an external id" do
      user = Factory.insert(:user, external_id: nil)
      {:ok, external_id} = Register.get_external_id(user)

      assert external_id

      user2 = Repo.get(User, user.id)
      assert user2.external_id == external_id
    end
  end

  describe "find/3" do
    setup do
      user = Factory.insert(:user)
      {:ok, user: user}
    end

    test "when the user does not exist" do
      assert {:error, :not_found} = Register.find("foo", "bar", "baz")
    end

    test "finding user by external id", %{user: u} do
      assert {:ok, user} = Register.find(u.provider, u.external_id, "foo")
      assert user.phone_number == "foo"
    end

    test "finding user by phone number", %{user: u} do
      assert {:ok, user} = Register.find("testp", "testid", u.phone_number)
      assert user.provider == "testp"
      assert user.external_id == "testid"
    end
  end

  describe "create/2" do
    test "with valid attributes" do
      assert {:ok, user} = Register.create(@create_attrs)

      user_attrs = Map.from_struct(user)
      for {k, v} <- @create_attrs, do: assert(user_attrs[k] == v)
    end

    test "with defaults" do
      assert {:ok, user} = Register.create(%{})
      assert user.external_id
      assert user.provider == "local"
    end
  end

  describe "find_or_create/4" do
    setup do
      user = Factory.insert(:user)
      {:ok, id: user.id, user: user}
    end

    test "when a user with the same provider/ID exists", %{user: user} do
      phone_number = Factory.phone_number()

      assert {:ok, {%User{} = new_user, false}} =
               Register.find_or_create(
                 user.provider,
                 user.external_id,
                 phone_number
               )

      assert new_user.id == user.id
      assert new_user.provider == user.provider
      assert new_user.external_id == user.external_id
      assert new_user.phone_number == phone_number
    end

    test "when a user with the same phone number exists", %{user: user} do
      external_id = Factory.external_id()

      assert {:ok, {%User{} = new_user, false}} =
               Register.find_or_create(
                 "test_provider",
                 external_id,
                 user.phone_number
               )

      assert new_user.id == user.id
      assert new_user.provider == "test_provider"
      assert new_user.external_id == external_id
      assert new_user.phone_number == user.phone_number
    end

    test "when the user does not exist" do
      external_id = Factory.external_id()
      phone_number = Factory.phone_number()

      assert {:ok, {%User{} = new_user, true}} =
               Register.find_or_create(
                 "test_provider",
                 external_id,
                 phone_number
               )

      assert new_user.provider == "test_provider"
      assert new_user.external_id == external_id
      assert new_user.phone_number == phone_number
    end
  end
end
