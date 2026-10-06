defmodule Cinema.Screening do
  @moduledoc """
  A single projection of one movie, at one theater, at one time.

  Flat by design: AlloCiné nests showtimes under presentation buckets
  (`multiple`, `original_st`, ...) which are an artifact of their own UI.
  One screening per row makes grouping and filtering trivial.
  """

  @enforce_keys [:theater_id, :title, :starts_at, :date, :version]
  defstruct [
    :theater_id,
    :theater_name,
    :title,
    :original_title,
    :runtime_min,
    :poster_url,
    :starts_at,
    :date,
    :version,
    :booking_url,
    genres: []
  ]

  @type version :: :vf | :vost

  @type t :: %__MODULE__{
          theater_id: String.t(),
          theater_name: String.t() | nil,
          title: String.t(),
          original_title: String.t() | nil,
          runtime_min: pos_integer() | nil,
          poster_url: String.t() | nil,
          starts_at: NaiveDateTime.t(),
          date: Date.t(),
          version: version(),
          booking_url: String.t() | nil,
          genres: [String.t()]
        }

  @doc """
  Whether the screening has already begun at `now` (local Grenoble time).

  Past screenings stay on the board — they say what a cinema programmes today —
  but the UI dims them so the eye skips to what is still catchable.
  """
  @spec past?(t(), NaiveDateTime.t()) :: boolean()
  def past?(%__MODULE__{starts_at: starts_at}, now) do
    NaiveDateTime.compare(starts_at, now) == :lt
  end
end
