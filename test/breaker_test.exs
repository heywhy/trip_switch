defmodule TripSwitch.BreakerTest do
  @moduledoc false
  use ExUnit.Case

  alias TripSwitch.Breaker

  setup do
    {:ok, breaker: Breaker.new(threshold: 1, repair_time: 1_000)}
  end

  test "broken breaker with heal time repaired", %{breaker: breaker} do
    assert Breaker.repair(breaker) == breaker
    assert {{:error, :unwell}, breaker} = Breaker.handle(breaker, {:error, :unwell})
    refute Breaker.repair(breaker) == breaker
  end

  test "broken breaker with no heal time not repaired", %{breaker: breaker} do
    {_result, breaker} = destroy(%{breaker | repair_time: 0})

    assert Breaker.repair(breaker) == breaker
  end

  test "increment counter on good current", %{breaker: breaker} do
    assert {{:ok, :good}, breaker} = Breaker.handle(breaker, {:ok, :good})
    assert %Breaker{counter: 1, state: :closed, surges: 0} = breaker
  end

  test "increment surges on bad current and open breaker", %{breaker: breaker} do
    assert {{:error, :bad}, breaker} = destroy(breaker)
    assert %Breaker{counter: 1, state: :open, surges: 1} = breaker
  end

  test "broken breaker can't handle any current", %{breaker: breaker} do
    {{:error, :bad}, breaker} = destroy(breaker)

    assert Breaker.broken?(breaker)
    assert_raise FunctionClauseError, fn -> Breaker.handle(breaker, {:ok, :good}) end
  end

  test "half open breaker healed successfully", %{breaker: breaker} do
    {_result, breaker} = destroy(breaker)
    breaker = Breaker.repair(breaker)

    assert %Breaker{state: :half_open} = breaker
    assert {_result, breaker} = Breaker.handle(breaker, {:ok, :good})
    assert %Breaker{state: :closed} = breaker
  end

  test "half open breaker gets opened completely", %{breaker: breaker} do
    {_result, breaker} = destroy(breaker)
    breaker = Breaker.repair(breaker)

    assert %Breaker{state: :half_open} = breaker
    assert {_result, breaker} = destroy(breaker)
    assert %Breaker{state: :open} = breaker
  end

  defp destroy(breaker), do: Breaker.handle(breaker, {:error, :bad})
end
