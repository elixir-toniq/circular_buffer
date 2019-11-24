defmodule CircularBuffer do
  @moduledoc """
  Circular Buffer built around erlang's queue module.

  When creating a circular buffer you must specify the max size:

  ```
  cb = CircularBuffer.new(10)
  ```
  """

  defstruct [:q, :max_size, :count]

  alias __MODULE__, as: CB

  @doc """
  Creates a new circular buffer with a given size.
  """
  def new(size) when is_integer(size) and size > 0 do
    %CB{q: :queue.new(), max_size: size, count: 0}
  end

  @doc """
  Inserts a new item into the next location of the circular buffer
  """
  def insert(%CB{}=cb, item) do
    if cb.count < cb.max_size do
      %{cb | q: :queue.cons(item, cb.q), count: cb.count + 1}
    else
      new_q =
        cb.q
        |> :queue.drop_r
        |> (fn q -> :queue.cons(item, q) end).()

      %CB{cb | q: new_q}
    end
  end

  @doc """
  Converts a circular buffer to a list. The list is ordered from oldest to newest
  elements based on their insertion order.
  """
  def to_list(%CB{}=cb) do
    cb.q
    |> :queue.reverse
    |> :queue.to_list
  end

  @doc """
  Returns the newest element in the buffer
  """
  def newest(%CB{}=cb) do
    case :queue.peek(cb.q) do
      {_, val} -> val
      :empty -> nil
    end
  end

  @doc """
  Returns the oldest element in the buffer
  """
  def oldest(%CB{}=cb) do
    case :queue.peek_r(cb.q) do
      {_, val} -> val
      :empty -> nil
    end
  end

  @doc """
  Checks the buffer to see if its empty
  """
  def empty?(%CB{}=cb) do
    :queue.is_empty(cb.q)
  end

  defimpl Enumerable do
    def count(cb) do
      {:ok, cb.count}
    end

    def member?(cb, element) do
      {:ok, :queue.member(element, cb.q)}
    end

    def reduce(cb, acc, fun) do
      Enumerable.List.reduce(CB.to_list(cb), acc, fun)
    end

    def slice(cb) do
      {:ok, cb.count, &Enumerable.List.slice(CB.to_list(cb), &1, &2)}
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
      concat(["#CircularBuffer<", to_doc(CB.to_list(cb), opts), ">"])
    end
  end
end
