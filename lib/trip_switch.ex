defmodule TripSwitch do
  @moduledoc """
  Documentation for `TripSwitch`.
  """
  use GenServer

  alias TripSwitch.Circuit

  @spec send(atom(), Circuit.signal()) :: {:ok, term()} | :broken
  def send(id, signal) do
    GenServer.call(via(id), {:send, signal})
  end

  @spec get(atom()) :: Circuit.t() | nil
  def get(id) do
    case Registry.lookup(TripSwitch.Registry, id) do
      [] -> nil
      [{pid, _}] -> GenServer.call(pid, :get)
    end
  end

  @spec reset(atom()) :: :ok
  def reset(id) do
    GenServer.call(via(id), :reset)
  end

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
    {:reply, :ok, %{state | circuit: Circuit.reset(circuit)}}
  end

  def handle_call({:send, signal}, _from, %{circuit: circuit} = state) do
    {result, circuit} = Circuit.handle(circuit, signal)

    state = schedule_or_cancel_repair(circuit, state)

    {:reply, result, state}
  end

  @impl GenServer
  def handle_info(:repair, %{circuit: circuit} = state) do
    state = schedule_or_cancel_repair(Circuit.repair(circuit), state)

    {:noreply, state}
  end

  defp schedule_or_cancel_repair(
         %Circuit{state: :open, fix_after: time} = circuit,
         %{repair: nil} = state
       )
       when time > 0 do
    timer = Process.send_after(self(), :repair, time)

    %{state | circuit: circuit, repair: timer}
  end

  defp schedule_or_cancel_repair(
         %Circuit{state: :open} = circuit,
         %{repair: ref} = state
       )
       when is_reference(ref) do
    %{state | circuit: circuit}
  end

  defp schedule_or_cancel_repair(%Circuit{} = circuit, state) do
    case state.repair do
      nil -> :ok
      ref -> Process.cancel_timer(ref)
    end

    %{state | circuit: circuit, repair: nil}
  end

  defp via(id), do: {:via, Registry, {TripSwitch.Registry, id}}
end
