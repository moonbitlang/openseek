# Python (CPython-compatible subset) — interpreter specification for this repo

This document is a **practical, test-oriented spec** for the `python`
package. It describes the contract defined by `python_spec.mbt` and the behavior
validated by the curated CPython-derived test corpus in this repository.

It is **not** a complete Python language specification.

## Objectives (what the implementation must do)

The `python` package expects an implementation that can:

1. Parse Python source in both `"exec"` (module) and `"eval"` (expression) modes.
2. Execute/evaluate code in a VM (`Vm`) with persistent global state across calls
   on the same VM.
3. Provide convenience helpers (`exec_program`, `eval_expr`, `run_file`,
   `check_syntax`, etc.) matching the declared API.
4. Raise the appropriate `PyError` variants for syntax and runtime failures.
5. Produce stable textual and JSON representations (`Value::repr`, `Value::str`,
   `Value::to_test_json`) used by tests.

## Primary references

- Python language reference (general): https://docs.python.org/3/reference/
- CPython regression tests (the suite is derived from these): https://github.com/python/cpython/tree/main/Lib/test
- This repository ships curated CPython reference sources and translated
  MoonBit tests.

## Scope and explicit non-goals

### Scope

The suite combines:

- Hand-written semantic tests, and
- A large set of **syntax-only** checks over CPython test modules via
  `check_syntax_file(...)`, plus a smaller subset of extracted semantic
  assertions.

Therefore, the most critical baseline is:

- A CPython-compatible lexer/parser (tokenization, indentation, grammar)
  sufficient to parse a broad set of CPython test modules.

### Non-goals

- Full CPython standard library, import system, filesystem layout, etc.
- Exact CPython bytecode compatibility (this is a MoonBit interpreter).
- Full IO/modeling of CPython’s runtime internals unless required by extracted
  semantic tests.

## API contract (from `python/python_spec.mbt`)

### VM lifecycle and execution

- `Vm::new() -> Vm` (fresh globals/builtins)
- `Vm::exec(self, src : StringView) -> Unit raise PyError`
- `Vm::exec_program(self, src : StringView) -> Value raise PyError`
  - Executes a multi-statement “program” and returns the value of the last
    expression statement if present, else `None`.
- `Vm::eval_expr(self, expr : StringView) -> Value raise PyError`
- Convenience functions:
  - `eval_expr(expr)`, `exec_program(src)`, `run_file(path)`

### Syntax checking

- `check_syntax(src, mode)` with `mode` in `{ "exec", "eval" }`
- `check_syntax_file(path)` parses a UTF-8 file in `"exec"` mode

### Values

- `Value::repr()` and `Value::str()` must be CPython-like (enough for tests).
- `Value::to_test_json()` must follow the schema described in `python_spec.mbt`
  (notably string encoding via Python-style `unicode_escape` without quotes).

### Errors

All failures are surfaced as `PyError` variants (see `python_spec.mbt`), such as:

- `SyntaxError`, `NameError`, `TypeError`, `ValueError`, `ZeroDivisionError`,
  `IndexError`, `KeyError`, `AttributeError`, `IoError`, `NotImplemented`.

The suite does not assert full traceback formatting; it does care about error
type in many cases.

## Parsing and compilation expectations

### Indentation and newlines

The generated syntax tests cover a wide range of Python constructs and rely on:

- Correct handling of significant indentation (INDENT/DEDENT tokens).
- Line continuation:
  - Explicit via backslash (`\\` newline)
  - Implicit inside `(...)`, `[...]`, `{...}`
- Correct treatment of CRLF vs LF in input files.

### Tokenization

At minimum, the interpreter must handle:

- Integer literals with underscores (tested).
- String literals:
  - Single-quoted, double-quoted
  - Triple-quoted
- The ellipsis token `...` as a single token.

The suite includes invalid literal tests (bad numeric forms, etc.) which must
raise `PyError::SyntaxError`.

## Execution semantics (hand-written tests)

The hand-written tests validate a subset of runtime behavior, including:

- Arithmetic and operator precedence on integers/bools
- Tuple/list/dict literals
- String indexing and slicing
- `repr`/`str` behavior on basic values
- Boolean operations and comparisons
- Some runtime errors (e.g. division by zero)

