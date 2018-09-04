defmodule Wocky.Repo.Migrations.RemoveCollectionFromTriggerFuns do
  use Wocky.Repo.Migration

  alias Wocky.Repo.Migration.Utils

  def up do
    Utils.add_hs_delete_trigger_function("users", "reference_user_id")
    Utils.add_hs_delete_trigger_function("bots", "reference_bot_id")
    Utils.add_hs_delete_trigger_function("bot_items", "reference_bot_item_id")
    Utils.recreate_bot_private_trigger_function()
  end
end