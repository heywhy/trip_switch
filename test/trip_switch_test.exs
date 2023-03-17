defmodule TripSwitchTest do
  @moduledoc false
  use ExUnit.Case

  alias TripSwitch.Breaker

  @switch :home
  @event_prefix :trip_switch
  @events [
    [@event_prefix, :repair, :done],
    [@event_prefix, :signal, :start],
    [@event_prefix, :signal, :stop]
  ]

  setup_all do
    start_supervised!({TripSwitch, name: @switch, threshold: 0.9, fix_after: 100})
    :ok
  end

  setup do
    :telemetry_test.attach_event_handlers(self(), @events)

    on_exit(fn -> TripSwitch.reset(@switch) end)
  end

  test "child_spec/1" do
    assert %{id: {TripSwitch, :dummy}} = TripSwitch.child_spec(name: :dummy)

    assert_raise ArgumentError, "expected :name option to be present", fn ->
      TripSwitch.child_spec([])
    end
  end

  test "broken?/1" do
    refute TripSwitch.broken?(@switch)
    assert :ok = destroy(@switch)
    assert TripSwitch.broken?(@switch)
  end

  test "get/1" do
    assert %Breaker{state: :closed} = TripSwitch.get(@switch)
  end

  test "send/2" do
    assert {:ok, 9} = TripSwitch.send(@switch, fn -> {:ok, 9} end)
    assert {:ok, 90} = TripSwitch.send(@switch, fn -> {:break, 90} end)

    assert_received {[@event_prefix, :signal, :start], _ref, _measurements, %{id: @switch}}
    assert_received {[@event_prefix, :signal, :stop], _ref, _measurements, %{id: @switch}}
  end

  test "send/2 breaks switch after failure threshold is reached" do
    for _ <- 1..3 do
      TripSwitch.send(@switch, fn -> {:break, 90} end)
    end

    assert :broken = TripSwitch.send(@switch, fn -> {:ok, 1} end)
  end

  test "send/2 auto repair switch" do
    :ok = destroy(@switch)

    assert %Breaker{state: :open} = TripSwitch.get(@switch)
    Process.sleep(100)
    assert %Breaker{state: :half_open} = TripSwitch.get(@switch)
    assert {:ok, :good} = TripSwitch.send(@switch, fn -> {:ok, :good} end)
    assert_received {[@event_prefix, :repair, :done], _ref, _mesurement, %{id: @switch}}
  end

  test "send/2 auto repaired switch goes back to half_open" do
    :ok = destroy(@switch)

    Process.sleep(100)

    assert :broken = TripSwitch.send(@switch, fn -> {:break, :unwell} end)
    assert %Breaker{state: :open} = TripSwitch.get(@switch)
  end

  test "reset/1" do
    assert :ok = TripSwitch.reset(@switch)
  end

  defp destroy(switch) do
    for _ <- 1..3 do
      TripSwitch.send(switch, fn -> {:break, 90} end)
    end

    :ok
  end
end
