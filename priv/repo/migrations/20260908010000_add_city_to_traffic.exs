defmodule Cinema.Repo.Migrations.AddCityToTraffic do
  use Ecto.Migration

  # `city` joins the primary key, and SQLite cannot alter one in place, so the
  # table is rebuilt. Nothing is carried over: the counter has never run
  # anywhere but a development box, and its rows have no key to file under a
  # city they were never recorded with.
  def up do
    drop table(:traffic)

    create table(:traffic, primary_key: false) do
      add :bucket, :string, primary_key: true
      add :path, :string, primary_key: true
      add :city, :string, primary_key: true
      add :count, :integer, null: false, default: 0
    end
  end

  def down do
    drop table(:traffic)

    create table(:traffic, primary_key: false) do
      add :bucket, :string, primary_key: true
      add :path, :string, primary_key: true
      add :count, :integer, null: false, default: 0
    end
  end
end
