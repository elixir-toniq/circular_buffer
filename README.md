# CircularBuffer

[![Hex version](https://img.shields.io/hexpm/v/circular_buffer.svg "Hex version")](https://hex.pm/packages/circular_buffer)
[![API docs](https://img.shields.io/hexpm/v/circular_buffer.svg?label=hexdocs "API docs")](https://hexdocs.pm/circular_buffer/CircularBuffer.html)
[![CI](https://github.com/elixir-toniq/circular_buffer/actions/workflows/elixir.yml/badge.svg)](https://github.com/elixir-toniq/circular_buffer/actions/workflows/elixir.yml)
[![REUSE status](https://api.reuse.software/badge/github.com/elixir-toniq/circular_buffer)](https://api.reuse.software/info/github.com/elixir-toniq/circular_buffer)

CircularBuffer provides a general-purpose CircularBuffer data structure.

Docs: [https://hexdocs.pm/circular_buffer](https://hexdocs.pm/circular_buffer).

## Installation

```elixir
def deps do
  [
    {:circular_buffer, "~> 0.4"}
  ]
end
```

## Should I use this?

The entire codebase is less than 50 lines of code and has been tested using
property based testing. I believe the implementation is sound but it may not
be the highest performance library out there.

