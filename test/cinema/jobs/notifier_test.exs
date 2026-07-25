defmodule Cinema.Jobs.NotifierTest do
  use Cinema.DataCase, async: false

  alias Cinema.Jobs.Notifier

  setup do
    Notifier.attach()
    on_exit(&Notifier.detach/0)
    :ok
  end

  test "broadcasts to subscribers of the city a job finished for" do
    Notifier.subscribe("grenoble")

    emit_stop("grenoble")

    assert_receive {:schedule_updated, "grenoble"}, 1_000
  end

  test "does not broadcast a city you are not watching" do
    Notifier.subscribe("grenoble")

    emit_stop("lyon")

    refute_receive {:schedule_updated, _slug}, 200
  end

  test "coalesces a burst into few messages" do
    # A cold Paris finishes 525 jobs; one push per job would re-render the
    # board hundreds of times.
    Notifier.subscribe("grenoble")

    for _ <- 1..20, do: emit_stop("grenoble")

    assert_receive {:schedule_updated, "grenoble"}, 1_000
    # Well under one message per job.
    assert drain_messages() < 20
  end

  test "ignores jobs from other workers" do
    Notifier.subscribe("grenoble")

    :telemetry.execute(
      [:oban, :job, :stop],
      %{duration: 1},
      %{job: %Oban.Job{worker: "Some.Other.Worker", args: %{"city_slug" => "grenoble"}}}
    )

    refute_receive {:schedule_updated, _slug}, 200
  end

  defp emit_stop(slug) do
    :telemetry.execute(
      [:oban, :job, :stop],
      %{duration: 1},
      %{
        job: %Oban.Job{
          worker: "Cinema.Jobs.FetchDay",
          args: %{"city_slug" => slug, "theater_id" => "T1", "date" => "2026-07-26"}
        }
      }
    )
  end

  defp drain_messages(count \\ 0) do
    receive do
      {:schedule_updated, _slug} -> drain_messages(count + 1)
    after
      300 -> count
    end
  end
end
