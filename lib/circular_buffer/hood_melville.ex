# SPDX-FileCopyrightText: 2019 Chris Keathley
# SPDX-FileCopyrightText: 2020 Frank Hunleth
# SPDX-FileCopyrightText: 2022 Milton Mazzarri
#
# SPDX-License-Identifier: MIT
#
# Public API adapted from elixir-toniq/circular_buffer.
defmodule CircularBuffer.HoodMelville do
  @moduledoc """
  A persistent circular buffer backed by a Hood–Melville queue.

  An insert into a full buffer removes the oldest element before enqueuing
  the new one. Each queue update performs at most two rotation steps.
  """

  alias __MODULE__, as: CB

  defstruct front: [],
            front_len: 0,
            rear: [],
            rear_len: 0,
            rotation: :idle,
            newest: nil,
            max_size: 0,
            count: 0

  @typep rotation ::
           :idle
           | {:reversing, non_neg_integer(), list(), list(), list(), list()}
           | {:appending, non_neg_integer(), list(), list()}
           | {:done, list()}

  @opaque t() :: %__MODULE__{
            front: list(),
            front_len: non_neg_integer(),
            rear: list(),
            rear_len: non_neg_integer(),
            rotation: rotation(),
            newest: term(),
            max_size: non_neg_integer(),
            count: non_neg_integer()
          }

  @doc "Creates an empty buffer of the given capacity."
  @spec new(non_neg_integer()) :: t()
  def new(size) when is_integer(size) and size >= 0, do: %CB{max_size: size}

  @doc "Creates a buffer from an enumerable and retains its newest elements."
  @spec new(Enumerable.t(), non_neg_integer()) :: t()
  def new(enumerable, size) when is_integer(size) and size >= 0 do
    Enum.reduce(enumerable, new(size), &insert(&2, &1))
  end

  @doc "Inserts an item, dropping the oldest item if the buffer is full."
  @spec insert(t(), term()) :: t()
  def insert(%CB{max_size: 0} = cb, _item), do: cb

  def insert(%CB{count: count, max_size: size} = cb, item) when count == size do
    cb |> dequeue() |> enqueue(item)
  end

  def insert(%CB{} = cb, item), do: enqueue(cb, item)

  defp dequeue(%CB{front: [_ | front]} = cb) do
    check(%CB{
      cb
      | front: front,
        front_len: cb.front_len - 1,
        rotation: invalidate(cb.rotation),
        count: cb.count - 1
    })
  end

  defp enqueue(cb, item) do
    check(%CB{
      cb
      | rear: [item | cb.rear],
        rear_len: cb.rear_len + 1,
        newest: item,
        count: cb.count + 1
    })
  end

  # front_len measures the logical front, including elements in rotation.
  # When rear first outgrows the front it has exactly one extra element.
  defp check(%CB{front_len: front_len, rear_len: rear_len} = cb)
       when rear_len > front_len do
    advance_twice(%CB{
      cb
      | front_len: front_len + rear_len,
        rear: [],
        rear_len: 0,
        rotation: {:reversing, 0, cb.front, [], cb.rear, []}
    })
  end

  defp check(cb), do: advance_twice(cb)

  defp advance_twice(cb) do
    case step(step(cb.rotation)) do
      {:done, front} -> %CB{cb | front: front, rotation: :idle}
      rotation -> %CB{cb | rotation: rotation}
    end
  end

  # Reverse the original front and rear together, one pair at a time.
  # valid counts copied front elements that are still part of the queue.
  defp step({:reversing, valid, [x | front], front_rev, [y | rear], rear_rev}) do
    {:reversing, valid + 1, front, [x | front_rev], rear, [y | rear_rev]}
  end

  defp step({:reversing, valid, [], front_rev, [y], rear_rev}) do
    {:appending, valid, front_rev, [y | rear_rev]}
  end

  # Prepend the surviving old front to the reversed rear.
  defp step({:appending, 0, _front_rev, new_front}), do: {:done, new_front}

  defp step({:appending, valid, [x | front_rev], new_front}) do
    {:appending, valid - 1, front_rev, [x | new_front]}
  end

  defp step(:idle), do: :idle
  defp step({:done, _front} = done), do: done

  defp invalidate({:reversing, valid, front, front_rev, rear, rear_rev}) do
    {:reversing, valid - 1, front, front_rev, rear, rear_rev}
  end

  # If all surviving front elements have already been prepended, the
  # element being evicted is now at the head of the new front.
  defp invalidate({:appending, 0, _front_rev, [_ | new_front]}) do
    {:done, new_front}
  end

  defp invalidate({:appending, valid, front_rev, new_front}) do
    {:appending, valid - 1, front_rev, new_front}
  end

  defp invalidate(:idle), do: :idle

  @doc "Returns the contents from oldest to newest."
  @spec to_list(t()) :: list()
  def to_list(%CB{} = cb), do: logical_front(cb) ++ Enum.reverse(cb.rear)

  defp logical_front(%CB{rotation: :idle, front: front}), do: front

  defp logical_front(%CB{rotation: {:reversing, valid, front, front_rev, rear, rear_rev}}) do
    Enum.reverse(Enum.take(front_rev, valid), front ++ Enum.reverse(rear, rear_rev))
  end

  defp logical_front(%CB{rotation: {:appending, valid, front_rev, new_front}}) do
    Enum.reverse(Enum.take(front_rev, valid), new_front)
  end

  @doc "Returns the newest element, or nil if the buffer is empty."
  @spec newest(t()) :: term()
  def newest(%CB{newest: item}), do: item

  @doc "Returns the oldest element, or nil if the buffer is empty."
  @spec oldest(t()) :: term()
  def oldest(%CB{front: [item | _]}), do: item
  def oldest(%CB{front: []}), do: nil

  @doc "Checks whether the buffer is empty."
  @spec empty?(t()) :: boolean()
  def empty?(%CB{count: count}), do: count == 0

  @doc "Returns the capacity of the buffer."
  @spec max_size(t()) :: non_neg_integer()
  def max_size(%CB{max_size: size}), do: size

  defimpl Enumerable do
    def count(cb), do: {:ok, cb.count}
    def member?(cb, item), do: {:ok, Enum.member?(CB.to_list(cb), item)}
    def reduce(cb, acc, fun), do: Enumerable.List.reduce(CB.to_list(cb), acc, fun)
    def slice(_cb), do: {:error, __MODULE__}
  end

  defimpl Collectable do
    def into(original) do
      collector = fn
        cb, {:cont, item} -> CB.insert(cb, item)
        cb, :done -> cb
        _cb, :halt -> :ok
      end

      {original, collector}
    end
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(cb, opts) do
      concat([
        "CircularBuffer.HoodMelville.new(",
        to_doc(CB.to_list(cb), opts),
        ", ",
        to_doc(CB.max_size(cb), opts),
        ")"
      ])
    end
  end
end
