defmodule Sortir.Agenda.Occurrence do
  @moduledoc """
  One date and place at which an event is performed.

  A concert has one occurrence, a touring play has many, an exhibition has
  none — it runs continuously and is placed by the event's
  `runs_from`/`runs_to` instead.

  The venue is recorded here rather than on the event so that a production can
  tour: the same show plays several places on different dates.

  `ends_at` is null unless the venue publishes an end time; it is never
  inferred from a typical running length. `status` defaults to `:unknown`,
  since most venues say nothing until a date sells out. `prices` are integer
  cents in ascending order.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(on_sale sold_out cancelled unknown)a

  @type t :: %__MODULE__{}

  schema "occurrences" do
    belongs_to(:event, Sortir.Agenda.Event)
    belongs_to(:venue, Sortir.Agenda.Venue)

    field(:room, :string)
    field(:starts_at, :utc_datetime)
    # Nullable and never inferred: many venues publish only a start time, and
    # guessing a duration would be invented data.
    field(:ends_at, :utc_datetime)

    field(:status, Ecto.Enum, values: @statuses, default: :unknown)
    # Cents, ascending. Venues publish tiers ("13 € - 14 € - 17 € - 19 €"),
    # not one price, and integers keep money away from floats.
    field(:prices, {:array, :integer}, default: [])
    field(:ticket_url, :string)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(occurrence, attrs) do
    occurrence
    |> cast(attrs, [
      :event_id,
      :venue_id,
      :room,
      :starts_at,
      :ends_at,
      :status,
      :prices,
      :ticket_url
    ])
    |> validate_required([:venue_id, :starts_at])
    |> validate_ends_after_start()
    |> unique_constraint([:event_id, :venue_id, :starts_at])
  end

  defp validate_ends_after_start(changeset) do
    starts = get_field(changeset, :starts_at)
    ends = get_field(changeset, :ends_at)

    if starts && ends && DateTime.compare(ends, starts) == :lt do
      add_error(changeset, :ends_at, "must not be before the start")
    else
      changeset
    end
  end

  @doc "The states a listed occurrence may be in."
  def statuses, do: @statuses
end
