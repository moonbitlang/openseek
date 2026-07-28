# TOML (v1.0.0 + selected v1.1.0 behaviors) — parser-oriented specification for this repo

This document is a **practical, test-oriented spec** for the `toml`
package. It describes the behavior required by this repository’s MoonBit API and
test suite and calls out deliberate choices made by the tests.

It is **not** a verbatim copy of the TOML specification.

## Objectives (what the implementation must do)

The `toml` package expects an implementation that can:

1. Parse TOML text into an internal `Toml` value representing the full document.
2. Reject malformed TOML inputs with a `ParseError`.
3. Produce a stable JSON view via `Toml::to_test_json()` for snapshot checking.

## Primary references

- TOML v1.0.0 (local copy): `toml/specs/v1.0.0.md`
- TOML v1.1.0 (local copy): `toml/specs/v1.1.0.md`
- TOML spec (online): https://toml.io/en/
- RFC 3339 for datetime lexical forms: https://www.rfc-editor.org/rfc/rfc3339

## Scope and explicit non-goals

### Scope

- Key/value pairs, tables (`[a]`), array-of-tables (`[[a]]`), and dotted keys.
- Value kinds used by the JSON test encoding:
  - string, integer, float, bool
  - offset datetime, local datetime, local date, local time
  - arrays
  - tables (objects)
  - inline tables (treated as tables)
- Comments (`# ...`) and flexible whitespace around tokens.

### Intentional differences from TOML (test-suite choices)

The upstream TOML spec requires arrays to be homogeneous (“all values of the
same type”). **This test suite explicitly accepts heterogeneous arrays**, and
the JSON encoding preserves the per-element type tags.

### Non-goals

- Semantic validation beyond what the tests cover (e.g. rejecting duplicate keys
  in every corner case) is not required unless tested.
- Round-tripping with whitespace/comments preservation is not required.

## API contract (from `toml/toml_spec.mbt`)

- `parse(input : StringView) -> Result[Toml, ParseError]`
- `Toml::to_test_json(self) -> Json` (encoding documented in `toml_spec.mbt`)
- `ParseError::to_string(self) -> String` (message text not asserted)

## Document model

### Keys

A key identifies a location in the document’s table tree.

Supported key forms (as used by the tests):

- Bare keys: `abc`, `A_B_0`, `x-y` (per spec’s allowed characters)
- Quoted keys:
  - Basic string keys: `"a b"`
  - Literal string keys: `'a b'`
- Dotted keys: `a.b.c = 1` creates nested tables

Key rules required by the tests:

- Keys are case-sensitive.
- Whitespace around `=` is allowed.
- Empty quoted keys are allowed (e.g. `"" = 1`) and create a key with empty name.

### Tables and arrays-of-tables

- Table header: `[table]` sets the “current table”.
- Nested table headers: `[a.b]` create/enter nested tables.
- Array-of-tables: `[[arr]]` appends a new table to an array at key `arr`.

The suite follows TOML’s general “table cannot be redefined in conflicting
ways” intent; details are ultimately driven by the tests.

## Values

### JSON encoding contract (how tests validate values)

Scalar values are encoded as:

```json
{ "type": "<toml-type>", "value": "<string>" }
```

Where `<toml-type>` is one of:

- `string`
- `integer`
- `float`
- `bool`
- `datetime` (offset date-time)
- `datetime-local`
- `date-local`
- `time-local`

And `<string>` is always a JSON string holding the canonical textual form for
that scalar.

Tables are JSON objects mapping keys to encoded values/tables/arrays.
Arrays are JSON arrays containing encoded scalars or nested arrays/tables.

### Strings

The test suite expects support for:

- Basic strings: `"..."` with backslash escapes
  - Escapes used in tests include: `\\`, `\"`, `\n`, `\t`, `\r`, and unicode
    escapes (`\uXXXX`, `\UXXXXXXXX`) where present.
- Literal strings: `'...'` (no escapes).
- Multiline basic strings: `""" ... """`
  - Support the TOML rules around the first newline being trimmed and the use
    of `\` at end-of-line for line continuation when tested.
- Multiline literal strings: `''' ... '''`

### Integers

Support the lexical forms exercised by the tests:

- Decimal: `0`, `42`, `+1`, `-1`
- Hex: `0xDEADBEEF` / `0X...`
- Octal: `0o755` / `0O...`
- Binary: `0b1010` / `0B...`
- Underscores as digit separators: `1_000_000`

Canonicalization in JSON:

- Encode the parsed integer value as a base-10 string (no underscores, no base
  prefix), preserving sign.

Range:

- Tests include large integers; the intended representation is at least signed
  64-bit (`Int64`). Inputs outside the supported range should be rejected.

### Floats

Support the lexical forms used by the tests:

- Decimal floats: `1.0`, `-0.01`
- Exponents: `1e3`, `1E-3`, `+1.5e+2`
- Leading/trailing decimal points where TOML allows them (per tests)

Canonicalization in JSON:

- Encode a readable decimal/exponent string consistent with the tests’ expected
  outputs (the suite’s fixtures define the canonical form).

### Booleans

- `true` and `false` (lowercase).
- JSON `value` is `"true"` or `"false"` (as a string, per the encoding rules).

### Date and time values (RFC 3339-like)

The suite uses the TOML types:

- Offset Date-Time: `1979-05-27T07:32:00Z`, `1979-05-27T07:32:00-07:00`
  - Encode in RFC 3339 form.
- Local Date-Time: `1979-05-27T07:32:00`
- Local Date: `1979-05-27`
- Local Time: `07:32:00` (including fractional seconds when present)

Canonicalization:

- Use the lexical form required by `Toml::to_test_json()` snapshots.

### Arrays

Arrays are bracketed lists: `[ value, value, ... ]`.

Rules used by this suite:

- Allow whitespace/newlines freely within arrays.
- Allow trailing commas only if tests expect them (follow TOML).
- **Allow heterogeneous arrays** (suite-specific).
- Allow nested arrays.
- Allow arrays to contain tables only via inline tables or arrays-of-tables
  constructs per TOML rules, as covered by tests.

### Inline tables

Inline tables use `{ key = value, ... }` and behave like tables.

## Whitespace, newlines, and comments

- Comments start with `#` and run to end of line, except inside strings.
- Newlines may be LF or CRLF.
- Spaces and tabs may appear around tokens where TOML allows them.

