defmodule SortirWeb.VideosLiveTest do
  use SortirWeb.ConnCase, async: false

  use Oban.Testing,
    repo: Sortir.Core.Repo,
    engine: Oban.Engines.Lite,
    notifier: Oban.Notifiers.PG

  import Phoenix.LiveViewTest

  alias Sortir.Core.Repo
  alias Sortir.Videos
  alias Sortir.Videos.Jobs.Fetch
  alias Sortir.Videos.StubFeed

  @spoiler "Pogacar s'impose"

  setup do
    {:ok, _} =
      Videos.save(%{
        youtube_id: "lomb",
        title: "Tour de Lombardie : #{@spoiler}",
        published_at: ~U[2026-10-05 12:00:00Z],
        views: 12_345
      })

    {:ok, _} =
      Videos.save(%{
        youtube_id: "bahr",
        title: "Grand Prix de Bahreïn : Verstappen vainqueur",
        published_at: ~U[2026-10-04 12:00:00Z],
        views: 87
      })

    :ok
  end

  describe "fetching on page load" do
    setup do
      Repo.delete_all(Oban.Job)
      on_exit(fn -> Application.delete_env(:sortir, Sortir.Videos) end)
    end

    test "opening the page queues a fetch in the background", %{conn: conn} do
      {:ok, _view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

      assert_enqueued(worker: Fetch)
    end

    test "the static first render does not: only the live connection does", %{conn: conn} do
      # A crawler or link preview reads the static page and never connects.
      get(conn, ~p"/nospoil/eurosportfrance")

      refute_enqueued(worker: Fetch)
    end

    test "opening the page again soon after does not queue another", %{conn: conn} do
      {:ok, _view, _html} = live(conn, ~p"/nospoil/eurosportfrance")
      {:ok, _view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

      assert [_] = all_enqueued(worker: Fetch)
    end

    test "a video fetched after the page loaded appears without a reload", %{conn: conn} do
      Application.put_env(:sortir, Sortir.Videos, feed: StubFeed)
      {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")
      refute has_element?(view, "#video-stub-1")

      perform_job(Fetch, %{})

      assert has_element?(view, "#video-stub-1")
    end

    test "the refresh keeps the search and the revealed state", %{conn: conn} do
      Application.put_env(:sortir, Sortir.Videos, feed: StubFeed)
      {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance?q=bahrein")
      view |> element("#toggle-videos") |> render_click()

      perform_job(Fetch, %{})

      assert has_element?(view, "#video-bahr img[src$='/bahr/hqdefault.jpg']")
      refute has_element?(view, "#video-stub-1")
    end

    test "the refresh does not close a player that is open", %{conn: conn} do
      Application.put_env(:sortir, Sortir.Videos, feed: StubFeed)
      {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")
      view |> element("#video-lomb button") |> render_click()

      perform_job(Fetch, %{})

      assert has_element?(view, "#player iframe[src*='/embed/lomb?']")
    end
  end

  test "lists every video as a card", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

    assert has_element?(view, "#video-lomb")
    assert has_element?(view, "#video-bahr")
  end

  test "is standalone: no link to the other pages", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

    refute has_element?(view, "nav")
    refute has_element?(view, "a[href='/']")
    refute has_element?(view, "a[href^='/agenda']")
  end

  test "never puts a title in the page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/nospoil/eurosportfrance")

    refute html =~ "Lombardie"
    refute html =~ @spoiler
    refute html =~ "Verstappen"
  end

  test "thumbnails are the tiny frame, blurred, with no alt text", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

    assert has_element?(view, "#video-lomb img.spoiler-blur[src$='/lomb/default.jpg'][alt='']")
    refute has_element?(view, "img[src*='hqdefault']")
    refute has_element?(view, "img[src*='maxresdefault']")
  end

  test "shows the publication date and the view count", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

    assert has_element?(view, "#video-lomb time[datetime='2026-10-05T12:00:00Z']")
    assert has_element?(view, "#video-lomb .video-views", "12 345")
  end

  test "searching keeps only the matching videos", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

    view |> form("#video-search", %{q: "lombardie"}) |> render_change()

    assert has_element?(view, "#video-lomb")
    refute has_element?(view, "#video-bahr")
  end

  test "searching stays on the page's path and clearing returns to it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

    view |> form("#video-search", %{q: "lombardie"}) |> render_change()
    assert_patch(view, "/nospoil/eurosportfrance?q=lombardie")

    view |> form("#video-search", %{q: ""}) |> render_change()
    assert_patch(view, "/nospoil/eurosportfrance")
  end

  test "search ignores case and accents", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

    view |> form("#video-search", %{q: "BAHREIN"}) |> render_change()

    assert has_element?(view, "#video-bahr")
    refute has_element?(view, "#video-lomb")
  end

  test "a match shows the part of the title that matched, as spelled", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

    view |> form("#video-search", %{q: "bahrein"}) |> render_change()

    assert has_element?(view, "#video-bahr .video-match", "Bahreïn")
  end

  test "a match sits inside the title line, between bars for what is hidden", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

    view |> form("#video-search", %{q: "lombardie"}) |> render_change()

    assert has_element?(view, "#video-lomb .video-title mark.video-match", "Lombardie")
    # "Tour de " before it, " : Pogacar s'impose" after it.
    assert has_element?(view, "#video-lomb .video-title .video-redact[style*='width']")
  end

  test "the bars add up to the length of what they hide, not its text", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance?q=lombardie")

    html = view |> element("#video-lomb .video-title") |> render()

    # "Tour de " (8) and " : Pogacar s'impose" (19) hidden: 27 characters at
    # half an em each. Long runs are cut into several bars so they can wrap.
    widths =
      ~r/width: ([\d.]+)em/
      |> Regex.scan(html, capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(&String.to_float/1)

    assert_in_delta Enum.sum(widths), 13.5, 0.05
    refute html =~ "Tour"
    refute html =~ "Pogacar"
  end

  test "a short run is one bar, a long one wraps over several", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance?q=lombardie")

    # Before the match: "Tour de " is 8 characters, so one bar. After it: 19, so two.
    assert has_element?(view, "#video-lomb .video-title .video-redact[style='width: 4.00em']")

    assert view
           |> element("#video-lomb .video-title")
           |> render()
           |> String.split("video-redact")
           |> length() == 4
  end

  test "without a search the bars are anonymous", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

    assert has_element?(view, "#video-lomb .video-title .video-redact")
    refute has_element?(view, ".video-title mark")
  end

  test "no match is shown without a search", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

    refute has_element?(view, ".video-match")
  end

  test "the match never reveals the rest of the title", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

    html = view |> form("#video-search", %{q: "bahrein"}) |> render_change()

    refute html =~ "Verstappen"
    refute html =~ "vainqueur"
    refute html =~ "Grand Prix de"
  end

  test "searching does not echo a title back", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

    html = view |> form("#video-search", %{q: "lombardie"}) |> render_change()

    refute html =~ @spoiler
  end

  test "an empty search says so", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

    view |> form("#video-search", %{q: "roland garros"}) |> render_change()

    assert has_element?(view, "#videos-empty")
    refute has_element?(view, "#video-lomb")
  end

  test "clearing the search brings everything back", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

    view |> form("#video-search", %{q: "lombardie"}) |> render_change()
    view |> form("#video-search", %{q: ""}) |> render_change()

    assert has_element?(view, "#video-lomb")
    assert has_element?(view, "#video-bahr")
  end

  test "the query lives in the URL so a search can be shared", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance?q=lombardie")

    assert has_element?(view, "#video-lomb")
    refute has_element?(view, "#video-bahr")
    assert has_element?(view, "#video-search input[value=lombardie]")
  end

  describe "blur all / unblur all" do
    test "thumbnails start blurred, with a button to reveal them", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

      assert has_element?(view, "#video-lomb img.spoiler-blur")
      assert has_element?(view, "#toggle-videos[aria-pressed=false]", "Tout afficher")
    end

    test "revealing all removes the blur and loads the sharp frame", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

      view |> element("#toggle-videos") |> render_click()

      refute has_element?(view, "img.spoiler-blur")
      assert has_element?(view, "#video-lomb img[src$='/lomb/hqdefault.jpg']")
      assert has_element?(view, "#video-bahr img[src$='/bahr/hqdefault.jpg']")
      assert has_element?(view, "#toggle-videos[aria-pressed=true]", "Tout masquer")
    end

    test "hiding all again blurs everything and drops the sharp frame", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

      view |> element("#toggle-videos") |> render_click()
      view |> element("#toggle-videos") |> render_click()

      assert has_element?(view, "#video-lomb img.spoiler-blur")
      refute has_element?(view, "img[src*='hqdefault']")
    end

    test "stays revealed while searching", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

      view |> element("#toggle-videos") |> render_click()
      view |> form("#video-search", %{q: "lombardie"}) |> render_change()

      assert has_element?(view, "#video-lomb img[src$='/lomb/hqdefault.jpg']")
      refute has_element?(view, "#video-bahr")
    end

    test "revealing shows every title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

      view |> element("#toggle-videos") |> render_click()

      assert has_element?(view, "#video-lomb .video-title-text", "Pogacar s'impose")
      assert has_element?(view, "#video-bahr .video-title-text", "Verstappen vainqueur")
      refute has_element?(view, ".video-title span")
    end

    test "hiding all again takes the titles back out of the page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

      view |> element("#toggle-videos") |> render_click()
      html = view |> element("#toggle-videos") |> render_click()

      refute has_element?(view, ".video-title-text")
      refute html =~ "Pogacar"
      refute html =~ "Verstappen"
      assert has_element?(view, "#video-lomb .video-title span")
    end

    test "searching while revealed shows only the matching titles", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

      view |> element("#toggle-videos") |> render_click()
      view |> form("#video-search", %{q: "bahrein"}) |> render_change()

      assert has_element?(view, "#video-bahr .video-title-text")
      refute has_element?(view, "#video-lomb")
    end

    test "the match chip is redundant once the title is shown", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance?q=bahrein")

      assert has_element?(view, "#video-bahr .video-match")

      view |> element("#toggle-videos") |> render_click()

      refute has_element?(view, ".video-match")
    end
  end

  describe "playing a video" do
    defp play(view, id), do: view |> element("#video-#{id} button") |> render_click()

    test "no card links to youtube.com, whose page shows the title and thumbnail", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

      refute has_element?(view, "a[href*='youtube.com']")
      refute has_element?(view, "a[href*='youtu.be']")
    end

    test "nothing is loaded from YouTube until a card is clicked", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

      refute has_element?(view, "iframe")
      refute has_element?(view, "#player")
    end

    test "clicking a card plays it in an embedded player, autoplaying", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

      play(view, "lomb")

      assert has_element?(
               view,
               "#player iframe[src^='https://www.youtube-nocookie.com/embed/lomb?']"
             )

      src =
        view
        |> element("#player iframe")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.attribute("src")
        |> hd()

      query = src |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

      # autoplay: no poster frame, which is a thumbnail. rel=0: end-screen
      # suggestions come only from this channel. enablejsapi: lets the page
      # see when playback starts and ends, to cover what would spoil.
      assert %{"autoplay" => "1", "rel" => "0", "enablejsapi" => "1", "playsinline" => "1"} =
               query
    end

    test "the player carries no title, in the iframe or around it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

      html = play(view, "lomb")

      refute html =~ "Pogacar"
      refute html =~ "Lombardie"
      assert has_element?(view, "#player iframe[title='Lecteur vidéo']")
    end

    test "the player is covered until playback starts and over the title corner", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

      play(view, "lomb")

      assert has_element?(view, "#player .player-frame[data-state=loading]")
      assert has_element?(view, "#player .player-cover")
      assert has_element?(view, "#player .player-title-guard")
    end

    test "closing removes the player and the iframe", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

      play(view, "lomb")
      view |> element("#player-close") |> render_click()

      refute has_element?(view, "#player")
      refute has_element?(view, "iframe")
    end

    test "Escape closes it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

      play(view, "lomb")
      render_keydown(view, "close-player", %{"key" => "Escape"})

      refute has_element?(view, "#player")
    end

    test "playing another video replaces the first", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

      play(view, "lomb")
      play(view, "bahr")

      assert has_element?(view, "#player iframe[src*='/embed/bahr?']")
      refute has_element?(view, "iframe[src*='/embed/lomb?']")
    end

    test "an id that is not one of ours plays nothing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

      render_click(view, "play", %{"id" => "dQw4w9WgXcQ"})

      refute has_element?(view, "#player")
    end

    test "playing does not change what the grid shows", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

      play(view, "lomb")

      assert has_element?(view, "#video-lomb img.spoiler-blur")
      assert has_element?(view, "#video-bahr")
    end

    test "cards are buttons with a label that leaves out the title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/nospoil/eurosportfrance")

      assert has_element?(view, "#video-lomb button[aria-label^='Lire la vidéo du']")
    end
  end
end
