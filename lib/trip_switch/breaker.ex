defmodule TripSwitch.Breaker do
  @moduledoc """
  Documentation for `TripSwitch.Breaker`.
  """

  defstruct [:surges, :counter, :state, :threshold, :repair_time]

  @type state :: :closed | :half_open | :open
  @type signal :: (() -> {:ok, term()} | {:break, term()})

  @type t :: %__MODULE__{
          state: state(),
          surges: pos_integer(),
          counter: pos_integer(),
          threshold: pos_integer(),
          repair_time: pos_integer()
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    attrs = %{
      surges: 0,
      counter: 0,
      state: :closed,
      threshold: Keyword.fetch!(opts, :threshold),
      repair_time: Keyword.get(opts, :repair_time, 0)
    }

    struct!(__MODULE__, attrs)
  end

  @spec broken?(t()) :: boolean()
  def broken?(%__MODULE__{state: :closed}), do: false
  def broken?(%__MODULE__{}), do: true

  @spec repairable?(t()) :: boolean()
  def repairable?(%__MODULE__{repair_time: t} = breaker), do: broken?(breaker) and t > 0

  @spec handle(t(), signal()) :: {{:ok, term()} | :broken, t()}
  def handle(%__MODULE__{state: :open} = breaker, _signal), do: {:broken, breaker}

  def handle(%__MODULE__{state: :half_open} = breaker, signal) do
    case signal.() do
      {:ok, _value} = return -> {return, increase_counter(reset(breaker))}
      {:break, _result} -> {:broken, struct!(breaker, state: :open)}
    end
  end

  def handle(%__MODULE__{state: :closed} = breaker, signal) do
    case signal.() do
      {:ok, _value} = return -> {return, increase_counter(breaker)}
      {:break, result} -> {{:ok, result}, surge(increase_counter(breaker))}
    end
  end

  @spec repair(t()) :: t()
  def repair(%__MODULE__{} = breaker) do
    case repairable?(breaker) do
      false -> breaker
      true -> struct!(breaker, state: :half_open, counter: 0, surges: 0)
    end
  end

  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = breaker) do
    struct!(breaker, state: :closed, counter: 0, surges: 0)
  end

  defp increase_counter(%{counter: counter} = breaker), do: %{breaker | counter: counter + 1}

  defp surge(%{surges: surges, counter: counter, threshold: threshold} = breaker) do
    surges = surges + 1
    t = surges / counter * 100 / 100

    case t >= threshold do
      true -> struct!(breaker, state: :open, surges: surges)
      false -> struct!(breaker, surges: surges)
    end
  end
end
