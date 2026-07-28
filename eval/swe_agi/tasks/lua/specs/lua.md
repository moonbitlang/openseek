# Lua 5.4 — interpreter specification for this repo

This document is a **practical, test-oriented spec** for the `lua`
package. It summarizes the Lua behavior expected by this repository’s MoonBit
API and tests.

It is **not** a verbatim copy of the Lua reference manual.

## Objectives (what the implementation must do)

The `lua` package expects an implementation that can:

1. Parse and execute Lua chunks (Lua 5.4 language) provided as UTF-8 text.
2. Provide a fresh VM for each `exec` call.
3. Load a standard set of libraries required by the tests.
4. Raise `LuaError::SyntaxError` for parse/compile errors.
5. Raise `LuaError::RuntimeError` for runtime failures (including failed
   `assert`, type errors, etc.).

## Primary references

- Lua 5.4 Reference Manual (vendored): `lua/specs/lua-5.4.8-manual.of`
- Lua 5.4 Reference Manual (online): https://www.lua.org/manual/5.4/

## Scope and explicit non-goals

### Scope

- Lua 5.4 grammar and semantics as exercised by the provided suite.
- Standard libraries required by `lua_spec.mbt`:
  - base, string, table, math, coroutine

### Non-goals

- C module loading (`require` with native modules), OS library, IO library,
  package searchers beyond what tests need.
- Debug library (unless tests require it).

## API contract (from `lua/lua_spec.mbt`)

- `exec(src : StringView) -> Unit raise LuaError`

Error type:

- `LuaError::SyntaxError(String)`
- `LuaError::RuntimeError(String)`

## Execution model for this suite

### Fresh VM per call

Each `exec` call must run in a new interpreter instance:

- No state is preserved across calls (globals, package cache, etc.).
- This simplifies testing and mirrors a “run this snippet” harness.

### Standard libraries

The suite requires these libraries to be present and functional:

- `_G` / base library (including `assert`, `error`, `type`, `tostring`, etc.)
- `string` library
- `table` library
- `math` library
- `coroutine` library

The tests often rely on Lua’s own `assert(...)` to signal failure; a failed
assert must manifest as `LuaError::RuntimeError`.

### Errors

- Syntax errors: invalid Lua source, unmatched constructs, invalid tokens, etc.
  must raise `LuaError::SyntaxError`.
- Runtime errors: arithmetic/type errors, explicit `error(...)`, failed
  `assert(...)`, indexing nil, etc. must raise `LuaError::RuntimeError`.

The tests do not assert exact error strings; a helpful message is recommended.

## Conformance checklist (high value test coverage)

- Parsing and executing Lua 5.4 chunks used by easy/mid/hard tests
- Correct classification of syntax vs runtime errors
- Presence of required standard libraries and common functions
- Deterministic behavior (fresh VM each call)

## Value, environment, and library expectations (test-oriented)

Although the public API only exposes `exec`, the tests rely on standard Lua
behavior observable through side effects and `assert`:

- Global environment `_G` exists.
- Standard functions exist and behave Lua-compatibly where exercised:
  - `assert`, `error`, `pcall`, `xpcall`, `type`, `tostring`, `tonumber`,
    `pairs`, `ipairs`, `next`, `select`, etc.
- The following library tables must be present (per `lua_spec.mbt`) and include
  the common functions used in the corpus:
  - `string` (e.g. `sub`, `find`, `match`, `gsub`, `byte`, `char`)
  - `table` (e.g. `insert`, `remove`, `concat`, `sort`, `pack`, `unpack`)
  - `math` (e.g. `abs`, `floor`, `ceil`, `sqrt`, trig, `random` if tested)
  - `coroutine` (e.g. `create`, `resume`, `yield`, `status`, `wrap`)

Notes:

- If the tests use randomness, `math.random` determinism may matter; prefer a
  deterministic seed unless tests explicitly require nondeterminism.
- The suite treats `assert(false)` as a runtime error; it should map to
  `LuaError::RuntimeError`.

## Chunk execution model

- Input is a “chunk” (Lua source file) and is compiled then executed.
- Statement separators (`;`) are optional.
- Newlines are significant primarily as statement separators.
- Short-circuit semantics for `and` / `or` and proper precedence must match Lua.

## Error classification examples

### Syntax errors

Should raise `LuaError::SyntaxError`:

- Unterminated string literals
- Mismatched block structure (`end` missing)
- Invalid tokens

### Runtime errors

Should raise `LuaError::RuntimeError`:

- `error("msg")`
- Calling a nil value (`f()` when `f == nil`)
- Arithmetic on non-numbers (`"a" + 1` in Lua)
- Table indexing errors where applicable
- `assert(...)` failures
