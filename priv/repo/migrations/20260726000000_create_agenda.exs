defmodule Sortir.Cinema.Repo.Migrations.CreateAgenda do
  use Ecto.Migration

  def change do
    create table(:venues) do
      add :slug, :string, null: false
      add :name, :string, null: false
      add :city, :string, null: false
      add :kind, :string, null: false
      add :url, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:venues, [:slug])

    create table(:events) do
      # Identity is (source, external_id): the source's own key, kept internal.
      add :source, :string, null: false
      add :external_id, :string, null: false
      add :slug, :string, null: false

      add :title, :string, null: false
      add :description, :text
      # Best effort — often empty, and never used to build the title.
      add :artists, {:array, :string}, null: false, default: []

      add :category, :string, null: false
      # The venue's own vocabulary, verbatim. Normalising across sources means
      # a mapping table that is wrong for every venue you add next.
      add :labels, {:array, :string}, null: false, default: []

      add :image_url, :string
      add :url, :string

      # Exhibitions run continuously and have no occurrences; they live here.
      add :runs_from, :date
      add :runs_to, :date

      timestamps(type: :utc_datetime)
    end

    create unique_index(:events, [:source, :external_id])
    create index(:events, [:runs_from])

    create table(:occurrences) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      # On the occurrence, not the event: a touring show plays several venues.
      add :venue_id, references(:venues, on_delete: :restrict), null: false

      add :room, :string
      add :starts_at, :utc_datetime, null: false
      # Nullable and never inferred: many venues publish only a start time.
      add :ends_at, :utc_datetime

      add :status, :string, null: false, default: "unknown"
      # Cents, ascending. Venues publish tiers, not one price.
      add :prices, {:array, :integer}, null: false, default: []
      add :ticket_url, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:occurrences, [:event_id, :venue_id, :starts_at])
    create index(:occurrences, [:starts_at])
  end
end
