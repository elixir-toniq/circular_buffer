# SPDX-FileCopyrightText: 2019 Chris Keathley
# SPDX-FileCopyrightText: 2020 Frank Hunleth
# SPDX-FileCopyrightText: 2022 Milton Mazzarri
#
# SPDX-License-Identifier: MIT
#
defmodule CircularBuffer.HoodMelvilleTest do
  use ExUnit.Case, async: false
  use PropCheck, default_opts: [:quiet, {:numtests, 10_000}]
  doctest CircularBuffer.HoodMelville

  alias CircularBuffer.HoodMelville, as: CB

  property "new/1 returns an empty buffer for non-negative sizes" do
    forall size <- non_neg_integer() do
      cb = CB.new(size)

      cb.max_size == size and
        cb.count == 0 and
        cb.front == [] and
        cb.front_len == 0 and
        cb.rear == [] and
        cb.rear_len == 0 and
        cb.rotation == :idle and
        CB.empty?(cb)
    end
  end

  property "new/1 raises for negative sizes" do
    forall n <- neg_integer() do
      try do
        CB.new(n)
        false
      rescue
        FunctionClauseError -> true
      end
    end
  end

  property "new/2 retains the newest elements of an enumerable" do
    forall {size, is} <- {non_neg_integer(), list(integer())} do
      buffer = CB.new(is, size)
      kept = if size == 0, do: [], else: Enum.take(is, -size)

      CB.max_size(buffer) == size and CB.to_list(buffer) == kept
    end
  end

  def slow_cb_count(cb) do
    cb |> CB.to_list() |> length()
  end

  property "the count matches the number of elements in the buffer" do
    forall {size, is} <- {non_neg_integer(), list(integer())} do
      buffer = Enum.reduce(is, CB.new(size), fn i, cb -> CB.insert(cb, i) end)
      slow_cb_count(buffer) == buffer.count
    end
  end

  property "can tell the current number of elements" do
    forall {size, is} <- {non_neg_integer(), list(integer())} do
      buffer = Enum.reduce(is, CB.new(size), fn i, cb -> CB.insert(cb, i) end)
      Enum.count(buffer) == min(size, length(is))
    end
  end

  property "member?/2 reflects buffer contents" do
    forall {size, is} <- size_and_list() do
      iis = Enum.with_index(is)
      buffer = Enum.reduce(iis, CB.new(size), fn i, cb -> CB.insert(cb, i) end)

      kept = Enum.take(iis, -size)
      evicted = Enum.drop(iis, -size)

      Enum.all?(kept, &Enum.member?(buffer, &1)) and
        Enum.all?(evicted, fn x -> not Enum.member?(buffer, x) end) and
        not Enum.member?(buffer, :never_inserted)
    end
  end

  property "implements Enumerable" do
    forall {size, is} <- size_and_list() do
      buffer = Enum.reduce(is, CB.new(size), fn i, cb -> CB.insert(cb, i) end)

      Enum.reduce(buffer, 0, fn elem, acc -> acc + elem end) ==
        Enum.sum(Enum.take(is, -size))
    end
  end

  property "can be collected" do
    forall {size, is} <- size_and_list() do
      buffer = Enum.reduce(is, CB.new(size), fn i, cb -> CB.insert(cb, i) end)

      Enum.into(is, CB.new(size)) == buffer
    end
  end

  property "the number of elements never exceeds the size of the buffer" do
    forall {size, is} <- size_and_list() do
      buffer = Enum.reduce(is, CB.new(size), fn i, cb -> CB.insert(cb, i) end)
      slow_cb_count(buffer) <= size
    end
  end

  property "the 'oldest' elements are dropped from the buffer" do
    forall {size, is} <- size_and_list() do
      iis = Enum.with_index(is)

      buffer =
        iis
        |> Enum.reduce(CB.new(size), fn i, cb -> CB.insert(cb, i) end)

      slice =
        iis
        |> Enum.take(-size)

      CB.to_list(buffer) == slice
    end
  end

  property "newest/1 returns the newest element in the buffer" do
    forall {size, is} <- size_and_list() do
      iis = Enum.with_index(is)

      buffer = Enum.reduce(iis, CB.new(size), fn i, cb -> CB.insert(cb, i) end)

      CB.newest(buffer) == Enum.at(Enum.reverse(iis), 0)
    end
  end

  property "oldest/1 returns the oldest element in the buffer" do
    forall {size, is} <- size_and_list() do
      iis = Enum.with_index(is)

      buffer = Enum.reduce(iis, CB.new(size), fn i, cb -> CB.insert(cb, i) end)

      oldest = iis |> Enum.take(-size) |> List.first()

      CB.oldest(buffer) == oldest
    end
  end

  property "inspect matches contents" do
    forall {size, is} <- size_and_list() do
      buffer = Enum.reduce(is, CB.new(size), fn i, cb -> CB.insert(cb, i) end)
      {inspected, _} = Code.eval_string(inspect(buffer, limit: :infinity))

      buffer.max_size == inspected.max_size and CB.to_list(inspected) == CB.to_list(buffer)
    end
  end

  test "inspecting zero-length buffer" do
    str = inspect(CB.new(0))
    assert str == "CircularBuffer.HoodMelville.new([], 0)"
  end

  test "max_size matches created size" do
    cb = CB.new(15)
    assert CB.max_size(cb) == 15
  end

  test "inserting into a zero-length buffer keeps it empty" do
    cb = Enum.into([1, nil, :item], CB.new(0))

    assert CB.empty?(cb)
    assert CB.to_list(cb) == []
    assert Enum.empty?(cb)
    assert CB.oldest(cb) == nil
    assert CB.newest(cb) == nil
    refute Enum.member?(cb, nil)
  end

  test "contents remain correct at every insertion across repeated rotations" do
    for size <- 1..32 do
      Enum.reduce(1..200, {CB.new(size), []}, fn item, {cb, contents} ->
        cb = CB.insert(cb, item)
        contents = Enum.take(contents ++ [item], -size)

        assert CB.to_list(cb) == contents
        assert Enum.to_list(cb) == contents
        assert cb.count == length(contents)
        assert CB.oldest(cb) == List.first(contents)
        assert CB.newest(cb) == List.last(contents)
        refute CB.empty?(cb)

        {cb, contents}
      end)
    end
  end

  test "Enum.slice" do
    # Verify Elixir's Enum.slice tests for lists work
    cb = Enum.into([-2, -1, 0, 1, 2, 3, 4, 5], CB.new(5))
    assert Enum.slice(cb, 0..0) == [1]
    assert Enum.slice(cb, 0..1) == [1, 2]
    assert Enum.slice(cb, 0..2) == [1, 2, 3]
    assert Enum.slice(cb, 1, 2) == [2, 3]
    assert Enum.slice(cb, 1, 0) == []
    assert Enum.slice(cb, 2, 5) == [3, 4, 5]
    assert Enum.slice(cb, 2, 6) == [3, 4, 5]
    assert Enum.slice(cb, 5, 5) == []
    assert Enum.slice(cb, 6, 5) == []
    assert Enum.slice(cb, 6, 0) == []
    assert Enum.slice(cb, -6, 0) == []
    assert Enum.slice(cb, -6, 5) == [1, 2, 3, 4, 5]
    assert Enum.slice(cb, -2, 5) == [4, 5]
    assert Enum.slice(cb, -3, 1) == [3]

    assert_raise FunctionClauseError, fn ->
      Enum.slice(cb, 0, -1)
    end
  end

  def size_and_list do
    let size <- pos_integer() do
      let n <- range(0, size * 2 + 1) do
        let is <- vector(n, integer()) do
          {size, is}
        end
      end
    end
  end
end
