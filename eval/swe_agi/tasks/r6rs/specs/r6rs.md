# R6RS Scheme — interpreter specification for this repo

This document is a **practical, test-oriented spec** for the `r6rs`
package. It summarizes the behaviors required by this repository’s MoonBit API
and tests, which collectively cover a large subset of R6RS Scheme.

It is **not** a complete reproduction of the R6RS standard text.

## Objectives (what the implementation must do)

The `r6rs` package expects an implementation that can:

1. Read and evaluate R6RS Scheme source code (multiple top-level forms).
2. Return the value of the last form (`eval_program`) or all form results in
   order (`eval_program_all`).
3. Render values in Scheme surface syntax (`value_to_string`) matching test
   expectations.
4. Raise an error on syntactic invalidity or runtime errors (the API uses `raise`).

## Primary references

- R6RS (Revised^6 Report on the Algorithmic Language Scheme):
  - Language: <https://www.r6rs.org/>
  - The report is also mirrored at: <https://scheme.com/tspl4/>

This repository also includes a migrated Racket-based R6RS test suite under:

- `r6rs/racket-r6rs-test/`

## API contract (from `r6rs/r6rs_spec.mbt`)

- `eval_program(src : String) -> Value raise`
  - Evaluates a program and returns the value of the last top-level form.
- `eval_program_all(src : String) -> Array[Value] raise`
  - Evaluates each top-level form and returns all results in order.
- `value_to_string(value : Value) -> String`
  - Renders using Scheme surface syntax (this is the test oracle for values).

`Value` is an opaque runtime value type in the public API; implementations may
use any internal representation as long as these functions behave correctly.

## Reader / syntax requirements (test-driven)

The combined test suite exercises a broad set of R6RS lexical and datum syntax,
including:

- Whitespace and comments
  - line comments `; ...`
  - datum comments `#;`
  - nested block comments `#| ... |#` (where tested)
- Identifiers, including unicode identifiers (tests include unicode coverage)
- Booleans: `#t`, `#f`
- Characters: `#\\a`, named characters, and hex forms (racket migration script
  hints at `#\\x...` cases)
- Strings:
  - escapes, including `\\n`, `\\t`, hex escapes where tested
  - possibly multiline string forms per tests
- Numbers:
  - exact/inexact
  - integers, rationals, flonums
  - complex numbers (rectangular and polar forms where tested)
  - infinities and NaNs (`+inf.0`, `-inf.0`, `+nan.0`) as exercised by tests
  - radix prefixes (`#b`, `#o`, `#d`, `#x`) and exactness prefixes (`#e`, `#i`)
- Lists and pairs:
  - proper lists `(1 2 3)`
  - dotted pairs `(1 . 2)`
  - quote syntax `'x`, quasiquote, unquote, unquote-splicing
- Vectors and bytevectors:
  - `#(1 2 3)`
  - `#vu8(1 2 3)`

## Evaluation semantics (test-driven)

The suite expects R6RS-consistent evaluation semantics for:

### Core forms and procedures

- Variable reference, definition, assignment:
  - `define`, `set!`, `define-values` (tested)
- Procedures and calls:
  - `lambda`, `case-lambda`, application, `apply`
- Conditionals and control:
  - `if`, `cond` (including `=>` clauses), `case`, `and`, `or`, `not`
  - `do` loops
- Bindings:
  - `let`, `let*`, `letrec`, `letrec*`, named `let`
  - `let-values`, `let*-values`, `call-with-values`, `values`
- Continuations and dynamic context:
  - `call/cc` (`call-with-current-continuation`)
  - `dynamic-wind`
- Exceptions and conditions:
  - `raise`, `raise-continuable`
  - `guard`, exception handlers, condition objects
- Parameters:
  - `make-parameter` and parameterization behavior

### Data structure procedures

The suite includes extensive coverage of:

- Pairs and list utilities (`cons`, `car`, `cdr`, `list`, predicates, etc.)
- Strings/chars (`string-ref`, comparisons, conversions, etc.)
- Vectors/bytevectors operations and error cases
- Hashtables (from the R6RS library set)
- Enums and sorting (as per migrated test modules)

### Macros (syntax-case)

Tests include R6RS macro facilities:

- `syntax-case`, `identifier-syntax`, pattern matching, and related utilities.

Correct macro expansion is required to pass both the migrated and hand-written
R6RS cases.

## `value_to_string` formatting contract (critical)

The tests compare `value_to_string` output exactly. Required formatting includes:

- Booleans: `#t` / `#f`
- Empty list: `()`
- Proper lists: `(1 2 3)`
- Dotted pairs: `(1 . 2)`
- Strings: quoted with escapes as needed (e.g. `"hi"`)
- Symbols/identifiers: printed without quotes (e.g. `abc`)
- Numbers: printed in readable Scheme syntax for the tested cases

