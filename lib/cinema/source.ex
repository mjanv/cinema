defmodule Cinema.Source do
  @moduledoc """
  A provider of showtimes.

  AlloCiné is the only implementation today, but cinemas also publish their own
  schedules. Aggregation and the UI depend on this contract, never on a
  concrete source, so adding an adapter means implementing this behaviour and
  listing it in config — nothing downstream changes.

  Implementations must not raise: a source that is down returns `{:error, _}`
  so one failing site cannot take down the whole page.
  """

  alias Cinema.{Screening, Theater}

  @doc "Theaters this source can serve, in display order."
  @callback theaters() :: [Theater.t()]

  @doc "Screenings for one theater on one date."
  @callback fetch_day(theater :: Theater.t(), date :: Date.t()) ::
              {:ok, [Screening.t()]} | {:error, term()}
end
