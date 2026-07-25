defmodule Cinema.Repo.Migrations.AddOban do
  use Ecto.Migration

  def up, do: Oban.Migration.up()

  # Leaves the tables in place: dropping the job history on a rollback would
  # lose the record of what was fetched and when.
  def down, do: Oban.Migration.down(version: 1)
end
