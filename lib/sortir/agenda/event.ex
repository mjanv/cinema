defmodule Sortir.Agenda.Event do
  @moduledoc """
  A programmed work: a concert, play, exhibition, screening or tour.

  An event is the production itself, independent of when it happens.
  `Sortir.Agenda.Occurrence` records one date it is performed — a play running
  on five nights is one event with five occurrences.

  Identity is `(source, external_id)`, the venue's own key, kept internal:
  two scrapers cannot collide, and re-scraping upserts rather than duplicates.
  The public `slug` is derived from the title, so re-sourcing an event does not
  break a link to it.

  An exhibition has no occurrences and is placed by `runs_from`/`runs_to`
  instead. `artists` is best-effort and may be empty; `labels` keeps the
  venue's own genre words verbatim rather than mapping them to a fixed
  vocabulary.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Sortir.Agenda.Occurrence

  @categories ~w(concert club_night performing_arts exhibition guided_tour screening talk other)a

  @type t :: %__MODULE__{}

  schema "events" do
    field(:source, :string)
    field(:external_id, :string)
    field(:slug, :string)

    field(:title, :string)
    field(:description, :string)
    # Best effort. Venues publish lineups as free text — "ACTRESS M b2b
    # MOODFINO + KENDAL + MALAGO" — and a bad split is worse than none, so this
    # may be empty and the title is never derived from it.
    field(:artists, {:array, :string}, default: [])

    field(:category, Ecto.Enum, values: @categories, default: :other)
    # The venue's own words, verbatim. One venue uses twelve categories, another
    # uses music genres; mapping them to a shared enum means a table that is
    # wrong for every source added next.
    field(:labels, {:array, :string}, default: [])

    field(:image_url, :string)
    field(:url, :string)

    # An exhibition runs continuously and has no occurrences: it lives here.
    field(:runs_from, :date)
    field(:runs_to, :date)

    has_many(:occurrences, Occurrence)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :source,
      :external_id,
      :title,
      :description,
      :artists,
      :category,
      :labels,
      :image_url,
      :url,
      :runs_from,
      :runs_to
    ])
    |> validate_required([:source, :external_id, :title])
    |> put_slug()
    |> validate_run()
    |> unique_constraint([:source, :external_id])
  end

  defp put_slug(changeset) do
    case get_field(changeset, :title) do
      nil -> changeset
      title -> put_change(changeset, :slug, slug(title))
    end
  end

  defp validate_run(changeset) do
    from = get_field(changeset, :runs_from)
    to = get_field(changeset, :runs_to)

    if from && to && Date.compare(to, from) == :lt do
      add_error(changeset, :runs_to, "must not be before the start of the run")
    else
      changeset
    end
  end

  @doc """
  A URL-safe slug for a title.

  Accents fold to ASCII and everything else collapses to single hyphens, so
  `COMPLET • Meryl` becomes `complet-meryl`.
  """
  @spec slug(String.t()) :: String.t()
  def slug(title) when is_binary(title) do
    title
    |> String.normalize(:nfd)
    |> String.replace(~r/[\x{0300}-\x{036F}]/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  @doc "The coarse categories used for filtering."
  def categories, do: @categories
end
