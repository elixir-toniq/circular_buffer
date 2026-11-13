defmodule CircularBufferLawsTest do
  use ExUnit.Case, async: true
  use Lynx.Case

  alias CircularBuffer, as: CB

  def fifo_insert(contents, item, size) do
    cond do
      size == 0 -> []
      length(contents) < size -> contents ++ [item]
      true -> tl(contents) ++ [item]
    end
  end

  # The lists must agree with the count. A nonempty b only occurs after filling
  # the buffer, and a nonempty buffer always has something in a.
  def valid?(a, b, count, size) do
    is_list(a) and is_list(b) and is_integer(count) and is_integer(size) and
      size >= 0 and count == length(a) + length(b) and count <= size and
      (b == [] or count == size) and (a != [] or b == [])
  end

  def valid?(%CB{a: a, b: b, count: count, max_size: size}) do
    valid?(a, b, count, size)
  end

  def buffer(a, b, count, size) do
    %CB{a: a, b: b, count: count, max_size: size}
  end

  laws "circular buffer insertion" do
    # Lean checks that valid buffers never reach this invalid field-access path.
    cutoff(&:elixir_erl_pass.no_parens_remote/2)

    # These lemmas bridge Erlang's list representation and Lean's ordinary lists.
    prelude(~LEAN"""
    module
    public import Lynx
    public import Lynx.Modules.Erlang.erlang
    public import Lynx.Modules.Erlang.lists
    public section

    namespace CircularBufferProofs
    open Lynx

    @[simp↓] theorem list_length (xs : List Term) :
        Erlang.erlang.«length/1» (Term.list xs) = .ok (.integer xs.length) := by
      induction xs with
      | nil => rfl
      | cons x xs ih => simp [Erlang.erlang.«length/1», ih]

    theorem length_returns (input value : Term)
        (returned : Erlang.erlang.«length/1» input = .ok value) :
        ∃ xs, input = Term.list xs ∧ value = .integer xs.length := by
      revert value
      induction input using Erlang.erlang.«length/1».induct with
      | case1 =>
        intro value returned
        simp [Erlang.erlang.«length/1»] at returned
        exact ⟨[], rfl, returned.symm⟩
      | case2 head tail ih =>
        intro value returned
        cases h : Erlang.erlang.«length/1» tail with
        | error error => simp [Erlang.erlang.«length/1», h] at returned
        | ok subtotal =>
          obtain ⟨xs, rfl, rfl⟩ := ih subtotal h
          simp [Erlang.erlang.«length/1»] at returned
          exact ⟨head :: xs, rfl, returned.symm⟩
      | case3 input notNil notCons =>
        intro value returned
        simp_all [Erlang.erlang.«length/1»]

    @[simp↓] theorem list_is_list (xs : List Term) :
        Erlang.erlang.«is_list/1» (Term.list xs) = .ok Term.true := by
      cases xs <;> rfl

    @[simp] theorem list_append (xs : List Term) (tail : Term) :
        Erlang.erlang.«++/2» (Term.list xs) tail =
          .ok (xs.foldr Term.cons tail) := by
      induction xs with
      | nil => rfl
      | cons x xs ih => simp [Erlang.erlang.«++/2», ih]

    @[simp] theorem list_foldr (xs ys : List Term) :
        xs.foldr Term.cons (Term.list ys) = Term.list (xs ++ ys) := by
      induction xs <;> simp_all

    @[simp↓] theorem list_append_lists (xs ys : List Term) :
        Erlang.erlang.«++/2» (Term.list xs) (Term.list ys) =
          .ok (Term.list (xs ++ ys)) := by
      simp only [list_append, list_foldr]

    @[simp↓] theorem list_reverse (xs ys : List Term) :
        Erlang.lists.«reverse/2» (Term.list xs) (Term.list ys) =
          .ok (Term.list (xs.reverse ++ ys)) := by
      induction xs generalizing ys with
      | nil => rfl
      | cons x xs ih =>
        simpa [Erlang.lists.«reverse/2», List.reverse_cons, List.append_assoc]
          using ih (x :: ys)

    end CircularBufferProofs
    """)

    law(initialization(size),
      requires: is_integer(size) and size >= 0,
      expects: valid?(CB.new(size)),
      proof: ~LEAN"""
      cases size <;>
        simp [«initialization:requires/1», Erlang.erlang.«is_integer/1»] at requires
      rename_i capacity
      simp [«initialization:ensures/1», Elixir.CircularBuffer.«new/1»,
        «valid?/1», «valid?/4», Lynx.Term.getMapKeys,
        Erlang.erlang.«is_integer/1», Erlang.erlang.«length/1»,
        Erlang.erlang.«==/2», Erlang.erlang.«/=/2»,
        Erlang.erlang.«is_list/1», requires]
      """
    )

    law(fifo_insertion(a, b, count, size, item),
      requires: valid?(a, b, count, size),
      expects:
        CB.to_list(CB.insert(buffer(a, b, count, size), item)) ==
          fifo_insert(CB.to_list(buffer(a, b, count, size)), item, size),
      proof: ~LEAN"""
      -- Turn the Elixir precondition into ordinary list and integer facts.
      simp only [«fifo_insertion:requires/5», «valid?/4»,
        Lynx.Term.true, Lynx.Except.andAlso_eq_true] at requires
      obtain ⟨⟨⟨⟨⟨⟨⟨⟨ha, hb⟩, hc⟩, hs⟩, nonnegative⟩, lengths⟩, bound⟩, full⟩, layout⟩ := requires
      cases count <;> simp [Erlang.erlang.«is_integer/1»] at hc
      cases size <;> simp [Erlang.erlang.«is_integer/1»] at hs
      rename_i count capacity
      cases la : Erlang.erlang.«length/1» a <;>
        cases lb : Erlang.erlang.«length/1» b <;> simp [la, lb] at lengths
      rename_i na nb
      obtain ⟨as, rfl, rfl⟩ := CircularBufferProofs.length_returns a na la
      obtain ⟨bs, rfl, rfl⟩ := CircularBufferProofs.length_returns b nb lb
      simp at lengths nonnegative bound
      simp [Erlang.erlang.«==/2», Erlang.erlang.«/=/2»] at full layout
      have reverse (xs : List Lynx.Term) :
          Erlang.lists.«reverse/1» (Lynx.Term.list xs) =
            .ok (Lynx.Term.list xs.reverse) := by
        cases xs with
        | nil => rfl
        | cons x xs => cases xs with
          | nil => rfl
          | cons y ys =>
            cases ys with
            | nil => rfl
            | cons z zs =>
              simpa only [Erlang.lists.«reverse/1», Lynx.Term.list_cons,
                List.reverse_cons, List.append_assoc, List.cons_append, List.nil_append]
                using CircularBufferProofs.list_reverse (z :: zs) [y, x]
      have reverse_cons (x : Lynx.Term) (xs : List Lynx.Term) :
          Erlang.lists.«reverse/1» (.cons x (Lynx.Term.list xs)) =
            .ok (Lynx.Term.list (xs.reverse ++ [x])) := by
        simpa using reverse (x :: xs)
      -- Follow insert/2: eviction, filling, zero capacity, then rotation.
      cases bs with
      | cons oldest rest =>
        have isFull : count = capacity := full (by simp)
        have positive : capacity ≠ 0 := by simp at lengths; omega
        have contentsFull : (as.length : Int) + rest.length + 1 = capacity := by
          simp at lengths
          omega
        simp [-List.foldr_reverse, «fifo_insertion:ensures/5», «buffer/4»,
          Elixir.CircularBuffer.«insert/2», Elixir.CircularBuffer.«to_list/1»,
          Lynx.Term.getMapKeys, Erlang.maps.«update/3», Erlang.erlang.«is_map/1»,
          reverse, reverse_cons, «fifo_insert/3», Erlang.erlang.«==/2»,
          Erlang.erlang.«tl/1», isFull, positive, lengths, List.append_assoc,
          CircularBufferProofs.list_append_lists, CircularBufferProofs.list_append,
          CircularBufferProofs.list_foldr, CircularBufferProofs.list_length,
          Erlang.erlang.«++/2», Erlang.erlang.«length/1», Int.add_comm, contentsFull]
        rw [CircularBufferProofs.list_foldr as.reverse [item],
          CircularBufferProofs.list_foldr rest (as.reverse ++ [item])]
        simp
      | nil =>
        by_cases filling : count < capacity
        · have positive : capacity ≠ 0 := by simp at lengths; omega
          have contentsFilling : (as.length : Int) < capacity := by simp at lengths; omega
          simp [-List.foldr_reverse, «fifo_insertion:ensures/5», «buffer/4»,
            Elixir.CircularBuffer.«insert/2», Elixir.CircularBuffer.«to_list/1»,
            Lynx.Term.getMapKeys, Erlang.maps.«update/3», Erlang.erlang.«is_map/1»,
            reverse, reverse_cons, «fifo_insert/3», Erlang.erlang.«==/2»,
            filling, positive, ← lengths,
            CircularBufferProofs.list_append_lists, CircularBufferProofs.list_append,
            CircularBufferProofs.list_foldr, CircularBufferProofs.list_length,
            Erlang.erlang.«++/2», Erlang.erlang.«length/1», contentsFilling]
          rw [CircularBufferProofs.list_foldr as.reverse [item]]
          simp
        · have isFull : count = capacity := by omega
          cases as with
          | nil =>
            have zero : capacity = 0 := by simp at lengths; omega
            have countZero : count = 0 := by simp at lengths; omega
            simp [«fifo_insertion:ensures/5», «buffer/4»,
              Elixir.CircularBuffer.«insert/2», Elixir.CircularBuffer.«to_list/1»,
              Lynx.Term.getMapKeys, reverse, «fifo_insert/3»,
              Erlang.erlang.«==/2», Erlang.erlang.«/=/2», zero, countZero,
              Erlang.erlang.«++/2»]
          | cons newest rest =>
            have positive : capacity ≠ 0 := by simp at lengths; omega
            cases hrev : (newest :: rest).reverse with
            | nil => simp at hrev
            | cons oldest remaining =>
              have remainingLength : (remaining.length : Int) + 1 = count := by
                have := congrArg List.length hrev
                simp at this lengths
                omega
              simp [«fifo_insertion:ensures/5», «buffer/4»,
                Elixir.CircularBuffer.«insert/2», Elixir.CircularBuffer.«to_list/1»,
                Lynx.Term.getMapKeys, Erlang.maps.«update/3», Erlang.erlang.«is_map/1»,
                reverse, reverse_cons, «fifo_insert/3», Erlang.erlang.«==/2»,
                Erlang.erlang.«/=/2», Erlang.erlang.«tl/1»,
                filling, positive, hrev, remainingLength,
                CircularBufferProofs.list_append_lists, CircularBufferProofs.list_append,
                CircularBufferProofs.list_foldr, CircularBufferProofs.list_length,
                Erlang.erlang.«++/2», Erlang.erlang.«length/1»]
      """
    )

    law(invariant_preservation(a, b, count, size, item),
      requires: valid?(a, b, count, size),
      expects: valid?(CB.insert(buffer(a, b, count, size), item)),
      proof: ~LEAN"""
      simp only [«invariant_preservation:requires/5», «valid?/4»,
        Lynx.Term.true, Lynx.Except.andAlso_eq_true] at requires
      obtain ⟨⟨⟨⟨⟨⟨⟨⟨ha, hb⟩, hc⟩, hs⟩, nonnegative⟩, lengths⟩, bound⟩, full⟩, layout⟩ := requires
      cases count <;> simp [Erlang.erlang.«is_integer/1»] at hc
      cases size <;> simp [Erlang.erlang.«is_integer/1»] at hs
      rename_i count capacity
      cases la : Erlang.erlang.«length/1» a <;>
        cases lb : Erlang.erlang.«length/1» b <;> simp [la, lb] at lengths
      rename_i na nb
      obtain ⟨as, rfl, rfl⟩ := CircularBufferProofs.length_returns a na la
      obtain ⟨bs, rfl, rfl⟩ := CircularBufferProofs.length_returns b nb lb
      simp at lengths nonnegative bound
      simp [Erlang.erlang.«==/2», Erlang.erlang.«/=/2»] at full layout
      have reverse (xs : List Lynx.Term) :
          Erlang.lists.«reverse/1» (Lynx.Term.list xs) =
            .ok (Lynx.Term.list xs.reverse) := by
        cases xs with
        | nil => rfl
        | cons x xs => cases xs with
          | nil => rfl
          | cons y ys =>
            cases ys with
            | nil => rfl
            | cons z zs =>
              simpa only [Erlang.lists.«reverse/1», Lynx.Term.list_cons,
                List.reverse_cons, List.append_assoc, List.cons_append, List.nil_append]
                using CircularBufferProofs.list_reverse (z :: zs) [y, x]
      cases bs with
      | cons oldest rest =>
        have isFull : count = capacity := full (by simp)
        have countLength : count = (as.length : Int) + rest.length + 1 := by
          simp at lengths
          omega
        simp [«invariant_preservation:ensures/5», «buffer/4»,
          Elixir.CircularBuffer.«insert/2», «valid?/1», «valid?/4»,
          Lynx.Term.getMapKeys, Erlang.maps.«update/3», Erlang.erlang.«is_map/1»,
          Erlang.erlang.«is_list/1», Erlang.erlang.«is_integer/1»,
          Erlang.erlang.«length/1», CircularBufferProofs.list_length,
          CircularBufferProofs.list_is_list, Erlang.erlang.«==/2»,
          Erlang.erlang.«/=/2», nonnegative, isFull, countLength]
        omega
      | nil =>
        by_cases filling : count < capacity
        · have newBound : count + 1 ≤ capacity := by omega
          have countLength : count = (as.length : Int) := by simpa using lengths
          have contentsFilling : (as.length : Int) < capacity := by omega
          have contentsBound : (as.length : Int) + 1 ≤ capacity := by omega
          simp [«invariant_preservation:ensures/5», «buffer/4»,
            Elixir.CircularBuffer.«insert/2», «valid?/1», «valid?/4»,
            Lynx.Term.getMapKeys, Erlang.maps.«update/3», Erlang.erlang.«is_map/1»,
            Erlang.erlang.«is_list/1», Erlang.erlang.«is_integer/1»,
            Erlang.erlang.«length/1», CircularBufferProofs.list_length,
            Erlang.erlang.«==/2», Erlang.erlang.«/=/2»,
            nonnegative, filling, newBound, countLength, contentsFilling, contentsBound]
        · cases as with
          | nil =>
            have zero : count = 0 := by simpa using lengths
            have capacityZero : capacity = 0 := by omega
            simp [«invariant_preservation:ensures/5», «buffer/4»,
              Elixir.CircularBuffer.«insert/2», «valid?/1», «valid?/4»,
              Lynx.Term.getMapKeys, Erlang.erlang.«is_list/1»,
              Erlang.erlang.«is_integer/1», Erlang.erlang.«length/1»,
              Erlang.erlang.«==/2», Erlang.erlang.«/=/2»,
              nonnegative, filling, zero, capacityZero]
          | cons newest rest =>
            cases hrev : (newest :: rest).reverse with
            | nil => simp at hrev
            | cons oldest remaining =>
              have isFull : count = capacity := by omega
              have remainingLength : (remaining.length : Int) + 1 = count := by
                have := congrArg List.length hrev
                simp at this lengths
                omega
              simp [«invariant_preservation:ensures/5», «buffer/4»,
                Elixir.CircularBuffer.«insert/2», «valid?/1», «valid?/4»,
                Lynx.Term.getMapKeys, Erlang.maps.«update/3», Erlang.erlang.«is_map/1»,
                reverse, Erlang.erlang.«is_list/1», Erlang.erlang.«is_integer/1»,
                Erlang.erlang.«length/1», CircularBufferProofs.list_length,
                CircularBufferProofs.list_is_list, Erlang.erlang.«tl/1»,
                Erlang.erlang.«==/2», Erlang.erlang.«/=/2»,
                filling, hrev, nonnegative, isFull, remainingLength]
              omega
      """
    )
  end
end
