defmodule Cinema.Repo.Migrations.CreateTraffic do
  use Ecto.Migration

  def change do
    create table(:traffic, primary_key: false) do
      add :bucket, :string, primary_key: true
      add :path, :string, primary_key: true
      add :count, :integer, null: false, default: 0
    end
  end
end
