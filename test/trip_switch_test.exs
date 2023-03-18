defmodule TripSwitchTest do
  @moduledoc false
  use ExUnit.Case
  use TripSwitch.Test

  @switch :home
  @event_prefix :trip_switch
  @events [
    [@event_prefix, :repair, :start],
    [@event_prefix, :repair, :stop],
    [@event_prefix, :signal, :start],
    [@event_prefix, :signal, :stop]
  ]

  setup_all do
    start_supervised!({TripSwitch, name: @switch, threshold: 0.9, repair_time: 100})
    :ok
  end

  setup do
    :telemetry_test.attach_event_handlers(self(), @events)
    :ok
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

  test "send/2" do
    assert {:ok, 9} = TripSwitch.send(@switch, fn -> {:ok, 9} end)
    assert {:ok, 90} = TripSwitch.send(@switch, fn -> {:break, 90} end)

    assert_received {[@event_prefix, :signal, :start], _ref, _measurements,
                     %{id: @switch, tag: tag}}

    assert_received {[@event_prefix, :signal, :stop], _ref, %{duration: _},
                     %{id: @switch, tag: ^tag}}
  end

  test "send/2 breaks switch after failure threshold is reached" do
    for _ <- 1..3 do
      TripSwitch.send(@switch, fn -> {:break, 90} end)
    end

    assert :broken = TripSwitch.send(@switch, fn -> {:ok, 1} end)
  end

  test "send/2 auto repair switch" do
    :ok = destroy(@switch)

    assert TripSwitch.broken?(@switch)
    Process.sleep(100)
    assert {:ok, :good} = TripSwitch.send(@switch, fn -> {:ok, :good} end)

    assert_received {[@event_prefix, :repair, :start], _ref, _mesurement,
                     %{id: @switch, tag: tag}}

    assert_received {[@event_prefix, :repair, :stop], _ref, %{duration: _},
                     %{id: @switch, tag: ^tag}}
  end

  test "send/2 auto repaired switch goes back to half_open" do
    :ok = destroy(@switch)

    Process.sleep(100)

    assert :broken = TripSwitch.send(@switch, fn -> {:break, :unwell} end)
    assert TripSwitch.broken?(@switch)
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
