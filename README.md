# CircularBuffer

[![Hex version](https://img.shields.io/hexpm/v/circular_buffer.svg "Hex version")](https://hex.pm/packages/circular_buffer)
[![API docs](https://img.shields.io/hexpm/v/circular_buffer.svg?label=hexdocs "API docs")](https://hexdocs.pm/circular_buffer/CircularBuffer.html)
[![CI](https://github.com/elixir-toniq/circular_buffer/actions/workflows/elixir.yml/badge.svg)](https://github.com/elixir-toniq/circular_buffer/actions/workflows/elixir.yml)
[![REUSE status](https://api.reuse.software/badge/github.com/elixir-toniq/circular_buffer)](https://api.reuse.software/info/github.com/elixir-toniq/circular_buffer)

CircularBuffer provides a general-purpose circular buffer data structure.

```elixir
# Create a new circular buffer that holds 5 elements
iex> cb = CircularBuffer.new(5)
#CircularBuffer<[]>

# Fill it up
iex> cb = Enum.into(1..5, cb)
#CircularBuffer<[1, 2, 3, 4, 5]>

# Verify that 1 is the oldest and 5 is the newest element in the buffer
iex> CircularBuffer.oldest(cb)
1
iex> CircularBuffer.newest(cb)
5

# Add another element. 1 gets pushed out.
iex> cb = CircularBuffer.insert(cb, 6)
#CircularBuffer<[2, 3, 4, 5, 6]>

# CircularBuffer implements Enumerable so all Enum.* functions work
iex> Enum.sum(cb)
20
```

## Installation

```elixir
def deps do
  [
    {:circular_buffer, "~> 1.0"}
  ]
end
```

## Should I use this?

The entire codebase is about 70 lines of code, has been tested using property
based testing, and has been used in production for several years. I believe the
implementation is sound but it may not be the highest performance library out
there.
