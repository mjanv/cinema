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
