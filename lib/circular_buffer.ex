# SPDX-FileCopyrightText: 2019 Chris Keathley
# SPDX-FileCopyrightText: 2020 Frank Hunleth
# SPDX-FileCopyrightText: 2022 Milton Mazzarri
#
# SPDX-License-Identifier: MIT
#
defmodule CircularBuffer do
  @moduledoc """
  Circular Buffer

  When creating a circular buffer you must specify the max size:

  ```
  cb = CircularBuffer.new(10)
  ```

  CircularBuffers are implemented as Okasaki queues like Erlang's `:queue`
  module, but with additional optimizations thanks to the reduced set
  of operations.

  CircularBuffer implements both the
  [`Enumerable`](https://elixir.hexdocs.pm/Enumerable.html) and
  [`Collectable`](https://elixir.hexdocs.pm/Collectable.html) protocols, so code
  like the following works:

      iex> cb = Enum.into([1, 2, 3, 4], CircularBuffer.new(3))
      iex> Enum.map(cb, fn x -> x * 2 end)
      [4, 6, 8]
  """

  defstruct [:a, :b, :max_size, :count]
  @typedoc "A circular buffer"
  @opaque t() :: %__MODULE__{
            a: list(),
            b: list(),
            max_size: non_neg_integer(),
            count: non_neg_integer()
          }

  alias __MODULE__, as: CB

  @doc """
  Creates a new circular buffer with a given size.
  """
  @spec new(non_neg_integer()) :: t()
  def new(size) when is_integer(size) and size >= 0 do
    %CB{a: [], b: [], max_size: size, count: 0}
  end

  @doc """
  Creates a new circular buffer with a given size and contents
  """
  @spec new(Enumerable.t(), non_neg_integer()) :: t()
  def new(enumerable, size) when is_integer(size) and size >= 0 do
    Enum.reduce(enumerable, new(size), &insert(&2, &1))
  end

  @doc """
  Inserts a new item into the next location of the circular buffer
  """
  @spec insert(t(), any()) :: t()
  def insert(%CB{a: a, b: [_ | tl_b]} = cb, item) do
    %{cb | a: [item | a], b: tl_b}
  end

  def insert(%CB{count: count, max_size: max_size} = cb, item) when count < max_size do
    %{cb | a: [item | cb.a], count: cb.count + 1}
  end

  def insert(%CB{a: a, b: []} = cb, item) when a != [] do
    new_b = a |> Enum.reverse() |> tl()
    %{cb | a: [item], b: new_b}
  end

  # max_size==0 case
  def insert(cb, _item), do: cb

  @doc """
  Converts a circular buffer to a list. The list is ordered from oldest to newest
  elements based on their insertion order.
  """
  @spec to_list(t()) :: list()
  def to_list(%CB{} = cb) do
    cb.b ++ Enum.reverse(cb.a)
  end

  @doc """
  Returns the newest element in the buffer

  ## Examples

      iex> cb = CircularBuffer.new(3)
      iex> CircularBuffer.newest(cb)
      nil
      iex> cb = Enum.reduce(1..4, cb, fn n, cb -> CircularBuffer.insert(cb, n) end)
      iex> CircularBuffer.newest(cb)
      4

  """
  @spec newest(t()) :: any()
  def newest(%CB{a: [newest | _rest]}), do: newest
  def newest(%CB{b: []}), do: nil

  @doc """
  Returns the oldest element in the buffer
  """
  @spec oldest(t()) :: any()
  def oldest(%CB{b: [oldest | _rest]}), do: oldest
  def oldest(%CB{a: a}), do: List.last(a)

  @doc """
  Checks the buffer to see if its empty

  Returns `true` if the given circular buffer is empty, otherwise `false`.

  ## Examples

      iex> cb = CircularBuffer.new(1)
      iex> CircularBuffer.empty?(cb)
      true
      iex> cb |> CircularBuffer.insert(1) |> CircularBuffer.empty?()
      false

  """
  @spec empty?(t()) :: boolean()
  def empty?(%CB{} = cb) do
    cb.count == 0
  end

  @doc """
  Return the max size of the buffer
  """
  @spec max_size(t()) :: non_neg_integer()
  def max_size(%CB{max_size: max_size}), do: max_size

  defimpl Enumerable do
    def count(cb) do
      {:ok, cb.count}
    end

    def member?(cb, element) do
      {:ok, Enum.member?(cb.a, element) or Enum.member?(cb.b, element)}
    end

    def reduce(cb, acc, fun) do
      do_reduce(cb.b, Enum.reverse(cb.a), acc, fun)
    end

    defp do_reduce(_b, _a, {:halt, acc}, _fun), do: {:halted, acc}
    defp do_reduce(b, a, {:suspend, acc}, fun), do: {:suspended, acc, &do_reduce(b, a, &1, fun)}
    defp do_reduce([], [], {:cont, acc}, _fun), do: {:done, acc}
    defp do_reduce([], [h | t], {:cont, acc}, fun), do: do_reduce([], t, fun.(h, acc), fun)
    defp do_reduce([h | t], a, {:cont, acc}, fun), do: do_reduce(t, a, fun.(h, acc), fun)

    def slice(_cb) do
      {:error, __MODULE__}
    end
  end

  defimpl Collectable do
    def into(original) do
      collector_fn = fn
        cb, {:cont, elem} -> CB.insert(cb, elem)
        cb, :done -> cb
        _cb, :halt -> :ok
      end

      {original, collector_fn}
    end
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(cb, opts) do
      concat([
        "CircularBuffer.new(",
        to_doc(CB.to_list(cb), opts),
        ", ",
        to_doc(CB.max_size(cb), opts),
        ")"
      ])
    end
  end
end
