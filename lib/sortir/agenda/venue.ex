defmodule Sortir.Agenda.Venue do
  @moduledoc """
  A place that programmes events.

  Venue details come from the scraper's `venue/0` rather than from the pages it
  parses, and are upserted on `slug` at the start of each scrape — so renaming
  a venue takes effect on the next run without creating a second row.

  `slug` is the public identity, as elsewhere in this app. `kind` classifies
  the place, not what it programmes: a museum that hosts a concert is still
  `:museum`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @kinds ~w(music_hall theatre museum cinema other)a

  @type t :: %__MODULE__{}

  schema "venues" do
    field(:slug, :string)
    field(:name, :string)
    field(:city, :string)
    field(:kind, Ecto.Enum, values: @kinds, default: :other)
    field(:url, :string)

    has_many(:occurrences, Sortir.Agenda.Occurrence)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(venue, attrs) do
    venue
    |> cast(attrs, [:slug, :name, :city, :kind, :url])
    |> validate_required([:slug, :name, :city])
    |> unique_constraint(:slug)
  end

  @doc "The kinds a venue may be."
  def kinds, do: @kinds
end
