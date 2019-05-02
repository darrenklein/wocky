defmodule Wocky.Notifier.Push.LogTest do
  use Wocky.DataCase, async: true

  alias Wocky.Notifier.Push.Log

  @attrs [:user_id, :device, :token, :response]

  test "required attributes" do
    changeset = Log.insert_changeset(%{})
    refute changeset.valid?

    for a <- @attrs do
      assert "can't be blank" in errors_on(changeset)[a]
    end
  end
end