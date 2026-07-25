defmodule CinemaWeb.ShowtimesLive do
  @moduledoc """
  The whole app: every showtime in the selected city for the coming days.

  Filtering happens client-side against the already-loaded schedule, so
  switching day or version never round-trips to AlloCiné.
  """

  use CinemaWeb, :live_view

  # The clock only needs to be right to the minute; ticking every 30s keeps it
  # from lagging visibly after a minute rolls over.
  @tick_ms 30_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@tick_ms, self(), :tick)

    {:ok,
     socket
     |> assign(version: :all, group_by: :movie, loading: false)
     |> assign_now()
     # Every assign the template reads is set here, so a render can never hit a
     # missing key no matter how handle_params/3 goes.
     |> assign(
       cities: Cinema.cities(),
       city: nil,
       film: nil,
       days: [],
       selected_date: nil,
       fetched_at: nil,
       stale?: false
     )}
  end

  @impl true
  def handle_info(:tick, socket), do: {:noreply, assign_now(socket)}

  # Screenings carry naive local times, so keep a naive copy to compare against.
  defp assign_now(socket) do
    now = Cinema.now()
    assign(socket, now: now, now_naive: DateTime.to_naive(now))
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      case Cinema.find_city(params["city"]) do
        nil ->
          # No city at all: the source is unreachable on a cold cache. Render an
          # explicit message rather than a half-built board.
          assign(socket, city: nil, days: [], selected_date: nil, film: nil)

        city ->
          socket = if city == socket.assigns.city, do: socket, else: load_days(socket, city)

          assign(socket,
            selected_date: selected_date(params, socket.assigns.days, socket.assigns.now_naive),
            film: params["film"] && Cinema.film(socket.assigns.days, params["film"])
          )
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("select-day", _params, %{assigns: %{city: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("select-day", %{"date" => date}, socket) do
    {:noreply, push_patch(socket, to: ~p"/?#{[city: socket.assigns.city.slug, date: date]}")}
  end

  def handle_event("close-film", _params, socket) do
    {:noreply, push_patch(socket, to: board_path(socket))}
  end

  def handle_event("select-city", %{"city" => slug}, socket) do
    {:noreply, push_patch(socket, to: ~p"/?#{[city: slug]}")}
  end

  def handle_event("filter-version", %{"version" => version}, socket) do
    {:noreply, assign(socket, version: parse_version(version))}
  end

  def handle_event("group-by", %{"group" => group}, socket) do
    {:noreply, assign(socket, group_by: parse_group(group))}
  end

  def handle_event("refresh", _params, %{assigns: %{city: nil}} = socket), do: {:noreply, socket}

  def handle_event("refresh", _params, socket) do
    socket =
      socket
      |> assign(loading: true)
      |> load_days(socket.assigns.city, refresh: true)
      |> assign(loading: false)

    {:noreply, socket}
  end

  defp board_path(socket) do
    params = [city: socket.assigns.city.slug]

    params =
      if socket.assigns.selected_date,
        do: params ++ [date: Date.to_iso8601(socket.assigns.selected_date)],
        else: params

    ~p"/?#{params}"
  end

  defp film_path(city, title), do: ~p"/?#{[city: city.slug, film: title]}"

  defp load_days(socket, city, opts \\ []) do
    schedule = if opts[:refresh], do: Cinema.refresh(city), else: Cinema.schedule(city)

    socket
    |> assign(
      city: city,
      days: schedule.days,
      fetched_at: schedule.fetched_at,
      stale?: schedule.stale?
    )
    |> assign(selected_date: default_date(schedule.days, socket.assigns.now_naive))
  end

  # An explicit ?date= always wins; otherwise open on the most useful day.
  defp selected_date(%{"date" => date}, days, now) do
    with {:ok, parsed} <- Date.from_iso8601(date),
         true <- Enum.any?(days, &(&1.date == parsed)) do
      parsed
    else
      _invalid -> default_date(days, now)
    end
  end

  defp selected_date(_params, days, now), do: default_date(days, now)

  defp default_date(days, now), do: Cinema.opening_date(days, now)

  defp parse_version("vf"), do: :vf
  defp parse_version("vost"), do: :vost
  defp parse_version(_all), do: :all

  defp parse_group("movie"), do: :movie
  defp parse_group(_theater), do: :theater

  # --- rendering ---------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(day: Enum.find(assigns.days, &(&1.date == assigns.selected_date)))
      |> assign(page_title: page_title(assigns.city))

    ~H"""
    <div class="board">
      <header class={["board-head", @film && "is-bare"]}>
        <div class="board-title">
          <h1>
            <span class="board-title-text">Séances à</span>
            <form :if={@city} id="city-picker" class="city-picker" phx-change="select-city">
              <label class="sr-only" for="city">Ville</label>
              <select id="city" name="city">
                <option :for={city <- @cities} value={city.slug} selected={city.slug == @city.slug}>
                  {city.name}
                </option>
              </select>
            </form>
          </h1>
          <div class="board-title-right">
            <time class="clock" datetime={DateTime.to_iso8601(@now)}>
              <span class="clock-date">{full_date(DateTime.to_date(@now))}</span>
              <span class="clock-time">{Calendar.strftime(@now, "%H:%M")}</span>
            </time>
            <button class="refresh" phx-click="refresh" disabled={@loading} aria-label="Actualiser">
              <span class="refresh-icon">{if @loading, do: "…", else: "↻"}</span>
            </button>
          </div>
        </div>

        <%!-- The day strip and filters act on the board only: the film view
              spans every day and shows one film, so neither applies there. --%>
        <nav :if={is_nil(@film)} class="days" aria-label="Choisir un jour">
          <button
            :for={day <- @days}
            class={["day", day.date == @selected_date && "is-current"]}
            phx-click="select-day"
            phx-value-date={Date.to_iso8601(day.date)}
            aria-current={day.date == @selected_date && "true"}
          >
            <span class="day-name">{day_name(day.date)}</span>
            <span class="day-num">{day.date.day}</span>
          </button>
        </nav>

        <div :if={is_nil(@film)} class="controls">
          <div class="versions" role="group" aria-label="Filtrer par version">
            <button
              :for={{label, value} <- [{"Tout", :all}, {"VF", :vf}, {"VOST", :vost}]}
              class={["version", @version == value && "is-on"]}
              phx-click="filter-version"
              phx-value-version={value}
            >
              {label}
            </button>
          </div>

          <div class="versions" role="group" aria-label="Regrouper les séances">
            <button
              :for={{label, value} <- [{"Par film", :movie}, {"Par cinéma", :theater}]}
              class={["version", @group_by == value && "is-on"]}
              phx-click="group-by"
              phx-value-group={value}
            >
              {label}
            </button>
          </div>
        </div>
      </header>

      <main :if={is_nil(@city)}>
        <p class="empty">
          AlloCiné est injoignable pour le moment. Réessayez dans quelques minutes.
        </p>
      </main>

      <main :if={@city && @film}>
        <button class="back" phx-click="close-film">
          <span class="back-arrow" aria-hidden="true">←</span>
          <span>Toutes les séances</span>
        </button>

        <article class="film">
          <div class="film-head">
            <img
              :if={@film.poster_url}
              class="poster poster-lg"
              src={@film.poster_url}
              alt=""
              loading="lazy"
              decoding="async"
              width="120"
              height="160"
            />
            <div class="film-meta">
              <h2 class="film-title">{@film.title}</h2>
              <p :if={@film.original_title && @film.original_title != @film.title} class="film-orig">
                {@film.original_title}
              </p>
              <p :if={@film.runtime_min} class="movie-meta">{runtime(@film.runtime_min)}</p>
              <.genres list={@film.genres} />
            </div>
          </div>

          <section :for={day <- @film.days} class="film-day">
            <h3 class="film-day-name">{full_date(day.date)}</h3>

            <div :for={venue <- day.theaters} class="venue">
              <h4 class="venue-name">{venue.name}</h4>
              <ul class="times">
                <li :for={screening <- venue.screenings}>
                  <.time_chip screening={screening} now={@now_naive} />
                </li>
              </ul>
            </div>
          </section>
        </article>
      </main>

      <main :if={@city && is_nil(@film)}>
        <%= if @group_by == :movie do %>
          <section :for={movie <- by_movie(@day, @version)} class="theater">
            <div class="movie movie-lead">
              <img
                :if={movie.poster_url}
                class="poster"
                src={movie.poster_url}
                alt=""
                loading="lazy"
                decoding="async"
                width="80"
                height="107"
              />
              <div :if={is_nil(movie.poster_url)} class="poster poster-empty" aria-hidden="true">
              </div>

              <div class="movie-body">
                <div class="movie-head">
                  <h2 class="movie-title">
                    <.link patch={film_path(@city, movie.title)} class="movie-link">
                      {movie.title}
                    </.link>
                  </h2>
                  <span :if={movie.runtime_min} class="movie-meta">{runtime(movie.runtime_min)}</span>
                </div>

                <.genres list={movie.genres} />

                <div :for={venue <- movie.theaters} class="venue">
                  <h3 class="venue-name">{venue.name}</h3>
                  <ul class="times">
                    <li :for={screening <- venue.screenings}>
                      <.time_chip screening={screening} now={@now_naive} />
                    </li>
                  </ul>
                </div>
              </div>
            </div>
          </section>

          <p :if={by_movie(@day, @version) == []} class="empty">
            Aucune séance {empty_reason(@version)} ce jour-là.
          </p>
        <% else %>
          <%= for theater <- visible_theaters(@day, @version) do %>
            <section class="theater">
              <h2 class="theater-name">{theater.name}</h2>

              <article :for={movie <- theater.movies} class="movie">
                <img
                  :if={movie.poster_url}
                  class="poster"
                  src={movie.poster_url}
                  alt=""
                  loading="lazy"
                  decoding="async"
                  width="80"
                  height="107"
                />
                <div :if={is_nil(movie.poster_url)} class="poster poster-empty" aria-hidden="true">
                </div>

                <div class="movie-body">
                  <div class="movie-head">
                    <h3 class="movie-title">
                      <.link patch={film_path(@city, movie.title)} class="movie-link">
                        {movie.title}
                      </.link>
                    </h3>
                    <span :if={movie.runtime_min} class="movie-meta">{runtime(movie.runtime_min)}</span>
                  </div>

                  <.genres list={movie.genres} />

                  <ul class="times">
                    <li :for={screening <- movie.screenings}>
                      <.time_chip screening={screening} now={@now_naive} />
                    </li>
                  </ul>
                </div>
              </article>
            </section>
          <% end %>

          <p :if={visible_theaters(@day, @version) == []} class="empty">
            Aucune séance {empty_reason(@version)} ce jour-là.
          </p>
        <% end %>
      </main>

      <footer class={["board-foot", @stale? && "is-stale"]}>
        <span>Source AlloCiné · <code class="build">{Cinema.commit()}</code></span>
        <span :if={@fetched_at}>
          {if @stale?, do: "AlloCiné injoignable — horaires du ", else: "Mis à jour à "}{local_time(
            @fetched_at
          )}
        </span>
      </footer>
    </div>
    """
  end

  attr :list, :list, required: true

  # Capped at three: a fourth wraps and starts competing with the times, which
  # are what the eye is actually scanning for.
  defp genres(assigns) do
    assigns = assign(assigns, list: Enum.take(assigns.list, 3))

    ~H"""
    <ul :if={@list != []} class="genres">
      <li :for={genre <- @list} class="genre">{genre}</li>
    </ul>
    """
  end

  attr :screening, :map, required: true
  attr :now, NaiveDateTime, required: true

  defp time_chip(assigns) do
    assigns = assign(assigns, past?: Cinema.Screening.past?(assigns.screening, assigns.now))

    ~H"""
    <a
      :if={@screening.booking_url && not @past?}
      class={["chip", version_class(@screening.version)]}
      href={@screening.booking_url}
      target="_blank"
      rel="noopener"
    >
      {format_time(@screening.starts_at)}
    </a>
    <span
      :if={is_nil(@screening.booking_url) or @past?}
      class={["chip", version_class(@screening.version), @past? && "is-past"]}
    >
      {format_time(@screening.starts_at)}
    </span>
    """
  end

  defp visible_theaters(nil, _version), do: []

  defp visible_theaters(day, :all), do: day.theaters

  defp visible_theaters(day, version) do
    day.theaters
    |> Enum.map(fn theater ->
      movies =
        theater.movies
        |> Enum.map(fn movie ->
          %{movie | screenings: Enum.filter(movie.screenings, &(&1.version == version))}
        end)
        |> Enum.reject(&(&1.screenings == []))

      %{theater | movies: movies}
    end)
    |> Enum.reject(&(&1.movies == []))
  end

  # Filter first, then invert, so a movie only lists cinemas that still have a
  # matching screening once the version filter is applied.
  defp by_movie(day, version) do
    case visible_theaters(day, version) do
      [] -> []
      theaters -> Cinema.by_movie(%{date: day.date, theaters: theaters})
    end
  end

  defp empty_reason(:vf), do: "en VF"
  defp empty_reason(:vost), do: "en VOST"
  defp empty_reason(:all), do: ""

  defp version_class(:vost), do: "is-vost"
  defp version_class(:vf), do: "is-vf"

  defp page_title(nil), do: "Séances"
  defp page_title(city), do: "Séances à #{city.name}"

  defp format_time(naive), do: Calendar.strftime(naive, "%H:%M")

  defp local_time(%DateTime{} = at) do
    case DateTime.shift_zone(at, "Europe/Paris") do
      {:ok, local} -> Calendar.strftime(local, "%H:%M")
      {:error, _no_tzdata} -> Calendar.strftime(at, "%H:%M")
    end
  end

  defp runtime(minutes) when minutes >= 60 do
    "#{div(minutes, 60)} h #{minutes |> rem(60) |> to_string() |> String.pad_leading(2, "0")}"
  end

  defp runtime(minutes), do: "#{minutes} min"

  @days ~w(lun. mar. mer. jeu. ven. sam. dim.)
  defp day_name(date), do: Enum.at(@days, Date.day_of_week(date) - 1)

  @months ~w(janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.)
  defp month_name(date), do: Enum.at(@months, date.month - 1)

  # Short enough to sit beside the clock on a phone: "mer. 24 juil."
  defp full_date(date), do: "#{day_name(date)} #{date.day} #{month_name(date)}"
end
