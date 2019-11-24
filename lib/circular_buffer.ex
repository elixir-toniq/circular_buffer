defmodule CircularBuffer do
  @moduledoc """
  Circular Buffer built around erlang's queue module.

  When creating a circular buffer you must specify the max size:

  ```
  cb = CircularBuffer.new(10)
  ```
  """

  @doc """
  Creates a new circular buffer with a given size.
  """
  def new(size) when is_integer(size) and size > 0 do
    %{q: :queue.new(), max_size: size, count: 0}
  end

  @doc """
  Inserts a new item into the next location of the circular buffer
  """
  def insert(cb, item) do
    if cb.count < cb.max_size do
      %{cb | q: :queue.cons(item, cb.q), count: cb.count + 1}
    else
      new_q =
        cb.q
        |> :queue.drop_r
        |> (fn q -> :queue.cons(item, q) end).()

      %{cb | q: new_q}
    end
  end

  @doc """
  Converts a circular buffer to a list. The list is ordered from oldest to newest
  elements based on their insertion order.
  """
  def to_list(cb) do
    cb.q
    |> :queue.reverse
    |> :queue.to_list
  end

  @doc """
  Returns the newest element in the buffer
  """
  def newest(cb) do
    case :queue.peek(cb.q) do
      {_, val} -> val
      :empty -> nil
    end
  end

  @doc """
  Returns the oldest element in the buffer
  """
  def oldest(cb) do
    case :queue.peek_r(cb.q) do
      {_, val} -> val
      :empty -> nil
    end
  end
end
