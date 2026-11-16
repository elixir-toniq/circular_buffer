// SPDX-FileCopyrightText: 2026 Frank Hunleth
//
// SPDX-License-Identifier: MIT

// Run with: node --test bench/visualize_test.mjs
import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import vm from "node:vm";
import test from "node:test";

const html = readFileSync(new URL("./visualize.html", import.meta.url), "utf8");
const context = vm.createContext({});
vm.runInContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], context);
const model = context.CircularBufferVisualization;
const plain = value => JSON.parse(JSON.stringify(value));
const root = fileURLToPath(new URL("../", import.meta.url));

test("JavaScript states match both Elixir implementations after every insert", () => {
  const script = `
    defmodule VisualizationReference do
      def json(nil), do: "null"
      def json(value) when is_integer(value), do: Integer.to_string(value)
      def json(value) when is_atom(value), do: inspect(Atom.to_string(value))
      def json(value) when is_tuple(value), do: json(Tuple.to_list(value))
      def json(value) when is_list(value), do: "[" <> Enum.map_join(value, ",", &json/1) <> "]"
      def json(value) when is_map(value) do
        fields = value |> Map.delete(:__struct__) |> Enum.map_join(",", fn {key, val} ->
          json(key) <> ":" <> json(val)
        end)
        "{" <> fields <> "}"
      end

      def run do
        for size <- Enum.to_list(0..32) ++ [64, 1000] do
          Enum.reduce(1..max(128, size * 3), {CircularBuffer.new(size), CircularBuffer.HoodMelville.new(size)}, fn item, {current, hood} ->
            current = CircularBuffer.insert(current, item)
            hood = CircularBuffer.HoodMelville.insert(hood, item)
            IO.puts(json(%{size: size, item: item, current: current, hood: hood}))
            {current, hood}
          end)
        end
      end
    end
    VisualizationReference.run()
  `;
  const reference = spawnSync("elixir", [
    "-r", "lib/circular_buffer.ex",
    "-r", "lib/circular_buffer/hood_melville.ex",
    "-e", script
  ], {cwd: root, encoding: "utf8", maxBuffer: 32 * 1024 * 1024, timeout: 60_000});
  assert.equal(reference.status, 0, reference.stderr);
  let current, hood, size;
  const states = new Set();
  let sawInvalidation = false;
  for (const line of reference.stdout.trim().split("\n")) {
    const expected = JSON.parse(line);
    if (expected.size !== size) {
      size = expected.size;
      current = model.newCurrent(size);
      hood = model.newHood(size);
    }
    const oldCurrent = plain(current);
    const oldHood = plain(hood);
    const nextCurrent = model.insertCurrent(current, expected.item);
    const nextHood = model.insertHood(hood, expected.item);
    assert.deepEqual(plain(current), oldCurrent, "current insert must preserve the old version");
    assert.deepEqual(plain(hood), oldHood, "Hood-Melville insert must preserve the old version");
    current = nextCurrent.buffer;
    hood = nextHood.buffer;
    assert.deepEqual(plain(current), expected.current, `current: size=${size}, item=${expected.item}`);
    assert.deepEqual(plain(hood), expected.hood, `Hood-Melville: size=${size}, item=${expected.item}`);
    const contents = size === 0 ? [] : Array.from(
      {length: Math.min(size, expected.item)},
      (_, index) => expected.item - Math.min(size, expected.item) + index + 1
    );
    assert.deepEqual(plain(model.currentContents(current)), contents);
    assert.deepEqual(plain(model.hoodContents(hood)), contents);
    assert.ok(nextHood.work.steps <= 4, "at most four active rotation steps per insert");
    assert.equal(nextHood.work.scheduled, size === 0 ? 0 : expected.item > size ? 4 : 2);
    for (const frame of nextHood.frames) {
      const rotation = frame.buffer.rotation;
      states.add(Array.isArray(rotation) ? rotation[0] : rotation);
      sawInvalidation ||= frame.title.includes("invalidate");
    }
  }
  assert.deepEqual([...states].sort(), ["appending", "done", "idle", "reversing"]);
  assert.ok(sawInvalidation, "the traces must include evictions during rotation");
});

test("replay snapshots reconstruct the logical queue without changing the result", () => {
  for (const size of [0, 1, 2, 3, 8, 16, 32]) {
    let cb = model.newHood(size);
    for (let item = 1; item <= 200; item++) {
      const result = model.insertHood(cb, item);
      const before = plain(model.hoodContents(cb));
      const after = plain(model.hoodContents(result.buffer));
      const dequeued = before.slice(1);
      for (const frame of result.frames) {
        const contents = plain(model.hoodContents(frame.buffer));
        assert.ok(
          [before, dequeued, after].some(expected => JSON.stringify(expected) === JSON.stringify(contents)),
          `invalid checkpoint contents: size=${size}, item=${item}, event=${frame.title}`
        );
        assert.equal(contents.length, frame.buffer.count);
      }
      assert.deepEqual(plain(model.hoodContents(result.buffer)), after);
      cb = result.buffer;
    }
  }
});