## Duplicate keys and overwrite behavior

The TOML spec forbids redefining a key in a way that would change its type or
overwrite an existing value. The exact enforcement in this repository is driven
by the invalid tests; implementers should treat duplicates as errors unless a
test demonstrates allowed behavior.

## Error conditions (must reject)

The invalid test suite expects failures for malformed inputs such as:

- Invalid numeric forms (bad underscores, invalid bases, etc.)
- Unclosed strings / invalid escapes
- Invalid table headers / malformed array syntax
- Key/value syntax errors (missing `=`, etc.)
- Forbidden redefinitions or structural conflicts where tested

## Conformance checklist (high value test coverage)

- Scalars: strings (all four string forms), ints (all bases + underscores),
  floats (exponents), bools
- Comments in tricky positions, including non-ASCII
- Empty documents and documents containing only whitespace/comments
- Keys: bare, quoted, dotted, empty quoted keys, and case-sensitivity
- Tables + subtables + array-of-tables
- Arrays: nested, mixed types, and mixed arrays/scalars
- RFC 3339-like datetime/local date/time parsing and canonical JSON encoding

## Key path and table conflict rules (more explicit)

The most common TOML implementation pitfalls are around “what gets created when”
and “what counts as redefining a key”. This repo’s invalid tests are the
authority, but these general rules usually apply:

### Dotted keys vs explicit tables

- `a.b = 1` creates table `a` (if absent) and sets key `b` inside it.
- `[a]` explicitly declares table `a` (creating it if absent).

Conflict examples (typically invalid in TOML and usually tested):

- If `a` is already a scalar, then `[a]` is invalid.
- If `a` is already an array, then `[a]` is invalid unless `a` is an array of
  tables with the correct shape.

### Array-of-tables (`[[x]]`)

`[[arr]]` appends a new table to the array at key `arr`.

Typical constraints:

- If `arr` does not exist, create it as an array and append a new table.
- If `arr` exists and is an array of tables, append a new table.
- Otherwise it is an error.

When writing into an array-of-tables:

- Keys following `[[arr]]` belong to the most recently appended table.

### Inline tables

Inline tables `{ a = 1, b = 2 }` behave like tables, but TOML usually restricts:

- No newlines inside an inline table literal.
- Keys inside inline tables are resolved immediately.

Treat the invalid test suite as canonical for which restrictions are enforced.

## Scalars: additional TOML lexical forms

The TOML spec includes several lexical forms that are easy to overlook; the test
suite covers many of them.

### Float special values

TOML supports:

- `inf`, `+inf`, `-inf`
- `nan`, `+nan`, `-nan`

If these appear in tests, the JSON encoding should use `"type": "float"` and a
canonical `"value"` string matching the fixtures.

### Underscore rules (numbers)

Underscores are allowed between digits but not:

- at the start or end
- adjacent to a decimal point
- adjacent to exponent markers
- repeated `__`

The invalid suite usually includes underscore corner cases; use it as the
source of truth.

## Datetime canonicalization notes

TOML datetimes are RFC 3339-like, but canonical output for tests is determined
by fixtures. Practical rules:

- Preserve the presence/absence of offset:
  - offset datetime uses `"datetime"`
  - local datetime uses `"datetime-local"`
- Preserve precision:
  - If fractional seconds are present, keep them in `"value"`.
- Normalize `Z` for UTC if fixtures use it.

## Arrays: suite-specific heterogeneous behavior (expanded)

Upstream TOML requires arrays to be homogeneous. This repository’s test suite
explicitly accepts heterogeneous arrays, including:

- arrays mixing ints and floats
- arrays mixing scalars and nested arrays

In JSON:

- Each element keeps its own tagged encoding (scalar object or nested array).

Implementers must not “reject” heterogeneous arrays just because TOML spec says
so; the tests define acceptance here.

## Test suite coverage

- Broad positive coverage and spec-derived fixtures
- Negative coverage for syntax, conflicts, and bad literals
- `toml/specs/v1.0.0.md`, `toml/specs/v1.1.0.md`: upstream reference texts vendored here
