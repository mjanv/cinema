defmodule Sortir.Agenda.Source do
  @moduledoc """
  Behaviour implemented by each venue's scraper.

  A source knows two things: which venue it describes (`venue/0`) and how to
  read events off that venue's site (`fetch/0`). Everything downstream —
  persistence, deduplication, scheduling, rendering — is written against this
  behaviour and never learns which venue it is handling, so a new venue is a
  single module plus an entry in `Sortir.Agenda.sources/0`.

  `fetch/0` takes no date range: venues paginate by month, by page number or
  not at all, and only the source knows how far its own site reaches. It
  returns `{:ok, entries}` where each entry is a map of `:event` and
  `:occurrence` attributes ready for `Sortir.Agenda.save/2`. Implementations
  accept options beyond the callback — an HTTP function and a pacing delay — so
  tests can drive them against stored pages.

  Implementations should degrade rather than raise: a row that will not parse
  is dropped, and a partial read is returned as `{:ok, partial}` rather than an
  error, since the next scrape fills the gap.
  """

  @typedoc "One event and the occurrence that places it, if it has one."
  @type scraped :: %{required(:event) => map(), optional(:occurrence) => map()}

  @doc "The venue this source scrapes."
  @callback venue() :: map()

  @doc """
  Everything the venue currently has programmed.

  No date argument: venues paginate differently — by month, by page, or not at
  all — and only the source knows how its own site works. Guessing a month at a
  time re-fetched overlapping pages and still missed the end of the programme.
  """
  @callback fetch() :: {:ok, [scraped()]} | {:error, term()}
end
