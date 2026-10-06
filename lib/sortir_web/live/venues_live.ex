defmodule SortirWeb.VenuesLive do
  @moduledoc """
  The venues the agenda is built from, and what each has programmed.

  A companion to `SortirWeb.AgendaLive`: where that page answers "what is on",
  this answers "what is this built from" — how much each venue contributes,
  how far ahead it reaches, and when it was last read.

  A venue with nothing programmed is still listed. A scraper that ran and
  found nothing must be distinguishable from one that was never added.
  """

  use SortirWeb, :live_view

  alias Sortir.Agenda
  alias Sortir.Core.Clock

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       now: Clock.now(),
       venues: Agenda.venues(),
       scraped_at: Agenda.scraped_at()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="board">
      <header class="board-head is-bare">
        <div class="board-title">
          <h1>Les salles</h1>
          <div class="board-title-right">
            <time class="clock" datetime={DateTime.to_iso8601(@now)}>
              <span class="clock-date">{full_date(DateTime.to_date(@now))}</span>
              <span class="clock-time">{Calendar.strftime(@now, "%H:%M")}</span>
            </time>
          </div>
        </div>

        <nav class="controls">
          <.link navigate={~p"/"} class="version">Séances</.link>
          <.link navigate={~p"/agenda"} class="version">Agenda</.link>
          <span class="version is-on">Salles</span>
        </nav>
      </header>

      <main>
        <section class="theater">
          <article :for={listed <- @venues} class="place">
            <div class="place-head">
              <h3 class="place-name">
                <.link :if={listed.venue.url} href={listed.venue.url} target="_blank" rel="noopener">
                  {listed.venue.name}
                </.link>
                <span :if={is_nil(listed.venue.url)}>{listed.venue.name}</span>
              </h3>
              <span class="place-count">{counts(listed)}</span>
            </div>

            <p class="agenda-meta">
              <span class="chip">{kind(listed.venue.kind)}</span>
              <span class="town">{listed.venue.city}</span>
              <span :if={listed.next} class="town">{programme(listed)}</span>
              <span :if={is_nil(listed.next)} class="town">rien à venir</span>
            </p>
          </article>

          <p :if={@venues == []} class="empty">
            Aucune salle enregistrée pour le moment.
          </p>
        </section>
      </main>

      <footer class="board-foot">
        <span>
          {length(@venues)} salles · dernière collecte {last_scrape(@scraped_at)} ·
          <code class="build">{Sortir.Core.Version.commit()}</code>
        </span>
      </footer>
    </div>
    """
  end

  # Events, not occurrences: a production on five nights is one thing the
  # venue programmed, and the occurrence count is the finer detail.
  defp counts(%{events: 0}), do: "—"

  defp counts(%{events: events, occurrences: occurrences}) do
    "#{events} #{plural(events, "événement")} · #{occurrences} #{plural(occurrences, "date")}"
  end

  defp programme(%{next: next, last: last}) do
    "du #{short_date(next)} au #{short_date(last)}"
  end

  defp plural(1, word), do: word
  defp plural(_many, word), do: word <> "s"

  defp last_scrape(nil), do: "jamais"

  defp last_scrape(at) do
    case DateTime.diff(DateTime.utc_now(), at, :hour) do
      hours when hours < 1 -> "il y a moins d'une heure"
      hours when hours < 24 -> "il y a #{hours} h"
      hours -> "il y a #{div(hours, 24)} j"
    end
  end

  @kinds %{
    music_hall: "Salle de concert",
    theatre: "Théâtre",
    museum: "Musée",
    cinema: "Cinéma",
    other: "Autre"
  }

  defp kind(kind), do: Map.get(@kinds, kind, "Autre")

  @days ~w(lun. mar. mer. jeu. ven. sam. dim.)
  @months ~w(janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.)

  defp full_date(date) do
    "#{Enum.at(@days, Date.day_of_week(date) - 1)} #{date.day} #{Enum.at(@months, date.month - 1)}"
  end

  defp short_date(date) do
    "#{date.day} #{Enum.at(@months, date.month - 1)} #{date.year}"
  end
end
