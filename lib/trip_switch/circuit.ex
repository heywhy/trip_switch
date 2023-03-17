defmodule TripSwitch.Circuit do
  @moduledoc """
  Documentation for `TripSwitch.Circuit`.
  """

  defstruct [:surges, :state, :capacity, :fix_after]

  @type state :: :closed | :half_open | :open
  @type signal :: (() -> {:ok, term()} | {:break, term()})

  @type t :: %__MODULE__{
          state: state(),
          surges: pos_integer(),
          capacity: pos_integer(),
          fix_after: pos_integer()
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    attrs = %{
      surges: 0,
      state: :closed,
      capacity: Keyword.fetch!(opts, :capacity),
      fix_after: Keyword.get(opts, :fix_after, 0)
    }

    struct!(__MODULE__, attrs)
  end

  @spec working?(t()) :: boolean
  def working?(%__MODULE__{state: state}), do: state in [:closed, :half_open]

  @spec handle(t(), signal()) :: {{:ok, term()} | :broken, t()}
  def handle(%__MODULE__{} = circuit, signal) do
    with true <- working?(circuit),
         {:ok, _value} = return <- signal.() do
      {return, circuit}
    else
      false -> {:broken, circuit}
      {:break, result} -> {{:ok, result}, surge(circuit)}
    end
  end

  @spec repair(t()) :: t()
  def repair(%__MODULE__{} = circuit) do
    struct!(circuit, state: :half_open)
  end

  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = circuit) do
    struct!(circuit, state: :closed, surges: 0)
  end

  defp surge(%{surges: surges, capacity: capacity} = circuit) do
    case surges + 1 do
      ^capacity -> struct!(circuit, state: :open, surges: capacity)
      surges -> struct!(circuit, surges: surges)
    end
  end
end
