defmodule SortirWeb.VideosLive do
  @moduledoc """
  Eurosport France's videos, with everything that gives the result away hidden.

  Looks like a video grid but shows only what cannot spoil: a heavily blurred
  thumbnail, the publication date and the view count. While blurred, titles are
  not sent to the browser at all, not even hidden: the search runs on the server
  and the cards that match are the only answer. To find a race, type its name.

  "Tout afficher" reveals the sharp thumbnails and the titles together, and
  "Tout masquer" takes both back out of the page.

  Clicking a card plays the video in an embedded player rather than linking to
  youtube.com, whose page shows the title and thumbnail. The embed has its own
  spoilers (title overlay, poster frame, end-screen suggestions); see the
  covers on the player.

  The query lives in the URL (`?q=`), so a search can be bookmarked or shared.
  """

  use SortirWeb, :live_view

  alias Sortir.Core.Clock
  alias Sortir.Videos

  @impl true
  def mount(_params, _session, socket) do
    # Only the live connection: the static render is also what crawlers and link
    # previews get, and none of them should cost a request to YouTube. The fetch
    # runs in the background; `:videos_updated` brings its result to the page.
    if connected?(socket) do
      Videos.subscribe()
      Videos.request_refresh()
    end

    {:ok, assign(socket, page_title: "Vidéos", revealed?: false, playing: nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = params |> Map.get("q", "") |> String.trim()

    {:noreply,
     socket
     |> assign(query: query, form: to_form(%{"q" => query}))
     |> load_videos()}
  end

  # Re-streamed, not just re-assigned: whether a card is blurred is read inside
  # the stream, and LiveView does not re-render stream items on an assign.
  defp load_videos(%{assigns: %{query: query}} = socket) do
    videos = Videos.list(query)

    socket
    |> assign(count: length(videos))
    |> stream(:videos, videos, reset: true, dom_id: &"video-#{&1.youtube_id}")
  end

  @impl true
  def handle_info(:videos_updated, socket), do: {:noreply, load_videos(socket)}

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    case String.trim(query) do
      "" -> {:noreply, push_patch(socket, to: ~p"/nospoil/eurosportfrance")}
      query -> {:noreply, push_patch(socket, to: ~p"/nospoil/eurosportfrance?#{[q: query]}")}
    end
  end

  def handle_event("play", %{"id" => id}, socket) do
    # Only videos we stored: the id comes from the browser, and the player
    # would otherwise embed whatever it is handed.
    case Videos.get(id) do
      nil -> {:noreply, socket}
      video -> {:noreply, assign(socket, playing: video.youtube_id)}
    end
  end

  def handle_event("close-player", _params, socket) do
    {:noreply, assign(socket, playing: nil)}
  end

  def handle_event("toggle-all", _params, socket) do
    {:noreply, socket |> update(:revealed?, &(!&1)) |> load_videos()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="board">
      <header class="board-head is-bare">
        <div class="board-title">
          <h1>Vidéos Eurosport</h1>
        </div>

        <.form
          for={@form}
          id="video-search"
          class="video-search"
          phx-change="search"
          phx-submit="search"
        >
          <.input
            field={@form[:q]}
            type="search"
            class="video-search-input"
            placeholder="Quelle course, quel Grand Prix, quel tournoi ?"
            autocomplete="off"
            phx-debounce="250"
          />
        </.form>

        <button
          id="toggle-videos"
          type="button"
          class="version video-toggle"
          phx-click="toggle-all"
          aria-pressed={to_string(@revealed?)}
        >
          {if @revealed?, do: "Tout masquer", else: "Tout afficher"}
        </button>
      </header>

      <main>
        <p :if={@count == 0} id="videos-empty" class="videos-empty">
          {empty_message(@query)}
        </p>

        <ul id="videos" class="videos" phx-update="stream">
          <li :for={{id, video} <- @streams.videos} id={id} class="video">
            <%!-- A button, not a link to youtube.com: that page shows the title and
                 thumbnail. The player is embedded in this page instead. --%>
            <button
              type="button"
              phx-click="play"
              phx-value-id={video.youtube_id}
              aria-label={"Lire la vidéo du #{short_date(video.published_at)}"}
            >
              <div class="video-thumb">
                <%!-- Blurred, it is the 120x90 frame: there is nothing to recover
                     under the blur, and the sharp frame is not in the page until
                     asked for. No alt text: it would be the title. --%>
                <img
                  class={["video-img", !@revealed? && "spoiler-blur"]}
                  src={thumbnail(video, @revealed?)}
                  alt=""
                  loading="lazy"
                  referrerpolicy="no-referrer"
                />
              </div>
              <%!-- Blurred, no title is sent at all: only what was searched for,
                   at its place in the line, with a bar for each stretch of
                   hidden text. Revealed, the title is. Never both, so hiding
                   again really takes it back out of the page. --%>
              <p :if={@revealed?} class="video-title-text">{video.title}</p>
              <p :if={!@revealed? && video.segments} class="video-title is-inline">
                <%= for segment <- video.segments do %>
                  <%= case segment do %>
                    <% {:shown, text} -> %>
                      <mark class="video-match">{text}</mark>
                    <% {:hidden, length} -> %>
                      <span
                        :for={width <- bar_widths(length)}
                        class="video-redact"
                        aria-hidden="true"
                        style={"width: #{width}em"}
                      ></span>
                  <% end %>
                <% end %>
              </p>
              <div :if={!@revealed? && is_nil(video.segments)} class="video-title">
                <span
                  class="video-redact"
                  aria-hidden="true"
                  style={"width: #{bar(video.youtube_id, 70, 95)}%"}
                ></span>
                <span
                  class="video-redact"
                  aria-hidden="true"
                  style={"width: #{bar(video.youtube_id, 35, 65)}%"}
                ></span>
              </div>
              <p class="video-meta">
                <time datetime={DateTime.to_iso8601(video.published_at)}>
                  {short_date(video.published_at)}
                </time>
                <span class="video-views">{views(video.views)}</span>
              </p>
            </button>
          </li>
        </ul>
      </main>

      <div
        :if={@playing}
        id="player"
        class="player-backdrop"
        phx-window-keydown="close-player"
        phx-key="Escape"
      >
        <button id="player-close" type="button" class="player-close" phx-click="close-player">
          Fermer
        </button>

        <%!-- Keyed by video and ignored by LiveView: the hook changes data-state
             itself, and a patch must neither reset it nor reload the iframe. --%>
        <div
          id={"player-frame-#{@playing}"}
          class="player-frame"
          data-state="loading"
          phx-hook=".PlayerGuard"
          phx-update="ignore"
        >
          <iframe
            src={embed_url(@playing)}
            title="Lecteur vidéo"
            allow="autoplay; fullscreen; picture-in-picture; encrypted-media"
            allowfullscreen
            referrerpolicy="strict-origin-when-cross-origin"
          ></iframe>
          <%!-- The embed paints the video's title over its top-left corner, and
               a poster frame before playback. Both spoil, so both are covered:
               the corner for good, the rest until the video is playing. --%>
          <div class="player-title-guard"></div>
          <div class="player-cover">
            <span class="player-cover-text" data-for="loading">Chargement…</span>
            <span class="player-cover-hint" data-for="loading">
              Rien ne démarre ? Touchez ici pour lancer.
            </span>
            <span class="player-cover-text" data-for="ended">Vidéo terminée</span>
          </div>
        </div>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".PlayerGuard">
          // YouTube's embed reports playback state by postMessage once told we
          // are listening (it needs enablejsapi=1 on the iframe).
          const ORIGIN = "https://www.youtube-nocookie.com"
          const STATES = {0: "ended", 1: "playing", 2: "paused"}

          export default {
            mounted() {
              const frame = this.el.querySelector("iframe")

              this.onMessage = (event) => {
                if (event.source !== frame.contentWindow || event.origin !== ORIGIN) return

                let data
                try { data = JSON.parse(event.data) } catch { return }

                const code = data.event === "onStateChange" ? data.info
                  : data.event === "infoDelivery" && data.info ? data.info.playerState
                  : undefined

                if (code in STATES) this.el.dataset.state = STATES[code]
              }

              window.addEventListener("message", this.onMessage)

              frame.addEventListener("load", () => {
                frame.contentWindow.postMessage(
                  JSON.stringify({event: "listening", id: 1, channel: "widget"}),
                  ORIGIN
                )
              })
            },

            destroyed() {
              window.removeEventListener("message", this.onMessage)
            }
          }
        </script>
      </div>
    </div>
    """
  end

  defp embed_url(youtube_id) do
    query =
      URI.encode_query(
        autoplay: 1,
        rel: 0,
        enablejsapi: 1,
        playsinline: 1,
        modestbranding: 1,
        iv_load_policy: 3,
        cc_load_policy: 0,
        origin: SortirWeb.Endpoint.url()
      )

    "https://www.youtube-nocookie.com/embed/#{youtube_id}?#{query}"
  end

  defp thumbnail(video, true), do: "https://i.ytimg.com/vi/#{video.youtube_id}/hqdefault.jpg"
  defp thumbnail(video, false), do: "https://i.ytimg.com/vi/#{video.youtube_id}/default.jpg"

  defp empty_message(""), do: "Aucune vidéo pour l'instant."
  defp empty_message(_query), do: "Aucune vidéo ne correspond."

  # A stable pseudo-random width per video, so the placeholder lines differ
  # from card to card without moving between renders.
  defp bar(id, min, max), do: min + :erlang.phash2({id, min}, max - min + 1)

  # A hidden stretch drawn as bars half an em per character, about the width
  # of the text it stands for. Cut into bars of at most ten characters so a long
  # one can wrap onto the next line like words, instead of overflowing the card.
  @bar_chars 10

  defp bar_widths(length) do
    bars = ceil(length / @bar_chars)

    List.duplicate(:erlang.float_to_binary(length * 0.5 / bars, decimals: 2), bars)
  end

  defp views(1), do: "1 vue"
  defp views(count), do: "#{group(count)} vues"

  defp group(number) do
    Regex.replace(~r/\B(?=(\d{3})+(?!\d))/, Integer.to_string(number), " ")
  end

  @months ~w(janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.)

  defp short_date(%DateTime{} = at) do
    date = at |> Clock.to_local() |> DateTime.to_date()

    "#{date.day} #{Enum.at(@months, date.month - 1)} #{date.year}"
  end
end
