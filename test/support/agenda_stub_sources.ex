defmodule Sortir.Agenda.StubSource do
  @moduledoc "Deterministic source for tests, so nothing hits a real venue."

  @behaviour Sortir.Agenda.Source

  alias Sortir.Core.Clock

  @impl true
  def venue do
    %{slug: "stub-venue", name: "Salle Stub", city: "Grenoble", kind: :music_hall, url: nil}
  end

  @impl true
  def fetch do
    today = Clock.today()

    {:ok,
     [
       scraped("stub-1", "Un concert", NaiveDateTime.new!(today, ~T[20:00:00])),
       scraped("stub-2", "Un autre", NaiveDateTime.new!(today, ~T[22:00:00]))
     ]}
  end

  defp scraped(id, title, at) do
    %{
      event: %{
        source: "stub",
        external_id: id,
        title: title,
        category: :concert,
        labels: ["Rock"]
      },
      occurrence: %{starts_at: at, ends_at: nil, status: :unknown, room: "Grande salle"}
    }
  end
end

defmodule Sortir.Agenda.LimitedSource do
  @moduledoc "A source that is being rate limited."

  @behaviour Sortir.Agenda.Source

  alias Sortir.Agenda.StubSource

  @impl true
  def venue, do: StubSource.venue()

  @impl true
  def fetch, do: {:error, {:http_status, 429}}
end

defmodule Sortir.Agenda.PartialSource do
  @moduledoc "A source where one entry is unusable, to prove the rest survive."

  @behaviour Sortir.Agenda.Source

  alias Sortir.Agenda.StubSource
  alias Sortir.Core.Clock

  @impl true
  def venue, do: StubSource.venue()

  @impl true
  def fetch do
    from = Clock.today()

    {:ok,
     [
       %{
         event: %{source: "stub", external_id: "good", title: "Bon", category: :concert},
         occurrence: %{starts_at: NaiveDateTime.new!(from, ~T[20:00:00])}
       },
       # No external_id: the source could not identify it.
       %{
         event: %{source: "stub", external_id: nil, title: "Cassé", category: :concert},
         occurrence: %{starts_at: NaiveDateTime.new!(from, ~T[21:00:00])}
       }
     ]}
  end
end
