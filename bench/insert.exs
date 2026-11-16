# SPDX-FileCopyrightText: 2026 Frank Hunleth
#
# SPDX-License-Identifier: MIT

# Compares current, pre-b5b51f3, and Hood-Melville insert/2 implementations.
# Run with: ERL_FLAGS="+S 1:1" elixir bench/insert.exs
Mix.install([{:benchee, "~> 1.3"}], consolidate_protocols: false)

Code.compile_file(Path.join(__DIR__, "../lib/circular_buffer.ex"))
Code.compile_file(Path.join(__DIR__, "../lib/circular_buffer/hood_melville.ex"))

defmodule CircularBufferOld do
  defstruct [:a, :b, :max_size, :count]

  def new(size) when is_integer(size) and size > 0 do
    %__MODULE__{a: [], b: [], max_size: size, count: 0}
  end

  def insert(%__MODULE__{b: b} = cb, item) when b != [] do
    %{cb | a: [item | cb.a], b: tl(b)}
  end

  def insert(%__MODULE__{count: count, max_size: max_size} = cb, item)
      when count < max_size do
    %{cb | a: [item | cb.a], count: cb.count + 1}
  end

  def insert(%__MODULE__{b: []} = cb, item) do
    new_b = cb.a |> Enum.reverse() |> tl()
    %{cb | a: [item], b: new_b}
  end
end

# Warm the buffers past filling so measured inserts include steady-state
# eviction and rotation work.
size = 1_000
warmup = size * 3 + div(size, 2)

old_warm =
  Enum.reduce(1..warmup, CircularBufferOld.new(size), fn i, cb ->
    CircularBufferOld.insert(cb, i)
  end)

new_warm =
  Enum.reduce(1..warmup, CircularBuffer.new(size), fn i, cb ->
    CircularBuffer.insert(cb, i)
  end)

hood_melville_warm =
  Enum.reduce(1..warmup, CircularBuffer.HoodMelville.new(size), fn i, cb ->
    CircularBuffer.HoodMelville.insert(cb, i)
  end)

n = 100_000

jobs =
  %{
    "old insert/2 (#{n} steady-state inserts, size=#{size})" => fn ->
      Enum.reduce(1..n, old_warm, fn i, cb ->
        CircularBufferOld.insert(cb, i)
      end)
    end,
    "new insert/2 (#{n} steady-state inserts, size=#{size})" => fn ->
      Enum.reduce(1..n, new_warm, fn i, cb ->
        CircularBuffer.insert(cb, i)
      end)
    end,
    "Hood-Melville insert/2 (#{n} steady-state inserts, size=#{size})" => fn ->
      Enum.reduce(1..n, hood_melville_warm, fn i, cb ->
        CircularBuffer.HoodMelville.insert(cb, i)
      end)
    end
  }

expected = Enum.to_list((n - size + 1)..n)

for {_name, job} <- jobs do
  buffer = job.()

  contents =
    case buffer.__struct__ do
      CircularBufferOld -> buffer.b ++ Enum.reverse(buffer.a)
      module -> module.to_list(buffer)
    end

  unless buffer.count == size and contents === expected do
    raise "benchmark variants disagree"
  end
end

IO.puts("Elixir #{System.version()}, OTP #{System.otp_release()}")
IO.puts("Schedulers: #{:erlang.system_info(:schedulers_online)}")

Benchee.run(jobs,
  warmup: 1,
  time: 3,
  memory_time: 1
)
