defmodule TripSwitch do
  @moduledoc """
  Documentation for `TripSwitch`.
  """
  use GenServer

  alias TripSwitch.Breaker

  @event_prefix :trip_switch

  @spec broken?(atom()) :: boolean()
  def broken?(id), do: Breaker.broken?(get(id))

  @spec send(atom(), Breaker.signal()) :: {:ok, term()} | :broken
  def send(id, signal) do
    :telemetry.span([@event_prefix, :signal], %{id: id}, fn ->
      with %Breaker{} = breaker <- get(id),
           {result, breaker} <- Breaker.handle(breaker, signal),
           :ok <- GenServer.call(via(id), {:save, breaker}) do
        {result, %{id: id}}
      end
    end)
  end

  @spec get(atom()) :: Breaker.t()
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
  def init(opts), do: {:ok, %{breaker: Breaker.new(opts), repair: nil}}

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
  def handle_info(:repair, %{breaker: breaker} = state) do
    [id] = Registry.keys(TripSwitch.Registry, self())

    state =
      Breaker.repair(breaker)
      |> schedule_or_cancel_repair(state)

    :telemetry.execute([@event_prefix, :repair, :done], %{}, %{id: id})

    {:noreply, state}
  end

  defp schedule_or_cancel_repair(%Breaker{fix_after: at} = breaker, state) do
    with {:a, true} <- {:a, Breaker.repairable?(breaker)},
         {:b, false} <- {:b, is_reference(state.repair)},
         timer <- Process.send_after(self(), :repair, at) do
      %{state | breaker: breaker, repair: timer}
    else
      {:a, false} -> cancel_timer(%{state | breaker: breaker})
      {:b, true} -> %{state | breaker: breaker}
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
