# SPDX-FileCopyrightText: 2026 Frank Hunleth
#
# SPDX-License-Identifier: MIT

# Run with: ERL_FLAGS="+S 1:1" elixir bench/reverse.exs
# All variants are compiled from the current source; lib/ is not modified.
Mix.install([{:benchee, "~> 1.3"}], consolidate_protocols: false)

Code.compile_file(Path.join(__DIR__, "../lib/circular_buffer/hood_melville.ex"))

defmodule ReverseBenchmark do
  def repeat(fun, input, 1), do: fun.(input)

  def repeat(fun, input, count) do
    fun.(input)
    repeat(fun, input, count - 1)
  end
end

source =
  __DIR__
  |> Path.join("../lib/circular_buffer.ex")
  |> File.read!()
  |> Code.string_to_quoted!()

for {name, reverse_arity} <- [
      {CircularBufferEnumReverse, nil},
      {CircularBufferListsReverse1, 1},
      {CircularBufferListsReverse2, 2}
    ] do
  variant =
    Macro.prewalk(source, fn
      {:__aliases__, meta, [:CircularBuffer]} ->
        {:__aliases__, meta, [name]}

      {{:., meta, [{:__aliases__, _, [:Enum]}, :reverse]}, call_meta, [list]}
      when reverse_arity in [1, 2] ->
        arguments = if reverse_arity == 1, do: [list], else: [list, []]
        {{:., meta, [:lists, :reverse]}, call_meta, arguments}

      {{:., meta, [:lists, :reverse]}, call_meta, [list]} ->
        case reverse_arity do
          nil ->
            {{:., meta, [{:__aliases__, [], [:Enum]}, :reverse]}, call_meta, [list]}

          arity ->
            arguments = if arity == 1, do: [list], else: [list, []]
            {{:., meta, [:lists, :reverse]}, call_meta, arguments}
        end

      node ->
        node
    end)

  Code.compile_quoted(variant)
end

inputs =
  for size <- [0, 1, 2, 3, 8, 32, 1_000], into: %{} do
    items = if size == 0, do: [], else: Enum.to_list(1..size)
    enum = CircularBufferEnumReverse.new(items, size)
    lists1 = CircularBufferListsReverse1.new(items, size)
    lists2 = CircularBufferListsReverse2.new(items, size)
    hood_melville = CircularBuffer.HoodMelville.new(items, size)

    {Integer.to_string(size), {enum, lists1, lists2, hood_melville}}
  end

insertions = 10_000

insert_enum = fn buffer ->
  Enum.reduce(1..insertions, buffer, fn item, cb ->
    CircularBufferEnumReverse.insert(cb, item)
  end)
end

insert_lists1 = fn buffer ->
  Enum.reduce(1..insertions, buffer, fn item, cb ->
    CircularBufferListsReverse1.insert(cb, item)
  end)
end

insert_lists2 = fn buffer ->
  Enum.reduce(1..insertions, buffer, fn item, cb ->
    CircularBufferListsReverse2.insert(cb, item)
  end)
end

insert_hood_melville = fn buffer ->
  Enum.reduce(1..insertions, buffer, fn item, cb ->
    CircularBuffer.HoodMelville.insert(cb, item)
  end)
end

for {_size, {enum, lists1, lists2, hood_melville}} <- inputs do
  for {module, lists, insert} <- [
        {CircularBufferListsReverse1, lists1, insert_lists1},
        {CircularBufferListsReverse2, lists2, insert_lists2}
      ],
      {left, right} <- [
        {enum, lists},
        {CircularBufferEnumReverse.insert(enum, :next), module.insert(lists, :next)},
        {insert_enum.(enum), insert.(lists)}
      ] do
    unless Map.from_struct(left) === Map.from_struct(right) and
             CircularBufferEnumReverse.to_list(left) ===
               module.to_list(right) and
             Enum.to_list(left) === Enum.to_list(right) do
      raise "benchmark variants disagree"
    end
  end

  for {left, right} <- [
        {enum, hood_melville},
        {CircularBufferEnumReverse.insert(enum, :next),
         CircularBuffer.HoodMelville.insert(hood_melville, :next)},
        {insert_enum.(enum), insert_hood_melville.(hood_melville)}
      ] do
    unless left.count == right.count and left.max_size == right.max_size and
             CircularBufferEnumReverse.to_list(left) ===
               CircularBuffer.HoodMelville.to_list(right) and
             Enum.to_list(left) === Enum.to_list(right) do
      raise "Hood-Melville benchmark contents disagree"
    end
  end
