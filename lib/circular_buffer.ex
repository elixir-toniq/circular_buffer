defmodule CircularBuffer do
  @moduledoc """
  Circular Buffer built around erlang's queue module.

  When creating a circular buffer you must specify the max size:

  ```
  cb = CircularBuffer.new(10)
  ```
  """

  def new(size) when is_integer(size) and size > 0 do
    %{q: :queue.new(), max_size: size, count: 0}
  end

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

  def to_list(cb) do
    cb.q
    |> :queue.reverse
    |> :queue.to_list
  end

  def newest(cb) do
    case :queue.peek(cb.q) do
      {_, val} -> val
      :empty -> nil
    end
  end

  def oldest(cb) do
    case :queue.peek_r(cb.q) do
      {_, val} -> val
      :empty -> nil
    end
  end
end
