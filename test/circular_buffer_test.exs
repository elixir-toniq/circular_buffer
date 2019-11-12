defmodule CircularBufferTest do
  use ExUnit.Case, async: false
  use PropCheck

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

  property "the count matches the number of elements in the buffer" do
    forall {size, is} <- {pos_integer(), list(integer())} do
      buffer = Enum.reduce(is, CB.new(size), fn i, cb -> CB.insert(cb, i) end)
      :queue.len(buffer.q) == buffer.count
    end
  end

  property "the number of elements never exceeds the size of the buffer" do
    forall {size, is} <- size_and_list() do
      buffer = Enum.reduce(is, CB.new(size), fn i, cb -> CB.insert(cb, i) end)
      :queue.len(buffer.q) <= size
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
        |> Enum.reverse
        |> Enum.take(size)

      :queue.to_list(buffer.q) == slice
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
        |> Enum.drop(size-1)
        |> Enum.at(0)

      CB.oldest(buffer) == oldest
    end
  end

  def size_and_list do
    let size <- pos_integer() do
      let is <- ints(size*2, []) do
        {size, is}
      end
    end
  end

  defp ints(0, acc), do: acc
  defp ints(size, acc) do
    let i <- integer() do
      ints(size-1, [i | acc])
    end
  end
end
