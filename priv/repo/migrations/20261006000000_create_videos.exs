defmodule Sortir.Core.Repo.Migrations.CreateVideos do
  use Ecto.Migration

  def change do
    create table(:videos) do
      add :youtube_id, :string, null: false
      # Stored so a search can match it, never rendered: it spoils the result.
      add :title, :string, null: false
      add :published_at, :utc_datetime, null: false
      add :views, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:videos, [:youtube_id])
    create index(:videos, [:published_at])
  end
end
