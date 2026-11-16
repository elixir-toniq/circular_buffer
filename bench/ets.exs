# SPDX-FileCopyrightText: 2026 Frank Hunleth
#
# SPDX-License-Identifier: MIT

# Run with: ERL_FLAGS="+S 1:1" elixir bench/ets.exs
Mix.install([{:benchee, "~> 1.3"}], consolidate_protocols: false)

for file <- ["circular_buffer.ex", "circular_buffer/hood_melville.ex", "circular_buffer/ets.ex"] do
  Code.compile_file(Path.join(__DIR__, "../lib/#{file}"))
end

defmodule ETSBenchmark do
  def insert_n(module, buffer, n) do
    Enum.reduce(1..n, buffer, fn item, cb -> module.insert(cb, item) end)
  end

  def full_buffer(module, size) do
    insert_n(module, module.new(size), max(1, size * 3 + div(size, 2)))
  end

  def cleanup(CircularBuffer.ETS, buffer), do: CircularBuffer.ETS.delete(buffer)
  def cleanup(_module, _buffer), do: :ok

  def repeat(fun, input, 1), do: fun.(input)

  def repeat(fun, input, count) do
    fun.(input)
    repeat(fun, input, count - 1)
  end
end

implementations = [
  {"Current", CircularBuffer},
  {"Hood-Melville", CircularBuffer.HoodMelville},
  {"ETS", CircularBuffer.ETS}
]

sizes = [0, 1, 8, 32, 1_000]
inputs = Map.new(sizes, fn size -> {Integer.to_string(size), size} end)
insertions = 100_000

for size <- sizes, {name, module} <- implementations do
  buffer = ETSBenchmark.full_buffer(module, size)

  try do
    result = ETSBenchmark.insert_n(module, buffer, insertions)
    expected = if size == 0, do: [], else: Enum.to_list((insertions - size + 1)..insertions)

    unless module.to_list(result) === expected and Enum.count(result) == size do
      raise "#{name} benchmark contents disagree at capacity #{size}"
    end
  after
    ETSBenchmark.cleanup(module, buffer)
  end
end

IO.puts("Elixir #{System.version()}, OTP #{System.otp_release()}")
IO.puts("Schedulers: #{:erlang.system_info(:schedulers_online)}")
IO.puts("Private ETS tables are created and deleted in each benchmark worker.")
IO.puts("No table creation, process messaging, or snapshot checks are timed as inserts.")
IO.puts("ETS is mutable; bulk inserts end at the same ring position on each run.")

workloads = [
  {"insert_100000", fn module, buffer -> ETSBenchmark.insert_n(module, buffer, insertions) end,
   1},
  {"to_list", fn module, buffer -> module.to_list(buffer) end, 100}
]

results =
  for round <- 1..3, {operation, fun, batch_size} <- workloads, reduce: %{} do
    results ->
      IO.puts("Round #{round}/3: #{operation}")

      jobs =
        Map.new(implementations, fn {name, module} ->
          operation = fn buffer -> fun.(module, buffer) end

          job =
            {fn buffer -> ETSBenchmark.repeat(operation, buffer, batch_size) end,
             before_scenario: fn size -> ETSBenchmark.full_buffer(module, size) end,
             after_scenario: fn buffer -> ETSBenchmark.cleanup(module, buffer) end}

          {name, job}
        end)

      suite =
        Benchee.run(jobs,
          inputs: inputs,
          warmup: 0.5,
          time: 1,
          parallel: 1,
          formatters: [],
          print: [benchmarking: false, configuration: false, fast_warning: false]
        )

      Enum.reduce(suite.scenarios, results, fn scenario, acc ->
        key = {operation, scenario.input_name, scenario.job_name}
        mean = scenario.run_time_data.statistics.average / batch_size

        IO.puts(
          "round=#{round},#{operation},capacity=#{scenario.input_name}," <>
            "#{scenario.job_name},mean_ns=#{Float.round(mean, 1)}"
        )

        Map.update(acc, key, [mean], &[mean | &1])
      end)
  end

IO.puts("\nMedian of three rounds' mean timings; snapshots include batch-loop overhead.")
IO.puts("operation,capacity,current_ns,hood_melville_ns,ets_ns,ets_vs_current")

for {operation, _fun, _batch_size} <- workloads, size <- sizes do
  means =
    Enum.map(implementations, fn {name, _module} ->
      results[{operation, Integer.to_string(size), name}] |> Enum.sort() |> Enum.at(1)
    end)

  [current, _hood, ets] = means
  values = Enum.map(means ++ [ets / current], &Float.round(&1, 2))
  IO.puts(Enum.join([operation, size | values], ","))
end

IO.puts("\nRetained ETS storage after 100,000 inserts (not allocation per insert).")
IO.puts("capacity,table_entries,table_bytes,handle_bytes")

for size <- sizes do
  buffer = ETSBenchmark.full_buffer(CircularBuffer.ETS, size)

  try do
    ETSBenchmark.insert_n(CircularBuffer.ETS, buffer, insertions)
    word_size = :erlang.system_info(:wordsize)
    entries = :ets.info(buffer.table, :size)
    bytes = :ets.info(buffer.table, :memory) * word_size
    handle_bytes = :erts_debug.flat_size(buffer) * word_size
    IO.puts(Enum.join([size, entries, bytes, handle_bytes], ","))
  after
    CircularBuffer.ETS.delete(buffer)
  end
end
