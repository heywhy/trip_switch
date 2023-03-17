defmodule TripSwitch.BreakerTest do
  @moduledoc false
  use ExUnit.Case

  alias TripSwitch.Breaker

  setup do
    {:ok, breaker: Breaker.new(threshold: 1, fix_after: 1_000)}
  end

  test "broken breaker with heal time repaired", %{breaker: breaker} do
    assert Breaker.repair(breaker) == breaker
    assert {{:ok, :melt}, breaker} = Breaker.handle(breaker, fn -> {:break, :melt} end)
    refute Breaker.repair(breaker) == breaker
  end

  test "broken breaker with no heal time not repaired", %{breaker: breaker} do
    {_result, breaker} = destroy(%{breaker | fix_after: 0})

    assert Breaker.repair(breaker) == breaker
  end

  test "increment counter on good signal", %{breaker: breaker} do
    assert {{:ok, :good}, breaker} = Breaker.handle(breaker, fn -> {:ok, :good} end)
    assert %Breaker{counter: 1, state: :closed, surges: 0} = breaker
  end

  test "increment surges on bad signal and open breaker", %{breaker: breaker} do
    assert {{:ok, :bad}, breaker} = destroy(breaker)
    assert %Breaker{counter: 1, state: :open, surges: 1} = breaker
  end

  test "broken breaker can't handle any signal", %{breaker: breaker} do
    {{:ok, :bad}, breaker} = destroy(breaker)

    assert {:broken, breaker} = Breaker.handle(breaker, fn -> {:ok, :good} end)
    assert %Breaker{counter: 1, state: :open, surges: 1} = breaker
  end

  test "half open breaker healed successfully", %{breaker: breaker} do
    {_result, breaker} = destroy(breaker)
    breaker = Breaker.repair(breaker)

    assert %Breaker{state: :half_open} = breaker
    assert {_result, breaker} = Breaker.handle(breaker, fn -> {:ok, :good} end)
    assert %Breaker{state: :closed} = breaker
  end

  test "half open breaker gets opened completely", %{breaker: breaker} do
    {_result, breaker} = destroy(breaker)
    breaker = Breaker.repair(breaker)

    assert %Breaker{state: :half_open} = breaker
    assert {_result, breaker} = destroy(breaker)
    assert %Breaker{state: :open} = breaker
  end

  defp destroy(breaker) do
    Breaker.handle(breaker, fn -> {:break, :bad} end)
  end
end