The translated suite may include additional semantic assertions where
extraction was possible.

## `Value::to_test_json` contract (critical)

Tests rely on stable JSON encoding of runtime values. Required shapes include:

- None: `{"type": "none"}`
- Bool: `{"type": "bool", "value": true|false}`
- Int: `{"type": "int", "value": "<decimal>"}` (value is a JSON string)
- Str:
  - `{"type": "str", "escape": "<unicode_escape>"}` (no surrounding quotes)
- Ellipsis: `{"type": "ellipsis"}`
- Tuple/List: `{"type": "tuple"|"list", "items": [<value-json>...] }`
- Dict: `{"type": "dict", "items": [[<key-json>, <value-json>]...] }`
  - Preserve insertion order.

The “unicode_escape” requirement exists because some CPython tests use surrogate
code points that are not valid UTF-8; implementations must represent such
strings losslessly according to the spec comments.

## Conformance checklist (high value test coverage)

- `check_syntax_file` passes for a broad subset of `reference_pub_test/test_*.py`
- Correct indentation/tokenization (including `...` and triple-quoted strings)
- `Vm` global state persists across multiple `exec`/`eval` calls on the same VM
- Correct exception variant selection for common failures
- `Value::repr`/`str` basic compatibility
- `Value::to_test_json` exact schema and stable ordering for dicts

## Parsing modes: `"exec"` vs `"eval"` (more explicit)

Python has two primary compilation modes used by this repo:

- `"exec"`: parses a module (statements, defs, control flow, indentation).
- `"eval"`: parses a single expression.

`check_syntax(src, mode)` must:

- Accept only the grammar for that mode.
- Raise `PyError::SyntaxError` on parse failures.

`Vm::exec` uses `"exec"` mode; `Vm::eval_expr` uses `"eval"` mode.

## `exec_program` semantics: “last expression value”

`Vm::exec_program` is a test convenience:

- Execute a multi-statement program.
- If the last top-level statement is an expression statement (`expr`), return
  that expression’s value.
- Otherwise return `None`.

Important edge cases:

- Trailing semicolons or newlines should not change which statement is “last”.
- If the last statement is `pass` or an assignment, return `None`.
- If evaluation raises, propagate the corresponding `PyError`.

## String representation: `repr` vs `str`

The tests use `Value::repr`/`Value::str` in a CPython-like way. Practical rules:

- `repr` should be unambiguous and roundtrip-ish for strings (quotes + escapes).
- `str` should be user-friendly (strings without quotes).

For core types:

- `None`: `"None"`
- `True`/`False`: `"True"` / `"False"`
- ints: decimal without underscores
- tuples: parentheses, including singleton tuple `(1,)` formatting
- lists: brackets
- dicts: braces; key ordering must match insertion order used by runtime

Exact formatting is test-driven; treat the provided assertions as canonical.

## `unicode_escape` and surrogate handling (expanded)

The JSON encoding for strings requires Python-style `unicode_escape` encoding
**without surrounding quotes**. Key details:

- Use `\\n`, `\\t`, `\\r`, `\\\\`, `\\'`, `\\\"` escapes where appropriate.
- Use `\\xNN` for bytes/control where expected by Python’s unicode_escape.
- Use `\\uXXXX` and `\\UXXXXXXXX` for unicode code points.

Surrogates:

- CPython allows lone surrogates in strings in some contexts (especially when
  decoding bytes with `surrogateescape` in tests).
- These are not valid Unicode scalar values and cannot be encoded in UTF-8.
- The `escape` field must represent them losslessly (e.g. `\\udc80`).

Therefore, the runtime string representation used by the interpreter must be
capable of representing these code points, or must store an alternative “byte
string with surrogateescape” model sufficient for `to_test_json`.

## Containers: ordering requirements

`Value::to_test_json` requires dict insertion order preservation:

- Python 3.7+ specifies that dict preserves insertion order.
- JSON encoding in this repo uses `items: [[k,v], ...]` to preserve that order.

Likewise, for operations like iteration over dicts/lists where tests observe
ordering, follow CPython ordering.
