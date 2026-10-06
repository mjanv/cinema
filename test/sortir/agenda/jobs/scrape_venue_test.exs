defmodule Sortir.Agenda.Jobs.ScrapeVenueTest do
  use Sortir.Cinema.DataCase, async: false

  use Oban.Testing,
    repo: Sortir.Core.Repo,
    engine: Oban.Engines.Lite,
    notifier: Oban.Notifiers.PG

  alias Sortir.Agenda
  alias Sortir.Agenda.Event
  alias Sortir.Agenda.Jobs.ScrapeVenue
  alias Sortir.Core.Repo

  setup do
    Repo.delete_all(Oban.Job)
    :ok
  end

  describe "perform/1 without a source" do
    test "fans out to one job per source" do
      # This is the shape the nightly cron inserts: no args. It must queue the
      # sources rather than crash on a missing key.
      assert :ok = perform_job(ScrapeVenue, %{})

      queued =
        Oban.Job
        |> Repo.all()
        |> Enum.map(& &1.args["source"])
        |> Enum.reject(&is_nil/1)

      assert length(queued) == length(Agenda.sources())

      for source <- Agenda.sources() do
        assert to_string(source) in queued
      end
    end
  end

  describe "enqueue/2" do
    test "queues one job per venue, not one per month" do
      # A page carries several months and links onward, so the job follows the
      # venue's own pagination rather than guessing a month at a time.
      assert {:ok, 1} = ScrapeVenue.enqueue(Agenda.StubSource)

      assert length(all_enqueued(worker: ScrapeVenue)) == 1
    end

    test "carries the source to scrape" do
      ScrapeVenue.enqueue(Agenda.StubSource)

      assert [job] = all_enqueued(worker: ScrapeVenue)
      assert job.args["source"] == "Elixir.Sortir.Agenda.StubSource"
      assert job.queue == "agenda"
    end

    test "does not queue the same venue twice" do
      ScrapeVenue.enqueue(Agenda.StubSource)
      ScrapeVenue.enqueue(Agenda.StubSource)

      assert length(all_enqueued(worker: ScrapeVenue)) == 1
    end
  end

  describe "perform/1" do
    test "stores what the source returned" do
      assert :ok = perform_job(ScrapeVenue, args_for(Agenda.StubSource))

      assert Repo.aggregate(Event, :count) == 2
      assert [event] = Repo.all(from(e in Event, where: e.external_id == "stub-1"))
      assert event.title == "Un concert"
    end

    test "creates the venue on first run" do
      perform_job(ScrapeVenue, args_for(Agenda.StubSource))

      assert Repo.aggregate(Agenda.Venue, :count) == 1
    end

    test "running twice does not duplicate" do
      perform_job(ScrapeVenue, args_for(Agenda.StubSource))
      perform_job(ScrapeVenue, args_for(Agenda.StubSource))

      assert Repo.aggregate(Event, :count) == 2
    end

    test "snoozes rather than failing when the venue rate limits" do
      assert {:snooze, seconds} = perform_job(ScrapeVenue, args_for(Agenda.LimitedSource))
      assert seconds > 0
    end

    test "cancels for a source that no longer exists" do
      args = %{"source" => "Elixir.Nope.Gone"}

      assert {:cancel, reason} = perform_job(ScrapeVenue, args)
      assert reason =~ "Nope.Gone"
    end

    test "keeps the events it could parse when one is unusable" do
      # One bad entry must not lose the whole month.
      assert :ok = perform_job(ScrapeVenue, args_for(Agenda.PartialSource))

      assert Repo.aggregate(Event, :count) == 1
    end
  end

  defp args_for(source), do: %{"source" => to_string(source)}
end
