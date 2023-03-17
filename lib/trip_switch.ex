defmodule TripSwitch do
  @moduledoc """
  Documentation for `TripSwitch`.
  """
  use GenServer

  alias TripSwitch.Circuit

  @event_prefix :trip_switch

  @spec broken?(atom()) :: boolean()
  def broken?(id), do: Circuit.broken?(get(id))

  @spec send(atom(), Circuit.signal()) :: {:ok, term()} | :broken
  def send(id, signal) do
    :telemetry.span([@event_prefix, :signal], %{id: id}, fn ->
      with %Circuit{} = circuit <- get(id),
           {result, circuit} <- Circuit.handle(circuit, signal),
           :ok <- GenServer.call(via(id), {:save, circuit}) do
        {result, %{id: id}}
      end
    end)
  end

  @spec get(atom()) :: Circuit.t()
  def get(id), do: GenServer.call(via(id), :get)

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
  def init(opts), do: {:ok, %{circuit: Circuit.new(opts), repair: nil}}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)

    GenServer.start_link(__MODULE__, opts, name: via(name))
  end

  @impl GenServer
  def handle_call(:get, _from, %{circuit: circuit} = state) do
    {:reply, circuit, state}
  end

  def handle_call(:reset, _from, %{circuit: circuit} = state) do
    state = cancel_timer(%{state | circuit: Circuit.reset(circuit)})

    {:reply, :ok, state}
  end

  def handle_call({:save, circuit}, _from, state) do
    state = schedule_or_cancel_repair(circuit, state)

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info(:repair, %{circuit: circuit} = state) do
    [id] = Registry.keys(TripSwitch.Registry, self())

    state =
      Circuit.repair(circuit)
      |> schedule_or_cancel_repair(state)

    :telemetry.execute([@event_prefix, :repair, :done], %{}, %{id: id})

    {:noreply, state}
  end

  defp schedule_or_cancel_repair(%Circuit{fix_after: at} = circuit, state) do
    with {:a, true} <- {:a, Circuit.repairable?(circuit)},
         {:b, false} <- {:b, is_reference(state.repair)},
         timer <- Process.send_after(self(), :repair, at) do
      %{state | circuit: circuit, repair: timer}
    else
      {:a, false} -> cancel_timer(%{state | circuit: circuit})
      {:b, true} -> %{state | circuit: circuit}
    end
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

  defp via(id), do: {:via, Registry, {TripSwitch.Registry, id}}
end
