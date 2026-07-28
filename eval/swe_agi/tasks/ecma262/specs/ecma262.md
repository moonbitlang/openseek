# ECMA-262 (JavaScript) — expression evaluator specification for this repo

This document is a **practical, test-oriented spec** for the `ecma262`
package. It summarizes the behavior required by this repository’s single-entry
API (`eval_expr`) and the output formatting expected by the test suite.

It is **not** a full reproduction of the ECMAScript language specification.

## Objectives (what the implementation must do)

The `ecma262` package expects an implementation that can:

1. Parse and evaluate a JavaScript **expression** string.
2. Produce a string output matching the test suite’s expected formatting (Node.js
   console-style inspection text).

## Primary references

- ECMAScript (linked by this repo): `ecma262/specs/ES.txt`
  - Current link in repo: https://262.ecma-international.org/
- Node.js behavior reference for formatting/coercions:
  - https://nodejs.org/api/util.html#utilinspectobject-options

## Scope and explicit non-goals

### Scope

The suite is expression-oriented and covers a broad subset of JavaScript
features, including:

- Literals: numbers (decimal/binary/octal/hex), strings (single/double, escapes,
  unicode), booleans, null, undefined, BigInt (`123n`), Symbols, arrays, objects
- Operators: arithmetic, comparisons, logical operators, `typeof`, etc.
- Common standard library objects/functions used in tests (e.g. `Number.*`,
  `Math.*`, `JSON.parse`, `Object.*`, array methods, etc.)
- Functions and classes where they appear in expressions.

### Non-goals

- Full JS program execution (statements, modules, async IO).
- Exact spec corner cases not covered by tests.

## API contract (from `ecma262/ecma262_spec.mbt`)

- `eval_expr(expr : String) -> String`

The function returns the string representation of the evaluated value, matching
the output format expected by tests.

## Output formatting contract (critical)

The suite compares the returned string exactly. The expected format is aligned
with Node.js’s console/inspect formatting used in common REPL outputs:

- Numbers:
  - `"0"`, `"-42"`, `"0.0015"`, `"1e-10"`, `"Infinity"`, `"NaN"`, `"-0"`
- Strings:
  - Returned **with double quotes**, using backslash escapes for control
    characters as shown by tests (e.g. `"\"hello\""` in the test source means
    the returned string is `"hello"` including quotes).
- Booleans: `"true"`, `"false"`
- null/undefined: `"null"`, `"undefined"`
- Arrays: `[ 1, 2, 3 ]` (spacing as in Node inspect)
- Objects: `{ a: 1, b: 2 }` with quoting rules similar to Node inspect
  (ident-like keys unquoted; others quoted).

Because formatting is part of the contract, implementations should treat the
test suite as the source of truth for exact spacing/quoting/escaping.

## Evaluation semantics (test-oriented summary)

The suite expects broadly ECMAScript-consistent semantics, including:

- Numeric literal parsing including `.5`, `10.`, exponent forms, and non-decimal
  prefixes (`0b`, `0o`, `0x`).
- String escape sequences and unicode escapes (`\\uXXXX`, `\\u{...}`).
- Type coercions for `+`, `-`, `*`, `/` consistent with JS (e.g. `"5" - 3 == 2`,
  `"hello" + 42 == "hello42"`, `true + true == 2`, `null + 1 == 1`,
  `undefined + 1 == NaN`).
- `typeof` results (`"undefined"`, `"object"`, `"function"`, `"symbol"`,
  `"bigint"`, etc.).

The implementation may embed or re-implement a JS runtime; regardless of
approach, it must match the observable results in the tests.

## Error handling

The current public API returns `String` and does not expose an error channel.
If evaluation fails, implementations may choose a strategy (panic, return a
sentinel string, etc.), but the provided test corpus primarily covers valid
expressions and compares their results.

## Conformance checklist (high value test coverage)

- Numeric literal parsing (decimal + binary/octal/hex + exponent forms)
- String literal parsing with escapes and unicode
- Coercion rules for arithmetic and comparisons as used by tests
- `typeof` results for many values
- Array/object literal formatting and inspection output matching snapshots
- Standard built-ins used by tests (`Number.*`, `Object.*`, `JSON.*`, etc.)

## Expression grammar scope (what counts as “an expression” here)

Even though the API is named `eval_expr`, the test corpus uses many JavaScript
constructs that are syntactically expressions (or expression-like in common JS
parsers), including:

- Literals and unary/binary operators
- Array and object literals
- Arrow functions and function expressions
- Class expressions (`class {}`) used in expression position
- `new`, `typeof`, `void`, conditional (`?:`) where tested

The implementation may:

- Use a full JS parser and evaluate an expression node, or
- Embed an existing JS engine, or
- Implement the required subset directly.

The observable behavior must match the tests’ return strings.

## Output formatting rules (more concrete)

The suite’s expected strings are close to Node.js’s `util.inspect` defaults for
primitives/arrays/objects in a REPL-like context. The following formatting
properties are frequently asserted:

### Strings

- Always rendered with **double quotes**.
- Must preserve/emit escape sequences for control characters:
  - newline as `\\n`, tab as `\\t`, backslash as `\\\\`, quote as `\\\"`, etc.
- Unicode characters may appear directly in the output when representable.

Examples from tests:

- `eval_expr("\"hello\"")` → `"\"hello\""` (returned string includes quotes)
- `eval_expr("'hello'")` → `"\"hello\""` (single-quoted literal normalizes)

### Numbers

- Decimal output without trailing `.0` for integer-valued numbers where Node
  prints an integer (e.g. `10.` → `"10"`).
- Scientific notation preserved when Node prints it (e.g. very small numbers:
  `1e-10` remains `"1e-10"`).
- `-0` must print as `"-0"`.
- `NaN`, `Infinity`, `-Infinity` as exact tokens.

### Arrays and objects

Objects:

- Printed as `{ a: 1, b: 2 }` with spaces after `{` and before `}`.
- Identifier-like keys are unquoted; other keys may be quoted (tests include
  numeric string keys: `{ "1": 1, "2": 2 }`).

Arrays:

- Printed as `[ 1, 2, 3 ]` with spaces after `[` and before `]` (as in the
  snapshots used by this repo).

Because formatting is part of the contract, treat the test corpus as the
canonical formatter specification for edge cases.

## Semantic corner cases emphasized by tests

### Type coercion

The suite includes many coercion checks, such as:

- `+` string concatenation vs numeric addition
- `-`, `*`, `/` forcing numeric conversion (e.g. `"5" - 3` → `2`)
- `null` numeric conversion (`null + 1` → `1`)
- `undefined` numeric conversion (`undefined + 1` → `NaN`)
- boolean arithmetic (`true + true` → `2`)

### IEEE-754 float behavior

The suite asserts floating point quirks:

- `0.1 + 0.2` → `0.30000000000000004`
- `0.3 - 0.1` → `0.19999999999999998`

### BigInt and Symbol

Tests include:

- BigInt literal (`123n`) and `typeof` returning `"bigint"`.
- `Symbol()` and `typeof` returning `"symbol"`.
