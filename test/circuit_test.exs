defmodule TripSwitch.CircuitTest do
  @moduledoc false
  use ExUnit.Case

  alias TripSwitch.Circuit

  setup do
    {:ok, circuit: Circuit.new(threshold: 1, fix_after: 1_000)}
  end

  test "broken circuit with heal time repaired", %{circuit: circuit} do
    assert Circuit.repair(circuit) == circuit
    assert {{:ok, :melt}, circuit} = Circuit.handle(circuit, fn -> {:break, :melt} end)
    refute Circuit.repair(circuit) == circuit
  end

  test "broken circuit with no heal time not repaired", %{circuit: circuit} do
    {_result, circuit} = break_circuit(%{circuit | fix_after: 0})

    assert Circuit.repair(circuit) == circuit
  end

  test "increment counter on good signal", %{circuit: circuit} do
    assert {{:ok, :good}, circuit} = Circuit.handle(circuit, fn -> {:ok, :good} end)
    assert %Circuit{counter: 1, state: :closed, surges: 0} = circuit
  end

  test "increment surges on bad signal and open circuit", %{circuit: circuit} do
    assert {{:ok, :bad}, circuit} = break_circuit(circuit)
    assert %Circuit{counter: 1, state: :open, surges: 1} = circuit
  end

  test "broken circuit can't handle any signal", %{circuit: circuit} do
    {{:ok, :bad}, circuit} = break_circuit(circuit)

    assert {:broken, circuit} = Circuit.handle(circuit, fn -> {:ok, :good} end)
    assert %Circuit{counter: 1, state: :open, surges: 1} = circuit
  end

  test "half open circuit healed successfully", %{circuit: circuit} do
    {_result, circuit} = break_circuit(circuit)
    circuit = Circuit.repair(circuit)

    assert %Circuit{state: :half_open} = circuit
    assert {_result, circuit} = Circuit.handle(circuit, fn -> {:ok, :good} end)
    assert %Circuit{state: :closed} = circuit
  end

  test "half open circuit gets opened completely", %{circuit: circuit} do
    {_result, circuit} = break_circuit(circuit)
    circuit = Circuit.repair(circuit)

    assert %Circuit{state: :half_open} = circuit
    assert {_result, circuit} = break_circuit(circuit)
    assert %Circuit{state: :open} = circuit
  end

  defp break_circuit(circuit) do
    Circuit.handle(circuit, fn -> {:break, :bad} end)
  end
end
