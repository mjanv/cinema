defmodule Sortir.Core.Clock do
  @moduledoc """
  Local time for the city the app serves.

  Every domain reads the same wall clock: a board showing tonight's events and
  a board showing tonight's screenings must agree on when "tonight" ends. The
  zone is configurable under `config :sortir, #{inspect(__MODULE__)}, timezone:
  ...` and defaults to `Europe/Paris`.

  Timestamps are stored in UTC and rendered locally. `to_utc/1` converts what a
  scraper read off a page; `to_local/1` converts back for display.
  """

  @default_timezone "Europe/Paris"

  @doc "The current time in the configured zone."
  @spec now(DateTime.t()) :: DateTime.t()
  def now(at \\ DateTime.utc_now()), do: to_local(at)

  @doc """
  Today's date in the configured zone.

  Not the UTC date: for the hours either side of midnight the two differ, and
  the local one is what a reader means by "today".
  """
  @spec today(DateTime.t()) :: Date.t()
  def today(at \\ DateTime.utc_now()), do: at |> to_local() |> DateTime.to_date()

  @doc """
  Reads a naive local time as UTC for storage.

  A `DateTime` is already anchored and passes through unchanged, as does `nil`.
  """
  @spec to_utc(NaiveDateTime.t() | DateTime.t() | nil) :: DateTime.t() | nil
  def to_utc(nil), do: nil
  def to_utc(%DateTime{} = at), do: at

  def to_utc(%NaiveDateTime{} = at) do
    case DateTime.from_naive(at, timezone()) do
      {:ok, at} ->
        DateTime.shift_zone!(at, "Etc/UTC")

      # Twice a year a local time is ambiguous or does not exist. Taking it as
      # UTC misplaces the event by an hour; dropping it loses the event.
      _dst_edge ->
        DateTime.from_naive!(at, "Etc/UTC")
    end
  end

  @doc """
  Shifts a stored time into the configured zone.

  Falls back to the value it was given if the zone database is unavailable, so
  a missing tzdata renders the wrong offset rather than crashing the page.
  """
  @spec to_local(DateTime.t()) :: DateTime.t()
  def to_local(%DateTime{} = at) do
    case DateTime.shift_zone(at, timezone()) do
      {:ok, local} -> local
      {:error, _no_tzdata} -> at
    end
  end

  @doc "The configured zone name."
  @spec timezone() :: String.t()
  def timezone do
    Application.get_env(:sortir, __MODULE__, [])[:timezone] || @default_timezone
  end
end
