defmodule CircularBufferTest do
  use ExUnit.Case, async: false
  use PropCheck
  doctest CircularBuffer

  alias CircularBuffer, as: CB

  property "new/1 accepts a max size" do
    forall i <- integer() do
      try do
        buffer = CB.new(i)
        buffer.max_size == i
      rescue
        FunctionClauseError ->
          i <= 0

        _ ->
          false
      end
    end
  end

  def slow_cb_count(cb) do
    Enum.count(cb.a) + Enum.count(cb.b)
  end

  property "the count matches the number of elements in the buffer" do
    forall {size, is} <- {pos_integer(), list(integer())} do
      buffer = Enum.reduce(is, CB.new(size), fn i, cb -> CB.insert(cb, i) end)
      slow_cb_count(buffer) == buffer.count
    end
  end

  property "can tell the current number of elements" do
    forall {size, is} <- {pos_integer(), list(integer())} do
      buffer = Enum.reduce(is, CB.new(size), fn i, cb -> CB.insert(cb, i) end)
      Enum.count(buffer) == min(size, length(is))
    end
  end

  property "member?/1" do
    items = such_that({a, b} <- {pos_integer(), pos_integer()}, when: a != b)

    forall {a, b} <- items do
      cb = CB.new(1) |> CB.insert(a)
      !Enum.member?(cb, b) && Enum.member?(cb, a)
    end
  end

  property "implements Enumerable" do
    forall is <- list(integer()) do
      buffer = Enum.reduce(is, CB.new(length(is) + 1), fn i, cb -> CB.insert(cb, i) end)

      Enum.reduce(buffer, 0, fn acc, i -> acc + i end) == Enum.sum(is)
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

      oldest =
        iis
        |> Enum.reverse()
        |> Enum.drop(size - 1)
        |> Enum.at(0)

      CB.oldest(buffer) == oldest
    end
  end

  test "can be inspected" do
    str = inspect(Enum.into([1, 2, 3, 4], CB.new(4)))
    assert str == "#CircularBuffer<[1, 2, 3, 4]>"
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
    assert Enum.slice(cb, -6, 5) == []
    assert Enum.slice(cb, -2, 5) == [4, 5]
    assert Enum.slice(cb, -3, 1) == [3]

    assert_raise FunctionClauseError, fn ->
      Enum.slice(cb, 0, -1)
    end

    assert_raise FunctionClauseError, fn ->
      Enum.slice(cb, 0.99, 0)
    end

    assert_raise FunctionClauseError, fn ->
      Enum.slice(cb, 0, 0.99)
    end
  end

  def size_and_list do
    let size <- pos_integer() do
      let is <- ints(size * 2 + 1, []) do
        {size, is}
      end
    end
  end

  defp ints(0, acc), do: acc

  defp ints(size, acc) do
    let i <- integer() do
      ints(size - 1, [i | acc])
    end
  end
end
