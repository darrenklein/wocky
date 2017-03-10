defmodule Wocky.UserSpec do
  use ESpec, async: true

  alias Wocky.ID
  alias Wocky.Repo
  alias Wocky.User

  before do
    id = ID.new
    external_id = ID.new
    :ok =
      %User{id: id, server: shared.server, external_id: external_id}
      |> User.update
    :ok = User.wait_for_user(id)
    {:ok, id: id, external_id: external_id}
  end

  finally do
    User.delete(shared.server, shared.id)
  end

  describe "register_user/3" do
    context "when the user already exists" do
      before do
        {:ok, result} =
          User.register("another_server", shared.external_id, "+15551234567")

        {:shared, result: result}
      end

      it "returns the ID of the existing user" do
        {result_id, _, _} = shared.result
        result_id |> should(eq shared.id)
      end

      it "returns the server of the existing user" do
        {_, result_server, _} = shared.result
        result_server |> should(eq shared.server)
        result_server |> should_not(eq "another_server")
      end

      it "returns 'false' in the last slot" do
        {_, _, result_is_new} = shared.result
        result_is_new |> should_not(be_true())
      end
    end

    context "when the user does not exist" do
      before do
        {:ok, result} =
          User.register(shared.server, ID.new, "+15551234567")

        {:shared, result: result}
      end

      finally do
        {id, _, _} = shared.result
        User.delete(shared.server, id)
      end

      it "creates the user and returns its ID" do
        {result_id, _, _} = shared.result
        obj = Repo.find("users", shared.server, result_id)
        obj |> should_not(be_nil())
      end

      it "returns the server that was passed in" do
        {_, result_server, _} = shared.result
        result_server |> should(eq shared.server)
      end

      it "returns 'true' in the last slot" do
        {_, _, result_is_new} = shared.result
        result_is_new |> should(be_true())
      end
    end
  end

  describe "delete/2" do
    before do
      result = User.delete(shared.server, shared.id)
      {:ok, result: result}
    end

    it "should return :ok" do
      shared.result |> should(eq :ok)
    end

    it "should remove the user from the database" do
      shared.server |> User.find(shared.id) |> should(be_nil())
    end

    it "should remove any tokens associated with the user"

    it "should remove any location data associated with the user"

    it "should succeed if the user does not exist" do
      shared.server
      |> User.delete(ID.new)
      |> should(eq :ok)

      "nosuchserver"
      |> User.delete(shared.id)
      |> should(eq :ok)
    end
  end
end