end

workloads = [
  {"insert_10000",
   %{
     "Enum.reverse/1" => fn {enum, _, _, _} -> insert_enum.(enum) end,
     "lists.reverse/1" => fn {_, lists1, _, _} -> insert_lists1.(lists1) end,
     "lists.reverse/2" => fn {_, _, lists2, _} -> insert_lists2.(lists2) end,
     "Hood-Melville" => fn {_, _, _, hood_melville} -> insert_hood_melville.(hood_melville) end
   }},
  {"rotation",
   %{
     "Enum.reverse/1" => fn {enum, _, _, _} -> CircularBufferEnumReverse.insert(enum, :next) end,
     "lists.reverse/1" => fn {_, lists1, _, _} ->
       CircularBufferListsReverse1.insert(lists1, :next)
     end,
     "lists.reverse/2" => fn {_, _, lists2, _} ->
       CircularBufferListsReverse2.insert(lists2, :next)
     end,
     "Hood-Melville" => fn {_, _, _, hood_melville} ->
       CircularBuffer.HoodMelville.insert(hood_melville, :next)
     end
   }},
  {"to_list",
   %{
     "Enum.reverse/1" => fn {enum, _, _, _} -> CircularBufferEnumReverse.to_list(enum) end,
     "lists.reverse/1" => fn {_, lists1, _, _} -> CircularBufferListsReverse1.to_list(lists1) end,
     "lists.reverse/2" => fn {_, _, lists2, _} -> CircularBufferListsReverse2.to_list(lists2) end,
     "Hood-Melville" => fn {_, _, _, hood_melville} ->
       CircularBuffer.HoodMelville.to_list(hood_melville)
     end
   }},
  {"reverse_only",
   %{
     "Enum.reverse/1" => fn {enum, _, _, _} -> Enum.reverse(enum.a) end,
     "lists.reverse/1" => fn {_, lists1, _, _} -> :lists.reverse(lists1.a) end,
     "lists.reverse/2" => fn {_, _, lists2, _} -> :lists.reverse(lists2.a, []) end
   }}
]

IO.puts("Elixir #{System.version()}, OTP #{System.otp_release()}")
IO.puts("Schedulers: #{:erlang.system_info(:schedulers_online)}")
IO.puts("Each input starts full; two-list variants have b=[].")
IO.puts("Rotation measures one insert, not necessarily a Hood-Melville rotation step.")

results =
  for round <- 1..3,
      {operation, jobs} <- workloads,
      reduce: %{} do
    results ->
      IO.puts("Round #{round}/3: #{operation}")

      # Batch short operations so timer and sample-collection overhead does not
      # dominate them. Report per-call times, including the common loop overhead.
      batch_size = if operation == "insert_10000", do: 1, else: 1_000

      jobs =
        Map.new(jobs, fn {name, fun} ->
          {name, fn input -> ReverseBenchmark.repeat(fun, input, batch_size) end}
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

IO.puts("\nMedian of three rounds' mean timings; negative change favors the alternative.")
IO.puts("Short operations include the common batch-loop and callback overhead.")

IO.puts(
  "operation,capacity,enum_ns,lists1_ns,lists2_ns,lists1_change_percent,lists2_change_percent," <>
    "hood_melville_ns,hood_melville_change_percent"
)

for {operation, _jobs} <- workloads, size <- [0, 1, 2, 3, 8, 32, 1_000] do
  key = Integer.to_string(size)
  enum = results[{operation, key, "Enum.reverse/1"}] |> Enum.sort() |> Enum.at(1)
  lists1 = results[{operation, key, "lists.reverse/1"}] |> Enum.sort() |> Enum.at(1)
  lists2 = results[{operation, key, "lists.reverse/2"}] |> Enum.sort() |> Enum.at(1)
  change1 = 100 * (lists1 / enum - 1)
  change2 = 100 * (lists2 / enum - 1)

  hood_melville =
    case results[{operation, key, "Hood-Melville"}] do
      nil ->
        ["", ""]

      means ->
        mean = means |> Enum.sort() |> Enum.at(1)
        Enum.map([mean, 100 * (mean / enum - 1)], &Float.round(&1, 1))
    end

  ([operation, size | Enum.map([enum, lists1, lists2, change1, change2], &Float.round(&1, 1))] ++
     hood_melville)
  |> Enum.join(",")
  |> IO.puts()
end
