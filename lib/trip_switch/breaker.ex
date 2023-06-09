defmodule TripSwitch.Breaker do
  @moduledoc """
  This is the underlying model which the trip switch uses. A breaker
  keeps track of number of currents it received and also the count
  of surges it got from the currents it has handled. A breaker
  has three states, `closed`, `open` and `half_open`. The
  closed state is considered the working state while the
  remaining states are broken states.

  The only time a breaker enters the `half_open` state is when it just
  got repaired after it got broken from a bad current it handled. The
  breaker is then transitioned into the `closed` state (if the next
  current is a good one) or `open` state (if the next current is bad).
  """

  defstruct [:surges, :counter, :state, :threshold, :repair_time]

  @type state :: :closed | :half_open | :open
  @type current :: {:error | :ok, term()}

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

  @doc "Check if the breaker is broken."
  @spec broken?(t()) :: boolean()
  def broken?(%__MODULE__{state: :open}), do: true
  def broken?(%__MODULE__{}), do: false

  @doc """
  Confirm if breaker is repairable.

  A breaker is only repairable if it `repair_time` is greater than 0.
  """
  @spec repairable?(t()) :: boolean()
  def repairable?(%__MODULE__{repair_time: t} = breaker), do: broken?(breaker) and t > 0

  @doc """
  Handle the given current and transition the breaker state if needed.
  """
  @spec handle(t(), current()) :: {current(), t()}
  def handle(%__MODULE__{state: :half_open} = breaker, current) do
    case current do
      {:ok, _value} = return -> {return, increase_counter(reset(breaker))}
      {:error, _reason} = return -> {return, struct!(breaker, state: :open)}
    end
  end

  def handle(%__MODULE__{state: :closed} = breaker, current) do
    case current do
      {:ok, _value} = return -> {return, increase_counter(breaker)}
      {:error, _reason} = return -> {return, surge(increase_counter(breaker))}
    end
  end

  @doc "Repair the breaker."
  @spec repair(t()) :: t()
  def repair(%__MODULE__{} = breaker) do
    case repairable?(breaker) do
      false -> breaker
      true -> struct!(breaker, state: :half_open, counter: 0, surges: 0)
    end
  end

  @doc "Reset breaker into its initial working state."
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
