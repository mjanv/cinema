defmodule Sortir.Videos.Jobs.FetchTest do
  use Sortir.Cinema.DataCase, async: false

  use Oban.Testing,
    repo: Sortir.Core.Repo,
    engine: Oban.Engines.Lite,
    notifier: Oban.Notifiers.PG

  alias Sortir.Core.Repo
  alias Sortir.Videos
  alias Sortir.Videos.{FailingFeed, StaleFeed, StubFeed}
  alias Sortir.Videos.Jobs.Fetch

  setup do
    Repo.delete_all(Oban.Job)
    on_exit(fn -> Application.delete_env(:sortir, Sortir.Videos) end)
    :ok
  end

  test "saves what the feed returns" do
    Application.put_env(:sortir, Sortir.Videos, feed: StubFeed)

    assert :ok = perform_job(Fetch, %{})
    assert [%{youtube_id: "stub-1", views: 1234}] = Videos.list()
  end

  test "running twice does not duplicate" do
    Application.put_env(:sortir, Sortir.Videos, feed: StubFeed)

    perform_job(Fetch, %{})
    perform_job(Fetch, %{})

    assert [_] = Videos.list()
  end

  test "does not save a video past the retention period, or the prune would undo it hourly" do
    Application.put_env(:sortir, Sortir.Videos, feed: StaleFeed)

    assert :ok = perform_job(Fetch, %{})
    assert ["fresh"] = Enum.map(Videos.list(), & &1.youtube_id)
  end

  test "returns the error so Oban retries" do
    Application.put_env(:sortir, Sortir.Videos, feed: FailingFeed)

    assert {:error, {:http_status, 500}} = perform_job(Fetch, %{})
    assert [] = Videos.list()
  end

  test "Videos.refresh/0 queues one job, and not a second while one waits" do
    assert {:ok, 1} = Videos.refresh()
    assert {:ok, 0} = Videos.refresh()

    assert_enqueued(worker: Fetch)
  end

  describe "request_refresh/0 (a page was opened)" do
    test "queues a fetch" do
      assert {:ok, 1} = Videos.request_refresh()

      assert_enqueued(worker: Fetch)
    end

    test "does not queue a second while one is waiting" do
      assert {:ok, 1} = Videos.request_refresh()
      assert {:ok, 0} = Videos.request_refresh()
    end

    test "does not queue one within 15 minutes of a fetch that already finished" do
      # The feed is cached for 15 minutes by YouTube: another fetch before then
      # would return the same thing. Every page view would otherwise be one.
      {:ok, _} = Oban.insert(Fetch.new(%{}))
      Repo.update_all(Oban.Job, set: [state: "completed", completed_at: DateTime.utc_now()])

      assert {:ok, 0} = Videos.request_refresh()
    end

    test "queues one again once the last fetch is older than 15 minutes" do
      {:ok, _} = Oban.insert(Fetch.new(%{}))

      old = DateTime.add(DateTime.utc_now(), -16 * 60)
      Repo.update_all(Oban.Job, set: [state: "completed", inserted_at: old, completed_at: old])

      assert {:ok, 1} = Videos.request_refresh()
    end

    test "a cron run is never held back by a recent page-triggered fetch" do
      {:ok, _} = Oban.insert(Fetch.new(%{}))
      Repo.update_all(Oban.Job, set: [state: "completed", completed_at: DateTime.utc_now()])

      assert {:ok, %Oban.Job{conflict?: false}} = Oban.insert(Fetch.new(%{}))
    end
  end

  describe "telling open pages" do
    setup do
      Application.put_env(:sortir, Sortir.Videos, feed: StubFeed)
      :ok = Videos.subscribe()
    end

    test "broadcasts when a fetch brought a video we did not have" do
      perform_job(Fetch, %{})

      assert_receive :videos_updated
    end

    test "stays quiet when the fetch only found what we already had" do
      perform_job(Fetch, %{})
      assert_receive :videos_updated

      perform_job(Fetch, %{})

      refute_receive :videos_updated, 50
    end

    test "stays quiet when the fetch failed" do
      Application.put_env(:sortir, Sortir.Videos, feed: FailingFeed)

      perform_job(Fetch, %{})

      refute_receive :videos_updated, 50
    end
  end
end
