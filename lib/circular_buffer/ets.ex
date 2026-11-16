# SPDX-FileCopyrightText: 2026 Frank Hunleth
#
# SPDX-License-Identifier: MIT
#
defmodule CircularBuffer.ETS do
  @moduledoc """
  An experimental, mutable circular buffer backed by a private ETS set.

  Inserts overwrite fixed slots. The write position lives in the table, so
  every handle to a buffer observes the same current contents. Unlike
  `CircularBuffer`, this module does not preserve older buffer versions.

  Use the buffer in the process that created it. Call `delete/1` when finished;
  ETS also deletes the table automatically when its owner exits. Each table
  contains at most `max_size + 1` entries, including the write-position entry.

      iex> cb = CircularBuffer.ETS.new([1, 2], 2)
      iex> CircularBuffer.ETS.insert(cb, 3)
      iex> CircularBuffer.ETS.to_list(cb)
      [2, 3]
      iex> CircularBuffer.ETS.delete(cb)
      true
  """

  alias __MODULE__, as: CB

  defstruct [:table, :max_size]

  @opaque t() :: %__MODULE__{
            table: :ets.tid(),
            max_size: non_neg_integer()
          }

  @doc "Creates an empty buffer owned by the calling process."
  @spec new(non_neg_integer()) :: t()
  def new(size) when is_integer(size) and size >= 0 do
    table = :ets.new(__MODULE__, [:set, :private])
    :ets.insert(table, {:position, -1})
    %CB{table: table, max_size: size}
  end

  @doc "Creates a buffer from an enumerable, retaining its newest elements."
  @spec new(Enumerable.t(), non_neg_integer()) :: t()
  def new(enumerable, size) when is_integer(size) and size >= 0 do
    cb = new(size)

    try do
      Enum.reduce(enumerable, cb, &insert(&2, &1))
    catch
      kind, reason ->
        delete(cb)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @doc "Overwrites the next slot and returns the same mutable buffer handle."
  @spec insert(t(), term()) :: t()
  def insert(%CB{max_size: 0} = cb, _item), do: cb

  def insert(%CB{table: table, max_size: size} = cb, item) do
    slot = :ets.update_counter(table, :position, {2, 1, size - 1, 0})
    :ets.insert(table, {slot, item})
    cb
  end

  @doc """
  Returns a snapshot ordered from oldest to newest.

  Copies the table entries and sorts them by slot, taking O(n log n) time.
  """
  @spec to_list(t()) :: list()
  def to_list(%CB{table: table}) do
    {{:position, position}, slots} = List.keytake(:ets.tab2list(table), :position, 0)
    {before, remaining} = Enum.split(:lists.keysort(1, slots), position + 1)
    Enum.map(remaining ++ before, fn {_slot, item} -> item end)
  end

  @doc "Returns the current number of stored elements."
  @spec count(t()) :: non_neg_integer()
  def count(%CB{table: table}) do
    case :ets.info(table, :size) do
      size when is_integer(size) -> size - 1
      :undefined -> raise ArgumentError, "buffer table has been deleted"
    end
  end

  @doc "Returns the oldest element, or nil if the buffer is empty."
  @spec oldest(t()) :: term()
  def oldest(%CB{table: table, max_size: size} = cb) do
    case count(cb) do
      0 ->
        nil

      count when count < size ->
        :ets.lookup_element(table, 0, 2)

      _count ->
        position = :ets.lookup_element(table, :position, 2)
        :ets.lookup_element(table, rem(position + 1, size), 2)
    end
  end

  @doc "Returns the newest element, or nil if the buffer is empty."
  @spec newest(t()) :: term()
  def newest(%CB{table: table}) do
    case :ets.lookup_element(table, :position, 2) do
      -1 -> nil
      position -> :ets.lookup_element(table, position, 2)
    end
  end

  @doc "Checks whether the buffer is empty."
  @spec empty?(t()) :: boolean()
  def empty?(%CB{} = cb), do: count(cb) == 0

  @doc "Returns the buffer capacity."
  @spec max_size(t()) :: non_neg_integer()
  def max_size(%CB{max_size: size}), do: size

  @doc "Deletes the ETS table, invalidating all handles to this buffer."
  @spec delete(t()) :: true
  def delete(%CB{table: table}), do: :ets.delete(table)

  defimpl Enumerable do
    def count(cb), do: {:ok, CB.count(cb)}
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
        "#CircularBuffer.ETS<capacity: ",
        to_doc(CB.max_size(cb), opts),
        ", contents: ",
        to_doc(CB.to_list(cb), opts),
        ">"
      ])
    end
  end
end
