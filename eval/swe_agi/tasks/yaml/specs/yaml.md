# YAML 1.2.2 — parser-oriented specification for this repo

This document is a **practical, test-oriented spec** for the `yaml`
package. It summarizes the YAML behaviors required by this repository’s MoonBit
API and test suite (including generated vectors).

It is **not** a verbatim copy of the YAML 1.2.2 specification.

## Objectives (what the implementation must do)

The `yaml` package expects an implementation that can:

1. Parse YAML text into an internal `Yaml` document representation.
2. Convert the parsed document to `Json` (`Yaml::to_json`) using a predictable
   mapping.
3. Serialize the document back to YAML (`Yaml::to_string`) such that parsing the
   serialized string yields an equivalent JSON value (roundtrip property used by
   tests).
4. Reject invalid YAML inputs with a `ParseError`.

## Primary references

- YAML 1.2.2 spec (vendored): `yaml/specs/1.2.2/spec.md`
- YAML 1.2.2 landing page: https://yaml.org/spec/1.2.2/
- YAML Test Suite (generated vectors use test IDs): https://github.com/yaml/yaml-test-suite

## Scope and explicit non-goals

### Scope

The test suite focuses on YAML’s core data model:

- Scalars: null, booleans, numbers, and strings
- Sequences: block (`- a`) and flow (`[a, b]`)
- Mappings: block (`a: b`) and flow (`{a: b}`)
- Anchors and aliases (including as mapping keys)
- Tags that influence the JSON mapping for sequences/mappings in limited cases
  (e.g. `!!set`)
- Block scalars:
  - Literal (`|`) and folded (`>`) styles

Multiple documents are allowed; the suite expects the parser to return the
**first** document when multiple documents appear in the stream.

### Non-goals

- Full YAML schema resolution beyond what tests assert (e.g. all timestamp
  corner cases).
- Emitting the exact same formatting as input in `to_string`.
- Preserving comments/whitespace.

## API contract (from `yaml/yaml_spec.mbt`)

- `parse(input : String) -> Result[Yaml, ParseError]`
- `Yaml::to_json(yaml : Yaml) -> Json`
- `Yaml::to_string(yaml : Yaml) -> String`
- `ParseError::to_string(self) -> String`

The test suite does not assert exact error text; it checks success vs failure.

## Data model and JSON mapping

The tests treat YAML as a way to construct a JSON-compatible value.

### Scalars

- Plain scalars may be resolved as:
  - `null` (e.g. `~`, explicit empty document, missing mapping values)
  - `bool` (`true`/`false`, plus the YAML 1.2 core schema forms tested)
  - `number` (integers and floats as used by the suite)
  - `string` (default when not matching the above)

Quoted scalars:

- Single-quoted: `'...'` with doubled single quote `''` representing `'`.
- Double-quoted: `"..."` with backslash escapes (e.g. `\n`, `\t`, `\\`, `\"`,
  unicode escapes when tested).

### Sequences

- Block sequence:
  ```yaml
  - one
  - two
  - 3
  ```
  maps to JSON array `["one", "two", 3]`.
- Flow sequence: `[1, 2, 3]` maps to JSON array `[1, 2, 3]`.

### Mappings

- Block mapping:
  ```yaml
  a: 1
  b: two
  ```
  maps to JSON object `{"a": 1, "b": "two"}`.
- Flow mapping: `{a: 1, b: [2, 3]}` maps to JSON object.

Key rules used by the suite:

- JSON object keys are strings derived from the YAML key’s scalar content.
- Duplicate keys are treated as an error (the suite contains invalid tests for
  duplicate mapping keys).

### Tags (suite-required behaviors)

YAML tags can alter the node kind/typing. The suite expects at least:

- `!!map` and `!!seq` tags to force mapping/sequence interpretation in some
  fixtures.
- `!!set` to be mapped to a JSON object whose keys are the set members and whose
  values are `null` (the suite includes: “sets become null-valued mapping”).

### Anchors and aliases

Anchors (`&a`) and aliases (`*a`) are supported.

Mapping to JSON:

- The JSON output must reflect the fully-resolved value graph.
- Aliases behave like “copying” the anchored node for JSON output purposes.
- Anchors/aliases can appear as mapping keys in the tested subset.

## Syntax and whitespace rules (test-relevant)

