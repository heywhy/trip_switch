defmodule TripSwitch do
  @moduledoc """
  TripSwitch is an Elixir implementation of a circuit breaker. The circuit
  breaker is a popular pattern in softwares that depends on various
  components/services to keep running.

  This library allows you wrap calls (signals) to remote calls in a trip switch.
  The switch monitors each invocation and records failures, the trip switch gets
  broken once the recorded failures reaches or surpasses the specified threshold.

  ## Signal

  A signal is simple a function that gets invoked. The state of the trip switch gets
  updated based on the result of this signal, see `t:TripSwitch.Breaker.signal/0`.

  ### Examples

      iex> TripSwitch.send(id, fn -> {:ok, :good} end)
      {:ok, :good}
      iex> TripSwitch.send(id, fn -> {:break, :good} end) # record this signal as a failure
      {:ok, :good}

  Note that a switch only stops invoking a signal after the failure threshold have been
  reached. In this case, the switch keeps is considered `broken` until it's repaired.

  ## Repairs

  It's obvious you are asking yourself what you should do when a trip switch gets broken. This
  library have a concept called Repair. What this means is that a switch is sent for repair
  automatically once it gets broken. Not all trip switches are considered fixable, you
  need to specify a `repair_time` (in milliseconds) when the trip switch is created
  else you need to manually fix (reset) the trip switch whenever it gets broken.

  ## Thresholds

  For a trip switch to function correctly, a threshold is needed to be specified. This allows
  us to define the capacity/expectation of the trip switch. The threshold is specified as
  a float value, usually between 0 and 1 (ex. 0.2566 or 0.13 and so on).

  Simply, a threshold is the percentage of bad signals a trip switch receives before it gets
  broken and sent for repair.

  ## Usage

  To create a trip switch you need to add it to your supervision tree:

  ```elixir
  children = [{TripSwitch, name: :switch, threshold: 0.5}]

  Supervisor.start_link(children, opts)
  ```

  It supports following options:

  - `:name` - this will be used as the id for the switch
  - `:threshold` - the maximum number of thresholds before the switch trips
  - `:repair_time` - time taken for the switch to get fixed after it gets broken

  ## Telemetry

  Being a big fan of observability, this library exposes information about it internals
  using the community approved library (`telemetry`). You can use the `telemetry_poller`
  library to poll these metrics. Below are events that this library publishes.

  Below are events published by `trip_switch`:

  * `[:trip_switch, :signal, :start]` - dispatched before a given signal is handled
    * Measurement: `%{system_time: system_time}`
    * Metadata: `%{id: atom(), tag: String.t()}`

  * `[:trip_switch, :signal, :stop]` - dispatched after a given signal have been handled
    * Measurement: ` %{duration: native_time}`
    * Metadata: `%{id: atom(), tag: String.t()}`

  * `[:trip_switch, :repair, :start]` - dispatched when auto-repair is scheduled
    * Measurement: `%{system_time: system_time}`
    * Metadata: `%{id: atom(), tag: String.t()}`

  * `[:trip_switch, :repair, :stop]` - dispatched after an auto-repair have been completed
    * Measurement: ` %{duration: native_time}`
    * Metadata: `%{id: atom(), tag: String.t()}`
  """
  use GenServer

  alias TripSwitch.Breaker

  @event_prefix :trip_switch

  @doc """
  Checks if the switch is broken.

  A switch is considered broken if the underlying breaker is `half_open` or `open`.

  ## Examples

      iex> TripSwitch.broken?(:switch)
      true
  """
  @spec broken?(atom()) :: boolean()
  def broken?(id), do: Breaker.broken?(get(id))

  @doc """
  Send a signal to the underlying breaker.

  The signal is a function that performs some actions then return
  a result that alters the state of the underlying breaker.

  ## Examples

      iex> TripSwitch.send(:switch, fn -> {:ok, %{name: "a"}}) end)
      {:ok, %{name: "a"}}
      iex> TripSwitch.send(:switch, fn -> {:break, {:error, :not_found}} end)
      {:error, :not_found}
  """
  @spec send(atom(), Breaker.signal()) :: {:ok, term()} | :broken
  def send(id, signal) do
    metadata = %{id: id, tag: FlakeId.get()}

    :telemetry.span([@event_prefix, :signal], metadata, fn ->
      with %Breaker{} = breaker <- get(id),
           {result, breaker} <- Breaker.handle(breaker, signal),
           :ok <- GenServer.call(via(id), {:save, breaker}) do
        {result, metadata}
      end
    end)
  end

  @doc """
  Reset the given switch.

  Calling this function on a broken switch returns it to a working state.

  ### Examples

        iex> TripSwitch.reset(:switch)
        :ok
  """
  @spec reset(atom()) :: :ok
  def reset(id), do: GenServer.call(via(id), :reset)

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    unless name = opts[:name] do
      raise ArgumentError, "expected :name option to be present"
    end

    Supervisor.child_spec(super(opts), id: {__MODULE__, name})
  end

  @impl GenServer
  def init(opts), do: {:ok, %{breaker: Breaker.new(opts), repair: nil}}

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)

    GenServer.start_link(__MODULE__, opts, name: via(name))
  end

  @impl GenServer
  def handle_call(:get, _from, %{breaker: breaker} = state) do
    {:reply, breaker, state}
  end

  def handle_call(:reset, _from, %{breaker: breaker} = state) do
    state = cancel_timer(%{state | breaker: Breaker.reset(breaker)})

    {:reply, :ok, state}
  end

  def handle_call({:save, breaker}, _from, state) do
    state = schedule_or_cancel_repair(breaker, state)

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({:repair, start_time, tag}, %{breaker: breaker} = state) do
    state =
      Breaker.repair(breaker)
      |> schedule_or_cancel_repair(state)

    :ok = emit_repair_stop_event(get_id(), start_time, tag)

    {:noreply, state}
  end

  defp schedule_or_cancel_repair(%Breaker{repair_time: at} = breaker, state) do
    with {:a, true} <- {:a, Breaker.repairable?(breaker)},
         {:b, false} <- {:b, is_reference(state.repair)},
         {start_time, tag} <- emit_repair_start_event(get_id()),
         timer <- Process.send_after(self(), {:repair, start_time, tag}, at) do
      %{state | breaker: breaker, repair: timer}
    else
      {:a, false} -> cancel_timer(%{state | breaker: breaker})
      {:b, true} -> %{state | breaker: breaker}
    end
  end

  defp get_id do
    [id] = Registry.keys(TripSwitch.Registry, self())
    id
  end

  defp cancel_timer(state) do
    case state.repair do
      ref when is_reference(ref) ->
        Process.cancel_timer(ref)
        %{state | repair: nil}

      nil ->
        state
    end
  end

  defp emit_repair_start_event(id) do
    tag = FlakeId.get()
    now = System.system_time()
    metadata = %{id: id, tag: tag}
    measurements = %{monotonic_time: System.monotonic_time(), system_time: now}

    :ok = :telemetry.execute([@event_prefix, :repair, :start], measurements, metadata)

    {now, tag}
  end

  defp emit_repair_stop_event(id, start_time, tag) do
    now = System.monotonic_time()
    metadata = %{id: id, tag: tag}

    measurements = %{
      monotonic_time: now,
      duration: start_time - now
    }

    :ok = :telemetry.execute([@event_prefix, :repair, :stop], measurements, metadata)
  end

  defp get(id), do: GenServer.call(via(id), :get)
  defp via(id), do: {:via, Registry, {TripSwitch.Registry, id}}
end
