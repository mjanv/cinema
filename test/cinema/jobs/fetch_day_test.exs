defmodule Cinema.Jobs.FetchDayTest do
  use Cinema.DataCase, async: false

  # Oban.Testing builds its own config rather than reading ours, so the SQLite
  # engine and PG notifier have to be repeated here.
  use Oban.Testing,
    repo: Cinema.Repo,
    engine: Oban.Engines.Lite,
    notifier: Oban.Notifiers.PG

  alias Cinema.City
  alias Cinema.Jobs.FetchDay

  @city City.new("ville-98857", "Grenoble")

  setup do
    # Other tests call Cinema.schedule/2, which now enqueues; start each of
    # these from an empty queue so the counts mean what they say.
    Cinema.Repo.delete_all(Oban.Job)
    :ok
  end

  describe "enqueue/2" do
    test "queues one job per theater and date, not one per city" do
      # One job per fetch is what lets the queue pace them: a single job for a
      # whole city would burst all its requests inside one execution.
      assert {:ok, count} = FetchDay.enqueue(@city, days: 2)

      # The stub source has one theater in Grenoble.
      assert count == 2

      assert_enqueued(worker: FetchDay, args: %{"theater_id" => "T1"})
    end

    test "queues every cinema for a day before moving to the next day" do
      # At a queue limit of 1, cinema-major ordering fetches one cinema's whole
      # week first and leaves the board half-empty. Day-major means today is
      # complete everywhere before tomorrow starts.
      FetchDay.enqueue(@city, days: 3)

      dates =
        all_enqueued(worker: FetchDay)
        |> Enum.sort_by(& &1.id)
        |> Enum.map(& &1.args["date"])

      assert dates == Enum.sort(dates), "dates must not interleave"
    end

    test "carries what the worker needs to fetch and store" do
      FetchDay.enqueue(@city, days: 1)

      assert [job] = all_enqueued(worker: FetchDay)
      assert job.args["city_slug"] == "grenoble"
      assert job.args["theater_id"] == "T1"
      assert job.args["date"] == Date.to_iso8601(Cinema.today())
      assert job.queue == "allocine"
    end

    test "does not queue a duplicate for the same theater and date" do
      FetchDay.enqueue(@city, days: 1)
      FetchDay.enqueue(@city, days: 1)

      assert length(all_enqueued(worker: FetchDay)) == 1
    end
  end

  describe "enqueue_missing/4" do
    test "queues nothing once the data is cached" do
      # The loop this prevents: a finished job broadcasts, the page reloads with
      # refresh: true, and re-enqueueing the same work keeps the queue alive
      # forever while anyone has the page open.
      theaters = Cinema.StubSource.theaters(@city)
      today = Cinema.today()

      {:ok, first} = FetchDay.enqueue_missing(@city, theaters, today, 1)
      assert first == 1

      Oban.drain_queue(queue: :allocine)

      {:ok, second} = FetchDay.enqueue_missing(@city, theaters, today, 1)
      assert second == 0, "cached days must not be queued again"
    end

    test "queues only the days that are missing" do
      theaters = Cinema.StubSource.theaters(@city)
      today = Cinema.today()

      FetchDay.enqueue_missing(@city, theaters, today, 1)
      Oban.drain_queue(queue: :allocine)

      # Day one is cached, days two and three are not.
      {:ok, queued} = FetchDay.enqueue_missing(@city, theaters, today, 3)
      assert queued == 2
    end
  end

  describe "perform/1" do
    test "stores the screenings it fetched" do
      date = Cinema.today()

      assert :ok =
               perform_job(FetchDay, %{
                 "city_slug" => "grenoble",
                 "theater_id" => "T1",
                 "date" => Date.to_iso8601(date)
               })

      assert {:ok, [_ | _]} = FetchDay.fetched(@city, "T1", date)
    end

    test "cancels when the theater no longer exists in that city" do
      # The directory can refresh between queueing and running. Cancelling
      # records why in the job, rather than reporting a silent success.
      assert {:cancel, reason} =
               perform_job(FetchDay, %{
                 "city_slug" => "grenoble",
                 "theater_id" => "GONE",
                 "date" => Date.to_iso8601(Cinema.today())
               })

      assert reason =~ "GONE"
    end

    test "snoozes rather than failing when the source is rate limited" do
      # A 429 is not an error to retry immediately: backing off is the whole
      # point of pacing the queue.
      defmodule LimitedSource do
        @behaviour Cinema.Source
        @impl true
        def cities, do: [Cinema.City.new("ville-98857", "Grenoble")]
        @impl true
        def theaters(_city), do: [%Cinema.Theater{external_id: "T1", name: "Un"}]
        @impl true
        def fetch_day(_theater, _date), do: {:error, {:http_status, 429}}
      end

      put_source(LimitedSource)

      assert {:snooze, seconds} =
               perform_job(FetchDay, %{
                 "city_slug" => "grenoble",
                 "theater_id" => "T1",
                 "date" => Date.to_iso8601(Cinema.today())
               })

      assert seconds > 0
    end
  end

  defp put_source(module) do
    previous = Application.get_env(:cinema, Cinema.Showtimes, [])
    Application.put_env(:cinema, Cinema.Showtimes, Keyword.put(previous, :source, module))
    on_exit(fn -> Application.put_env(:cinema, Cinema.Showtimes, previous) end)
  end
end
