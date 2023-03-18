defmodule TripSwitch.Test do
  @moduledoc """
  This is an helper to help reset trip switches after every tests.

  ## Examples
  ```elixir
  defmodule SomeTest do
    use ExUnit.Case
    use TripSwitch.Test

    ...
  end
  ```
  """

  defmacro __using__(_opts) do
    quote do
      setup do
        on_exit(fn ->
          switches = Registry.select(TripSwitch.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}])

          for switch <- switches do
            :ok = TripSwitch.reset(switch)
          end
        end)
      end
    end
  end
end
