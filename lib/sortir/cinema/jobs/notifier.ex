defmodule Cinema.Jobs.Notifier do
  @moduledoc """
  Tells open pages when a city's schedule has changed.

  Fetching is asynchronous now, so a cold city renders an empty board and fills
  in as jobs land. This closes that loop: it listens for finished `FetchDay`
  jobs and broadcasts per city.

  Broadcasts are **coalesced**. A cold Paris finishes 525 jobs; one message per
  job would re-render every open board 525 times. Instead the first completion
  starts a short window and only one message goes out when it closes.
  """

  use GenServer

  alias Phoenix.PubSub

  @handler __MODULE__
  @pubsub Cinema.PubSub
  @worker "Cinema.Jobs.FetchDay"

  # Long enough to absorb a burst, short enough that the board feels live.
  @window_ms 750

  # --- public API --------------------------------------------------------

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Subscribes the calling process to one city's updates."
  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(city_slug), do: PubSub.subscribe(@pubsub, topic(city_slug))

  @doc false
  def attach do
    :telemetry.attach(
      @handler,
      [:oban, :job, :stop],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  @doc false
  def detach, do: :telemetry.detach(@handler)

  @doc false
  def handle_event([:oban, :job, :stop], _measure, %{job: %{worker: @worker} = job}, _config) do
    case job.args do
      %{"city_slug" => slug} -> GenServer.cast(__MODULE__, {:completed, slug})
      _no_city -> :ok
    end
  rescue
    # A notifier that raises must not take down the job that succeeded.
    _error -> :ok
  end

  def handle_event(_event, _measure, _meta, _config), do: :ok

  # --- server ------------------------------------------------------------

  @impl GenServer
  def init(_opts) do
    attach()
    {:ok, %{pending: MapSet.new(), timer: nil}}
  end

  @impl GenServer
  def handle_cast({:completed, slug}, state) do
    pending = MapSet.put(state.pending, slug)
    {:noreply, %{state | pending: pending, timer: state.timer || schedule_flush()}}
  end

  @impl GenServer
  def handle_info(:flush, state) do
    for slug <- state.pending do
      PubSub.broadcast(@pubsub, topic(slug), {:schedule_updated, slug})
    end

    {:noreply, %{state | pending: MapSet.new(), timer: nil}}
  end

  @impl GenServer
  def terminate(_reason, _state) do
    detach()
    :ok
  end

  defp schedule_flush, do: Process.send_after(self(), :flush, @window_ms)

  defp topic(city_slug), do: "schedule:#{city_slug}"
end
