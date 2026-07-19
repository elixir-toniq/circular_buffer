<!--
  SPDX-FileCopyrightText: None
  SPDX-License-Identifier: CC0-1.0
-->

# Changelog

## v1.1.0

* New features
  * Add `CircularBuffer.new(enumerable, max_size)` to create a buffer with an
    initial set of contents. This allows for CircularBuffers to be created at
    the end of a pipeline.
  * Add `CircularBuffer.max_size(cb)` to return the max size of the buffer. This
    avoids the Dialyzer warning when reaching into the opaque cb type.
  * `inspect`ing a CircularBuffer now returns a call to `CircularBuffer.new/2`
    that can be copy/pasted.
  * Zero-length CircularBuffers can now be created. While not normally useful,
    supporting them can remove some edge case code in people's programs and it's
    a minimal change to the CircularBuffer codebase.

## v1.0.1

* Changes
  * Improve common buffer insertion case when buffer overflows by ~13%
  * Remove unneeded list concatenation for reduce
  * Property test improvements to cover more edge cases (no issues found)

## v1.0.0

This release is identical to v0.4.2.

## v0.4.2

* Changes
  * Fix Elixir 1.19 warnings
  * Add [REUSE Software](https:/reuse.software/) for machine-readable licensing
    and copyright information
  * Minor documentation updates

## v0.4.1

* Changes
  * Documentation and code coverage improvements

## v0.4.0

* Changes
  * Switch from `:queue`-based implementation to list-based one to enable a few
    optimizations
