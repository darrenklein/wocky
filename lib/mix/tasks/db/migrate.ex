defmodule Mix.Tasks.Db.Migrate do
  use Mix.Task
  alias Mix.Wocky
  alias Schemata.Migrator

  @moduledoc "Runs the database migrations"
  @shortdoc "Runs the database migrations"

  def run(args) do
    Wocky.start_app(args)

    success =
      case Migrator.migrate(:up) do
        {:ok, _} -> true
        {:error, _} -> false
      end
    Wocky.set_error_exit(!success)
  end
end
