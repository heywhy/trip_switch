defmodule TripSwitch.Circuit do
  @moduledoc """
  Documentation for `TripSwitch.Circuit`.
  """

  defstruct [:surges, :counter, :state, :threshold, :fix_after]

  @type state :: :closed | :half_open | :open
  @type signal :: (() -> {:ok, term()} | {:break, term()})

  @type t :: %__MODULE__{
          state: state(),
          surges: pos_integer(),
          counter: pos_integer(),
          threshold: pos_integer(),
          fix_after: pos_integer()
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    attrs = %{
      surges: 0,
      counter: 0,
      state: :closed,
      fix_after: Keyword.get(opts, :fix_after, 0),
      threshold: Keyword.fetch!(opts, :threshold)
    }

    struct!(__MODULE__, attrs)
  end

  @spec handle(t(), signal()) :: {{:ok, term()} | :broken, t()}
  def handle(%__MODULE__{state: :open} = circuit, _signal), do: {:broken, circuit}

  def handle(%__MODULE__{state: :half_open} = circuit, signal) do
    case signal.() do
      {:ok, _value} = return -> {return, increase_counter(reset(circuit))}
      {:break, _result} -> {:broken, struct!(circuit, state: :open)}
    end
  end

  def handle(%__MODULE__{state: :closed} = circuit, signal) do
    case signal.() do
      {:ok, _value} = return -> {return, increase_counter(circuit)}
      {:break, result} -> {{:ok, result}, surge(increase_counter(circuit))}
    end
  end

  @spec repair(t()) :: t()
  def repair(%__MODULE__{state: :open} = circuit) do
    struct!(circuit, state: :half_open)
  end

  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = circuit) do
    struct!(circuit, state: :closed, counter: 0, surges: 0)
  end

  defp increase_counter(%{counter: counter} = circuit), do: %{circuit | counter: counter + 1}

  defp surge(%{surges: surges, counter: counter, threshold: threshold} = circuit) do
    surges = surges + 1
    t = surges / counter * 100 / 100

    case t >= threshold do
      true -> struct!(circuit, state: :open, surges: surges)
      false -> struct!(circuit, surges: surges)
    end
  end
end
