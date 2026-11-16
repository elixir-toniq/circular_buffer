# SPDX-FileCopyrightText: 2026 Frank Hunleth
#
# SPDX-License-Identifier: MIT
#
defmodule CircularBuffer.ETSTest do
  use ExUnit.Case, async: false
  use PropCheck, default_opts: [:quiet, {:numtests, 10_000}]
  doctest CircularBuffer.ETS

  alias CircularBuffer.ETS, as: CB

  property "FIFO contents, peeks and counts stay correct after every insert" do
    forall {size, items} <- {non_neg_integer(), list(integer())} do
      cb = CB.new(size)

      try do
        {_contents, valid} =
          Enum.reduce(items, {[], true}, fn item, {contents, valid} ->
            CB.insert(cb, item)
            contents = if size == 0, do: [], else: Enum.take(contents ++ [item], -size)

            valid =
              valid and CB.to_list(cb) == contents and
                CB.count(cb) == length(contents) and
                Enum.count(cb) == length(contents) and
                CB.empty?(cb) == (contents == []) and
                CB.oldest(cb) == List.first(contents) and
                CB.newest(cb) == List.last(contents) and
                :ets.info(cb.table, :size) == length(contents) + 1

            {contents, valid}
          end)

        valid
      after
        CB.delete(cb)
      end
    end
  end

  property "construction, collection and enumeration retain the newest elements" do
    forall {size, items} <- {non_neg_integer(), list(integer())} do
      constructed = CB.new(items, size)
      collected = CB.new(size)

      try do
        result = Enum.into(items, collected)
        expected = if size == 0, do: [], else: Enum.take(items, -size)

        result == collected and CB.to_list(constructed) == expected and
          Enum.to_list(collected) == expected and
          Enum.reduce(collected, 0, &+/2) == Enum.sum(expected) and
          Enum.all?(expected, &Enum.member?(collected, &1)) and
          not Enum.member?(collected, :never_inserted)
      after
        CB.delete(constructed)
        CB.delete(collected)
      end
    end
  end

  test "negative and non-integer capacities are rejected before allocating a table" do
    tables = owned_tables()

    for size <- [-1, 1.5, :invalid] do
      assert_raise FunctionClauseError, fn -> CB.new(size) end
      assert_raise FunctionClauseError, fn -> CB.new([], size) end
    end

    assert owned_tables() == tables
  end

  test "zero capacity stays empty without changing the write position" do
    cb = CB.new(0)

    try do
      Enum.into([1, nil, :position], cb)
      assert CB.to_list(cb) == []
      assert CB.count(cb) == 0
      assert CB.empty?(cb)
      assert CB.oldest(cb) == nil
      assert CB.newest(cb) == nil
      assert :ets.tab2list(cb.table) == [{:position, -1}]
    after
      CB.delete(cb)
    end
  end

  test "nil, duplicate values and metadata-like values are ordinary elements" do
    cb = CB.new([nil, :position, {:position, 9}, 0, nil], 4)

    try do
      assert CB.to_list(cb) == [:position, {:position, 9}, 0, nil]
      assert CB.oldest(cb) == :position
      assert CB.newest(cb) == nil
      assert Enum.member?(cb, nil)
      assert Enum.member?(cb, {:position, 9})
      CB.insert(cb, nil)
      assert CB.to_list(cb) == [{:position, 9}, 0, nil, nil]
    after
      CB.delete(cb)
    end
  end

  test "old handles observe current contents through repeated wraps" do
    cb = CB.new(3)
    original = cb

    try do
      for item <- 1..100 do
        assert CB.insert(cb, item) == original
        assert CB.to_list(original) == Enum.to_list(max(1, item - 2)..item)
        assert CB.count(original) == min(3, item)
        assert :ets.lookup_element(cb.table, :position, 2) in 0..2
      end
    after
      CB.delete(cb)
    end
  end

  test "enumeration supports slicing, early termination and suspension" do
    cb = CB.new(1..12, 5)

    try do
      assert Enum.slice(cb, 1, 3) == [9, 10, 11]
      assert Enum.slice(cb, -2, 5) == [11, 12]
      assert Enum.take(cb, 2) == [8, 9]
      assert Enum.zip(cb, [:a, :b]) == [{8, :a}, {9, :b}]
      refute Enum.member?(cb, 7)
      assert CB.to_list(cb) == [8, 9, 10, 11, 12]

      assert_raise FunctionClauseError, fn ->
        Enum.slice(cb, 0, -1)
      end
    after
      CB.delete(cb)
    end
  end

  test "inspection is a snapshot and does not allocate another table" do
    cb = CB.new([1, 2, 3], 2)
    tables = owned_tables()

    try do
      assert inspect(cb) == "#CircularBuffer.ETS<capacity: 2, contents: [2, 3]>"
      CB.insert(cb, 4)
      assert inspect(cb) == "#CircularBuffer.ETS<capacity: 2, contents: [3, 4]>"
      assert owned_tables() == tables
    after
      CB.delete(cb)
    end
  end

  test "buffers are independent and delete invalidates their table" do
    first = CB.new([1], 2)
    second = CB.new([2], 2)

    try do
      CB.insert(first, 3)
      assert CB.to_list(first) == [1, 3]
      assert CB.to_list(second) == [2]
      assert CB.delete(first)
      assert :ets.info(first.table) == :undefined
      assert_raise ArgumentError, fn -> CB.to_list(first) end
      assert_raise ArgumentError, fn -> CB.count(first) end
    after
      CB.delete(second)
    end
  end

  test "only the owner can read or write private table entries" do
    cb = CB.new([1], 2)

    try do
      task =
        Task.async(fn ->
          assert_raise ArgumentError, fn -> CB.insert(cb, 2) end
          assert_raise ArgumentError, fn -> CB.to_list(cb) end
        end)

      Task.await(task)
      assert CB.to_list(cb) == [1]
    after
      CB.delete(cb)
    end
  end

  test "the table is automatically deleted when its owner exits" do
    parent = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        send(parent, {:buffer, CB.new([1, 2], 2)})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:buffer, cb}
    assert :ets.info(cb.table, :owner) == pid
    send(pid, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}
    assert :ets.info(cb.table) == :undefined
  end

  test "a failed constructor cleans up its table and preserves the failure" do
    tables = owned_tables()
    raises = Stream.map([1, 2], fn _ -> raise "enumeration failed" end)
    throws = Stream.map([1, 2], fn _ -> throw(:enumeration_failed) end)

    assert_raise RuntimeError, "enumeration failed", fn -> CB.new(raises, 2) end
    assert catch_throw(CB.new(throws, 2)) == :enumeration_failed
    assert owned_tables() == tables
  end

  defp owned_tables do
    :ets.all()
    |> Enum.filter(&(:ets.info(&1, :owner) == self()))
    |> MapSet.new()
  end
end
