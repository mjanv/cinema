defmodule Cinema.Repo.Migrations.CreateCacheEntries do
  use Ecto.Migration

  def change do
    create table(:cache_entries, primary_key: false) do
      add :namespace, :string, primary_key: true
      add :key, :string, primary_key: true
      add :value, :binary, null: false
      add :stored_at, :bigint, null: false
    end
  end
end
