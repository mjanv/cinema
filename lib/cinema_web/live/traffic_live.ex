defmodule CinemaWeb.TrafficLive do
  @moduledoc """
  What the app is actually used for: views over time, by city and by page.

  Everything is drawn with CSS boxes rather than a charting library. The whole
  page is four series of at most a few dozen points; a bar is a div whose
  height is a percentage, which needs no JavaScript, no build step and no
  vendored megabyte, and it renders in the dead view like the rest of the app.
  """

  use CinemaWeb, :live_view

  alias Cinema.Traffic

  # Long enough that a page left open on a second monitor is not polling for
  # nothing, short enough that a deploy's first visitors show up while you are
  # still watching.
  @refresh_ms 30_000

  # Label, granularity, and how many points wide. The breakdowns alongside the
  # chart cover the same span, rounded up to whole days -- the smallest window
  # `Traffic` counts back in.
  @ranges [
    {"24 h", :hourly, 24},
    {"48 h", :hourly, 48},
    {"7 j", :daily, 7},
    {"30 j", :daily, 30}
  ]
  @default_range "48 h"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(@refresh_ms, self(), :refresh)
      Traffic.hit("/traffic")
    end

    {:ok, socket |> assign(names: city_names(), page_title: "Trafic") |> load(@default_range)}
  end

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load(socket, socket.assigns.range)}

  @impl true
  def handle_event("select-range", %{"range" => range}, socket) do
    {:noreply, load(socket, range)}
  end

  defp load(socket, range) do
    {label, granularity, points} =
      Enum.find(@ranges, List.first(@ranges), fn {candidate, _granularity, _points} ->
        candidate == range
      end)

    series = series(granularity, points)
    days = if granularity == :hourly, do: ceil(points / 24), else: points

    assign(socket,
      range: label,
      granularity: granularity,
      series: series,
      peak: peak(series),
      cities: Traffic.cities(days),
      paths: Traffic.paths(days),
      total: Traffic.total(days)
    )
  end

  defp series(:hourly, points), do: Traffic.hourly(points)
  defp series(:daily, points), do: Traffic.daily(points)

  # Slugs are what the counter stores -- they survive a city being renamed, and
  # they are what the URL says. Names are what an operator reads.
  defp city_names do
    Map.new(Cinema.cities(), &{&1.slug, &1.name})
  rescue
    # The city list is fetched, so it can be unavailable exactly when the
    # dashboard is most interesting. Slugs alone still read fine.
    _error -> %{}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="traffic">
      <header class="traffic-head">
        <div class="traffic-title">
          <h1>Trafic</h1>
          <p class="traffic-total">
            <strong>{@total}</strong>
            <span>{if @total == 1, do: "vue", else: "vues"} sur {@range}</span>
          </p>
        </div>

        <nav class="periods" aria-label="Choisir la période">
          <button
            :for={{label, _granularity, _points} <- ranges()}
            class={["period", @range == label && "is-on"]}
            phx-click="select-range"
            phx-value-range={label}
            aria-current={@range == label && "true"}
          >
            {label}
          </button>
        </nav>
      </header>

      <main>
        <section class="panel">
          <h2 class="panel-title">
            {if @granularity == :hourly, do: "Par heure", else: "Par jour"}
            <span class="panel-peak">pic {@peak}</span>
          </h2>

          <div class="chart" role="img" aria-label={chart_summary(@series, @granularity, @peak)}>
            <div
              :for={{bucket, count} <- @series}
              class="slot"
              title={"#{point_label(bucket, @granularity)} — #{count}"}
            >
              <div
                class={["bar", count == 0 && "is-zero"]}
                style={"height: #{share(count, @peak)}%"}
              >
              </div>
            </div>
          </div>

          <div :if={@series != []} class="axis">
            <span>{point_label(first_bucket(@series), @granularity)}</span>
            <span>{point_label(last_bucket(@series), @granularity)}</span>
          </div>
        </section>

        <div class="panels">
          <.breakdown
            id="cities"
            title="Villes"
            rows={@cities}
            names={@names}
            empty="Aucune ville consultée."
          />
          <.breakdown
            id="paths"
            title="Pages"
            rows={@paths}
            names={%{}}
            empty="Aucune page consultée."
          />
        </div>
      </main>

      <footer class="traffic-foot">
        <a href={~p"/"}>← Séances</a>
        <span>Actualisé toutes les 30 s · <code class="build">{Cinema.commit()}</code></span>
      </footer>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :rows, :list, required: true
  attr :names, :map, required: true
  attr :empty, :string, required: true

  defp breakdown(assigns) do
    assigns = assign(assigns, top: Enum.take(assigns.rows, 12), peak: peak(assigns.rows))

    ~H"""
    <section class="panel" id={@id}>
      <h2 class="panel-title">{@title}</h2>

      <ul :if={@top != []} class="rows">
        <li :for={{key, count} <- @top} class="row">
          <span class="row-label">{Map.get(@names, key, key)}</span>
          <span class="row-track"><span class="row-bar" style={"width: #{share(count, @peak)}%"} /></span>
          <span class="row-count">{count}</span>
        </li>
      </ul>

      <p :if={@top == []} class="empty">{@empty}</p>
    </section>
    """
  end

  defp ranges, do: @ranges

  # The tallest bar sets the scale: these are counts with no natural ceiling,
  # and a fixed axis would flatten a quiet week into nothing.
  defp peak([]), do: 0
  defp peak(points), do: points |> Enum.map(&elem(&1, 1)) |> Enum.max()

  # A floor of 2% keeps a bar that is merely small from disappearing into the
  # axis, where it would read as no traffic at all.
  defp share(0, _peak), do: 0
  defp share(_count, 0), do: 0
  defp share(count, peak), do: max(count / peak * 100, 2)

  defp first_bucket(series), do: series |> List.first() |> elem(0)
  defp last_bucket(series), do: series |> List.last() |> elem(0)

  defp chart_summary([], _granularity, _peak), do: "Aucune donnée"

  defp chart_summary(series, granularity, peak) do
    "De #{point_label(first_bucket(series), granularity)} à " <>
      "#{point_label(last_bucket(series), granularity)}, pic à #{peak} vues"
  end

  # Buckets are ISO strings: "2026-09-08T14" for an hour, "2026-09-08" for a
  # day. Both are read against today, so only the part that varies is shown.
  defp point_label(<<_date::binary-10, "T", hour::binary-2>>, :hourly), do: "#{hour} h"

  defp point_label(<<_year::binary-4, "-", month::binary-2, "-", day::binary-2>>, :daily) do
    "#{day}/#{month}"
  end

  defp point_label(bucket, _granularity), do: bucket
end
