# jq — query language specification for this repo

This document is a **practical, test-oriented spec** for the `jq`
package. It summarizes the subset of jq’s syntax and built-ins required by this
repository’s MoonBit API and tests.

It is **not** a verbatim copy of the jq manual.

## Objectives (what the implementation must do)

The `jq` package expects an implementation that can:

1. Parse a jq query string into an AST.
2. Parse JSON input into a `Json` value.
3. Evaluate the query against the input JSON producing **zero or more outputs**.
4. Return outputs as `Array[Json]` in evaluation order.
5. Raise on parse errors or evaluation/runtime errors.

## Primary references

- jq Manual: https://jqlang.github.io/jq/manual/
- This repo’s reference overview: `jq/specs/README.md`

## API contract (from `jq/jq_spec.mbt`)

- `run(query : String, input : String) -> Array[Json] raise`

Notes:

- The API collects **all results** of a jq filter into an array (jq itself can
  stream results).
- Errors are surfaced via `raise`; tests only require “error vs no error” and
  correct outputs for valid cases.

## JSON data model

jq operates on JSON values:

- null, boolean, number, string, array, object

Numbers are JSON numbers (tests include integers and floats).

## Evaluation model (test-oriented)

- A filter consumes an input value and produces 0..N output values.
- `,` (comma) concatenates outputs from two filters.
- `|` (pipe) feeds each output of the left filter as input to the right filter,
  concatenating results in order.

The `run` function returns the full output stream as an `Array[Json]`.

## Syntax and semantics required by the test suite

The suite covers many jq features; this section summarizes the “must support”
set at a high level. The provided test corpus is authoritative.

### Core filters

- Identity: `.`
- Literals: `null`, `true`, `false`, numbers, strings
- Field access:
  - `.foo`
  - `.foo.bar`
  - Optional: `.foo?` (missing key yields no output / null behavior as per tests)
- Indexing and slicing:
  - `.[0]`, `.[-1]`
  - `.[start:end]` slices
  - `.[]` iteration over arrays and objects

### Constructors

- Arrays: `[ expr, expr, ... ]`, `[]`
- Objects: `{key: value, ...}`, including computed keys where tested

### Operators

- Arithmetic: `+ - * / %` with type-dependent behavior (numbers, strings,
  arrays, objects) as tested.
- Comparisons: `== != < <= > >=`
- Boolean logic: `and`, `or`, `not`
- Alternative: `//` (null-coalescing style)

### Built-ins (high-level)

The test suite exercises built-ins such as:

- `length`, `keys`, `values`, `type`, `empty`
- `map(f)`, `select(pred)`
- `sort`, `sort_by(f)`, `reverse`
- `unique`, `unique_by(f)`, `group_by(f)`
- `add`, `min`, `max`, `min_by`, `max_by`
- Numeric: `floor`, `ceil`, `round`, `sqrt`, `abs`
- String: `split`, `join`, `startswith`, `endswith`, `ascii_upcase`,
  `ascii_downcase`, `ltrimstr`, `rtrimstr`, `contains`, `inside`,
  `explode`, `implode`
- Path helpers: `getpath`, `setpath`

### Control flow and variables

The suite includes (see `jq/specs/README.md` categories):

- `if ... then ... else ... end`
- `try ... catch ...`
- `as $var` bindings
- `reduce ... as $x (init; update)` (parse + evaluation)
- `def name(...) : body;` user-defined functions and calls

### Regex features

The suite includes regex operations (`test`, etc.) and invalid regex failures.

## Error conditions (must reject)

The invalid tests expect errors for:

### Parse errors

- Unclosed brackets/braces/parens/strings
- Unexpected tokens (comma, pipe, etc.)
- Invalid escapes in strings
- Malformed objects (missing colon)
- Invalid numbers
- Malformed slice/index syntax
- Malformed `reduce`/`def` forms as asserted by tests

### Evaluation errors

- Type mismatches (e.g. adding string and number where not defined by tests)
- Indexing non-arrays or out of bounds where tests require error
- Accessing fields on non-objects where tests require error
- Division/modulo by zero
- Invalid regex patterns
- Domain errors (e.g. `sqrt` of negative)

## Conformance checklist (high value test coverage)

- Streaming semantics captured into `Array[Json]` deterministically
- Field access, indexing, slicing, iteration
- Pipe/comma composition ordering
- Constructors, operators, and core built-ins
- Variables/reduce/defs
- Regex functions and error cases
- Parse/eval error reporting (at least error/no-error and correct category)

## Output stream semantics (more explicit)

jq is fundamentally a stream processor. This repository collects that stream
into an `Array[Json]`:

- `.` produces exactly 1 output (the input).
- `empty` produces 0 outputs.
- `a, b` concatenates outputs from `a` and `b` (left then right).
- `a | b` feeds each output of `a` into `b`, concatenating all results in order.

Determinism requirements:

- Object iteration order must be stable where it affects output; prefer
  deterministic key ordering if the semantics are not specified by tests.
- For functions like `keys`, output ordering must match expected results in
  tests (commonly sorted keys for objects, numeric indices for arrays).

## Field access and optional variants

The suite covers:

- `.foo` on objects:
  - If key exists, output its value.
  - If the key does not exist, output `null`.
- `.foo?` optional access:
  - Usually suppresses errors and yields `null`/no output depending on context.

Because jq has subtle distinctions between “null value” and “no output”, treat
the tests as the canonical definition for missing-key behaviors.

## Indexing, slicing, and iteration details

### Indexing

- `.[i]` for arrays (0-based)
- Negative indices count from the end (`.[-1]` is last element).
- Indexing a value of the wrong type raises an error.
- An array index outside the valid range yields `null`.

### Slicing

`.[start:end]`:

- start/end may be omitted.
- Negative start/end are interpreted relative to array length.
- If bounds exceed the array, jq clamps them; tests define exact clamping rules.

### Iteration

`.[]`:

- On arrays: outputs each element.
- On objects: outputs each value (and ordering is important for determinism).

`.[]?`:

- Optional iteration suppresses errors on non-iterables.

## Built-ins: ordering-sensitive functions

Some built-ins are sensitive to ordering and equality semantics:

- `sort` and `sort_by` must follow jq’s ordering across JSON types (null, bool,
  number, string, array, object) where tests cover it.
- `group_by(f)` requires input to be sorted by `f` first in jq; tests may assume
  jq’s behavior where `group_by` sorts internally or requires pre-sorted input.
- `unique`/`unique_by` similarly depend on sorting semantics.

Use the test corpus as the source of truth for these ordering behaviors.

## Error taxonomy (practical)

Even though the public API uses `raise` without a typed error enum, it is useful
to ensure errors are categorized consistently in implementation:

- Parse-time errors:
  - malformed syntax, unclosed delimiters, invalid escapes, invalid numbers
- Eval-time errors:
  - type mismatches (e.g. `length` on number where tests expect error)
  - indices applied to values of the wrong type
  - division/modulo by zero
  - invalid regex patterns
  - domain errors (`sqrt` negative)
