defmodule SortirWeb.AgendaLive do
  @moduledoc """
  Board of what is on in the city's venues, day by day.

  Renders the next `@days_shown` days that have events, grouped by date and
  ordered by start time. Days with nothing on are omitted rather than shown
  empty, so the board stays useful across a venue's closed season.

  Reads from `Sortir.Agenda`, which is populated by scheduled scrapes; the page
  itself fetches nothing and does not refresh.
  """

  use SortirWeb, :live_view

  alias Sortir.Agenda
  alias Sortir.Core.Clock

  # Days *with something on*, not days ahead. A venue closes for the summer;
  # a fixed window would show an empty page during exactly the spell when you
  # want to know what is coming back.
  #
  # High enough to show everything a venue has programmed — currently seven
  # months out — rather than truncating without saying so. Empty days are
  # already dropped, so this is days of content, not days of calendar.
  @days_shown 400

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(now: Clock.now()) |> load_days()}
  end

  defp load_days(socket) do
    today = Clock.today()

    assign(socket, days: Agenda.upcoming(today, @days_shown), today: today)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="board">
      <header class="board-head is-bare">
        <div class="board-title">
          <h1>Agenda à Grenoble</h1>
          <div class="board-title-right">
            <time class="clock" datetime={DateTime.to_iso8601(@now)}>
              <span class="clock-date">{full_date(DateTime.to_date(@now))}</span>
              <span class="clock-time">{Calendar.strftime(@now, "%H:%M")}</span>
            </time>
          </div>
        </div>

        <nav class="controls">
          <.link navigate={~p"/"} class="version">Séances</.link>
          <span class="version is-on">Agenda</span>
          <.link navigate={~p"/agenda/venues"} class="version">Salles</.link>
        </nav>
      </header>

      <main>
        <section :for={day <- @days} class="theater">
          <h2 class="theater-name">{full_date(day.date)}</h2>

          <article :for={entry <- day.entries} class="movie">
            <img
              :if={entry.event.image_url}
              class="poster"
              src={entry.event.image_url}
              alt=""
              loading="lazy"
              decoding="async"
              width="80"
              height="107"
            />
            <div :if={is_nil(entry.event.image_url)} class="poster poster-empty" aria-hidden="true">
            </div>

            <div class="movie-body">
              <div class="movie-head">
                <h3 class="movie-title">{entry.event.title}</h3>
                <span :if={price(entry)} class="movie-meta">{price(entry)}</span>
              </div>

              <p class="agenda-meta">
                <span
                  :for={occurrence <- entry.occurrences}
                  class={["chip", status_class(occurrence)]}
                >
                  {time(occurrence)}
                </span>
                <span :if={entry.occurrences == []} class="chip">Exposition</span>
                <span :if={entry.venue} class="town">{venue_label(entry)}</span>
              </p>

              <ul :if={entry.event.labels != []} class="genres">
                <li :for={label <- Enum.take(entry.event.labels, 3)} class="genre label">
                  {label}
                </li>
              </ul>
            </div>
          </article>
        </section>

        <p :if={@days == []} class="empty">
          Rien de programmé pour le moment.
        </p>
      </main>

      <footer class="board-foot">
        <span>Sources : les salles elles-mêmes ·
        <code class="build">{Sortir.Core.Version.commit()}</code></span>
      </footer>
    </div>
    """
  end

  defp time(%{starts_at: starts_at} = occurrence) do
    start = Calendar.strftime(Clock.to_local(starts_at), "%H:%M")

    case occurrence.ends_at do
      nil -> start
      ends_at -> "#{start} → #{Calendar.strftime(Clock.to_local(ends_at), "%H:%M")}"
    end
  end

  # Prices are tiers; the lowest is what tells you whether you can go.
  defp price(%{occurrence: %{prices: [cheapest | _rest]}}), do: "dès #{div(cheapest, 100)} €"
  defp price(_entry), do: nil

  defp status_class(%{status: :sold_out}), do: "is-sold-out"
  defp status_class(%{status: :cancelled}), do: "is-cancelled"
  defp status_class(_occurrence), do: nil

  defp venue_label(%{venue: venue, occurrence: %{room: room}}) when is_binary(room) do
    if String.contains?(room, venue.name), do: room, else: "#{venue.name} · #{room}"
  end

  defp venue_label(%{venue: venue}), do: venue.name

  @days ~w(lun. mar. mer. jeu. ven. sam. dim.)
  @months ~w(janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.)

  defp full_date(date) do
    "#{Enum.at(@days, Date.day_of_week(date) - 1)} #{date.day} #{Enum.at(@months, date.month - 1)}"
  end
end