When multiple exact textual forms are allowed by R6RS, this repository’s tests
define the canonical forms to produce.

## Error behavior

The API uses `raise` for both syntax and runtime errors. The test suite contains
explicit “errors” sections; implementations must:

- Raise for invalid argument counts/types where tests expect it.
- Raise for syntax errors (bad forms, invalid reader syntax) where tested.

Exact error strings are not generally asserted; error/no-error and result
correctness is.

## Conformance checklist (high value test coverage)

- Reader correctness for R6RS datum syntax (numbers, strings, chars, lists,
  vectors/bytevectors, quoting forms)
- Core evaluation semantics (bindings, procedures, control forms)
- Exceptions/conditions and continuation features (`call/cc`, `dynamic-wind`)
- Macro expansion (`syntax-case`, `identifier-syntax`)
- Value printing (`value_to_string`) matching expected canonical text
- Large programs (e.g. `tak`, `sieve`) for functional correctness and tail calls

## Library surface and “what must exist”

R6RS is both a language and a standard library set. This repository’s tests
exercise many standard procedures and syntactic forms, which implies the
interpreter must provide (at least) the commonly used bindings from:

- `(rnrs base (6))` core syntax and procedures
- `(rnrs lists (6))`, `(rnrs unicode (6))`, `(rnrs bytevectors (6))`
- `(rnrs arithmetic fixnums (6))`, `(rnrs arithmetic flonums (6))`,
  `(rnrs arithmetic bitwise (6))`
- `(rnrs exceptions (6))`, `(rnrs conditions (6))`
- `(rnrs hashtables (6))`, `(rnrs enums (6))`
- `(rnrs control (6))`, `(rnrs eval (6))`
- `(rnrs io simple (6))` at least, as the main test file includes IO behaviors

The migrated Racket tests under `r6rs/racket-r6rs-test/` are a good index of
which libraries/features are expected.

## Evaluation environment model

For this repo’s public API, you can choose:

- A single global interaction environment per `eval_program` call, or
- A fresh environment per call.

The tests mostly evaluate standalone programs; however, features like `eval`
and library imports may imply an interaction environment.

Recommendation (test-friendly):

- Treat each `eval_program`/`eval_program_all` call as evaluating a complete
  program in a fresh environment with standard libraries available, unless a
  test explicitly asserts persistence.

## Numbers: canonical behaviors to define

The tests heavily exercise the numeric tower:

- exact integers, rationals
- inexact reals (flonums), including infinities/NaNs
- complex numbers (rectangular and polar forms)
- predicates like `integer?`, `exact?`, `inexact?`, `finite?`, etc.

Important test-relevant points:

- Exactness propagation: operations must return exact results when inputs are
  exact and the result is representable exactly; otherwise inexact.
- Comparisons across exact/inexact should follow R6RS rules (including NaN
  behavior).
- Radix/exactness prefixes in the reader must be honored.

## `value_to_string`: canonical printing rules (more explicit)

The tests treat `value_to_string` output as the main oracle. In addition to the
examples already in the suite, these rules are usually required:

- Print `()` for the empty list.
- Print proper lists with space-separated elements: `(1 2 3)`.
- Print dotted pairs with ` . `: `(1 . 2)`.
- Print booleans as `#t` and `#f`.
- Print strings with quotes and escapes for special characters.
- Print symbols as their identifiers (no quotes), respecting case rules used by
  the reader.

For numbers:

- Use a stable textual form that matches the suite’s expected outputs for:
  - rationals (`1/2`)
  - complex (`1+2i` forms) and exactness markers where expected
  - infinities/NaNs tokens

Where R6RS allows multiple equivalent prints, the tests define which one to
emit.

## Continuations and dynamic-wind: behavioral notes

The suite includes `call/cc` and `dynamic-wind` tests which validate:

- Captured continuations can escape and later resume.
- `dynamic-wind` before/after thunks run in the correct order on entry/exit,
  including when continuations re-enter.
- Tail-call optimization (TCO) matters: some tests expect tail recursion to run
  without stack overflow.

## Error behavior in tests

The suite has explicit “errors” sections. Common required errors include:

- Wrong-arity errors for primitives (e.g. `(car)`).
- Type errors for primitives (e.g. `(car 1)`).
- Index errors for `string-ref`, vector accesses, bytevector operations.
- Syntax errors for malformed special forms.

The public API uses `raise` without a typed error enum; therefore, the test
oracle is usually “raises vs returns”. Exact error text is typically not
asserted.