- Indentation is significant for block collections. Invalid indentation must be
  rejected.
- Comments start with `#` and run to end of line (outside scalars). Comments are
  ignored by parsing and do not affect JSON output.
- Tabs may appear as whitespace in contexts covered by the tests (the suite has
  a test asserting tabs are treated as whitespace).

## Block scalars

### Literal (`|`)

Example:

```yaml
a: |
  line1
  line2
```

The suite expects the resulting string to preserve newlines, including a final
newline if present per YAML’s block scalar rules.

### Folded (`>`)

The suite includes folded scalar examples; folded style converts some line
breaks to spaces according to YAML rules, while preserving “more-indented”
lines.

## Multiple documents

The YAML stream can contain multiple documents separated by `---` (and ended by
`...`). The test suite expects:

- The parser returns the **first** document’s value.
- Tags/anchors declared in later documents do not affect the returned result.

## Error conditions (must reject)

The invalid test suite expects failures for at least:

- Malformed YAML overall (“invalid yaml returns error”).
- Invalid flow collections (e.g. trailing tokens).
- Duplicate mapping keys.
- Invalid trailing content after a scalar where not allowed.
- Indentation errors.

## `Yaml::to_string` expectations

`Yaml::to_string` is validated indirectly by tests:

- `parse(input)` → `yaml1`
- `yaml1.to_string()` → `text`
- `parse(text)` → `yaml2`
- Assert `yaml2.to_json() == yaml1.to_json()`

Therefore `to_string` must emit YAML that is:

- Syntactically valid for all values produced by the parser.
- Semantically equivalent under the suite’s YAML→JSON mapping.

Exact formatting is not constrained; correctness is.

## Conformance checklist (high value test coverage)

- Plain scalars, quoted scalars, escapes, unicode
- Block + flow sequences and mappings
- Comments ignored in common positions
- Nulls: `~`, explicit empty document, missing mapping values
- Nested structures
- Block scalars (`|` and `>`)
- Anchors and aliases (including alias keys)
- Tags: `!!map`, `!!seq`, `!!set`
- Multiple document streams (return first)
- Generated YAML test-suite vectors

## Core schema / scalar resolution rules (test-oriented)

YAML has multiple schemas. This repository’s tests assume a JSON-like mapping
where plain scalars are resolved to:

- `null` for `~` and certain empty-document/missing-value cases
- `bool` for `true` / `false` (and potentially other YAML 1.2 core schema forms
  if present in generated vectors)
- numbers for simple integer/float forms (e.g. `42`, `0.25`)
- otherwise strings

Because YAML scalar resolution is a common source of ambiguity, treat the test
suite as canonical for borderline cases (leading zeros, `on/off`, etc.).

## Flow vs block collections: additional notes

The suite includes:

- Flow mappings/sequences (`{a: 1, b: [2, 3]}`)
- Block mappings/sequences (indentation-driven)

Important behaviors:

- Flow collections allow line breaks and comments in some positions (tests and
  generated vectors cover many such cases).
- Block indentation rules must be enforced; invalid indentation must raise.

## Block scalars: indentation and chomping

YAML block scalars (`|` and `>`) include rules for:

- Indentation detection and explicit indentation indicators
- Chomping indicators (`|-`, `|+`, `>-`, `>+`)

The suite includes many block scalar tests (including “impl01 large block scalar
indent”). Therefore:

- Preserve trailing newline behavior exactly as expected by fixtures.
- Ensure folded scalars (`>`) follow YAML folding rules:
  - convert some line breaks to spaces
  - preserve “more-indented” lines

## Anchors, aliases, and cycles

The suite requires anchors/aliases, including as mapping keys.

Practical requirements:

- Aliases resolve to the anchored node’s value in the JSON output.
- If the YAML input contains cyclic references (possible in YAML), the JSON
  mapping is not well-defined. If such cases appear in generated vectors, the
  implementation should reject or define a deterministic cycle-breaking rule.
  (If not present, cycles can be treated as out of scope.)

## Duplicate keys and merge behavior

The invalid tests include “mapping duplicates should error”, which implies:

- Duplicate mapping keys are rejected, rather than “last wins”.

YAML’s merge key (`<<`) behavior is not referenced by the public API; only
implement it if tests require it.
