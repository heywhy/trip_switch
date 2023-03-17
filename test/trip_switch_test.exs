defmodule TripSwitchTest do
  @moduledoc false
  use ExUnit.Case

  alias TripSwitch.Circuit

  @circuit :home
  @event_prefix :trip_switch
  @events [
    [@event_prefix, :repair, :done],
    [@event_prefix, :signal, :start],
    [@event_prefix, :signal, :stop]
  ]

  setup_all do
    start_supervised!({TripSwitch, name: @circuit, threshold: 0.9, fix_after: 100})
    :ok
  end

  setup do
    :telemetry_test.attach_event_handlers(self(), @events)

    on_exit(fn -> TripSwitch.reset(@circuit) end)
  end

  test "child_spec/1" do
    assert %{id: {TripSwitch, :dummy}} = TripSwitch.child_spec(name: :dummy)

    assert_raise ArgumentError, "expected :name option to be present", fn ->
      TripSwitch.child_spec([])
    end
  end

  test "get/1" do
    refute TripSwitch.get(:unknown)
    assert %Circuit{state: :closed} = TripSwitch.get(@circuit)
  end

  test "send/2" do
    assert {:ok, 9} = TripSwitch.send(@circuit, fn -> {:ok, 9} end)
    assert {:ok, 90} = TripSwitch.send(@circuit, fn -> {:break, 90} end)

    assert_received {[@event_prefix, :signal, :start], _ref, _measurements, %{id: @circuit}}
    assert_received {[@event_prefix, :signal, :stop], _ref, _measurements, %{id: @circuit}}
  end

  test "send/2 breaks circuit after failure threshold is reached" do
    for _ <- 1..3 do
      TripSwitch.send(@circuit, fn -> {:break, 90} end)
    end

    assert :broken = TripSwitch.send(@circuit, fn -> {:ok, 1} end)
  end

  test "send/2 auto repair circuit" do
    for _ <- 1..3 do
      TripSwitch.send(@circuit, fn -> {:break, 90} end)
    end

    assert %Circuit{state: :open} = TripSwitch.get(@circuit)
    Process.sleep(100)
    assert %Circuit{state: :half_open} = TripSwitch.get(@circuit)
    assert {:ok, :good} = TripSwitch.send(@circuit, fn -> {:ok, :good} end)
    assert_received {[@event_prefix, :repair, :done], _ref, _mesurement, %{id: @circuit}}
  end

  test "send/2 auto repaired circuit goes back to half_open" do
    for _ <- 1..3 do
      TripSwitch.send(@circuit, fn -> {:break, 90} end)
    end

    Process.sleep(100)

    assert :broken = TripSwitch.send(@circuit, fn -> {:break, :unwell} end)
    assert %Circuit{state: :open} = TripSwitch.get(@circuit)
  end

  test "reset/1" do
    try do
      assert :ok = TripSwitch.reset(@circuit)
      TripSwitch.reset(:unknown)
    catch
      :exit, {reason, _} -> send(self(), {:unknown_circuit_failed, reason})
    after
      assert_received {:unknown_circuit_failed, :noproc}
    end
  end
end
