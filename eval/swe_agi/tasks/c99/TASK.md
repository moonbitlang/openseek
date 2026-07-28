## Goal

Implement a MoonBit **C99 parser** (subset) that produces a correct AST and a
stable JSON encoding that matches this repository’s test suite. The authoritative
repo reference is vendored in:

- `specs/c99.md`

## What This Task Is Really About

This is an exercise in building a **real parser** for a real programming
language. The goal is to parse C99 source text into a structured AST with type
information — not to pattern-match test strings.

A proper implementation will have:

- A **lexer** that tokenizes keywords, identifiers, literals, and punctuation
- A **parser** that builds an AST for a translation unit
- A **type/declaration pass** that tracks scopes, typedef names, and computes
  expression `ctype`/`repr` fields as required by tests
- A **serializer** that encodes the AST into the exact JSON schema used in tests

**Important mindset**: If the test suite were regenerated with different
literals or identifier names (but still within the supported grammar), your
implementation should still pass. If it wouldn’t, you haven’t built a parser —
you’ve built a lookup table.

## Approach

Build incrementally:

1. **Lexing**: identifiers, keywords, numeric/char/string literals, operators,
   punctuation, and whitespace/comments.
2. **Parsing expressions**: precedence/associativity, postfix/unary/cast.
3. **Parsing declarations**: declarators, pointers/arrays/functions, structs/enums.
4. **Parsing statements**: blocks, control flow, labels/goto, switch/case.
5. **Semantic checks + typing**: typedef disambiguation, scopes, and required
   `ctype`/`repr` computation.
6. **JSON encoding**: implement `CProgram::to_test_json()` to match snapshots.

Run tests frequently while adding features.

Important: The core logic must be implemented in MoonBit.

## Scope

In scope for this parser implementation (as exercised by tests):

- Translation unit parsing and AST construction
- Declarations/definitions and statement parsing needed by the suite
- Expression parsing with correct C precedence and associativity
- Typedef/tag name tracking sufficient to disambiguate declarations vs expressions
- Deterministic JSON encoding via `CProgram::to_test_json()`

The graded subset is the C99 syntax whose output is defined by the normative
AST/JSON vocabulary in `specs/c99.md`. A construct mentioned as C99 background
but absent from that vocabulary is outside the current grading contract.
Extending the graded subset requires updating the vendored specification and
adding a documented conformance example before any test may require the new
JSON shape.

Repo-specific note (important):

- Tests assert a **specific JSON schema** and require expression nodes to carry
  expected typing/representation fields; match that schema exactly.
- Tests may vary source spelling, identifiers, literal values, nesting, and
  combinations within the documented contract. They must not introduce a new
  JSON `"type"`, `"kind"`, payload field, option encoding, or type mapping that
  is absent from `specs/c99.md`.

Out of scope (not required by current tests):

- Preprocessor directives, macro expansion, includes, and pragmas
- Code generation or execution
- C11 additions such as `_Alignof`, `_Atomic`, and `_Noreturn`

## Required API

Complete the declarations in `c99_spec.mbt`.

Implementation notes:

- You can **freely decide** the project structure (modules/files/directories),
  the parsing strategy, and any internal data structures.
- Do **not** modify the following files:
  - `c99_spec.mbt` - API specification
  - `specs/` folder - Reference documents
  - Provided `*_test.mbt` files - Test fixtures
- Implement the required declarations by adding new `.mbt` files as needed.
- **You may add additional test files** (e.g., xxx_test.mbt) if needed for testing and maintenance purposes
  - Create additional test files (e.g., `xxx_test.mbt`) to validate edge cases
  - Derive test scenarios from `specs/c99.md`
  - All added tests must remain faithful to the behaviors used by this repo

Required entry points:

- `@c99.parse(code : StringView) -> CProgram raise ParseError`
- `@c99.CProgram::to_test_json(self : CProgram) -> Json`

## Behavioral rules

- Follow the covered C99 grammar and precedence rules.
- Typedef name resolution is required to disambiguate declarations vs expressions.
- `to_test_json()` must match the explicit JSON schema used by tests exactly.
- On invalid input, raise `ParseError` (message text is not the oracle; structure is).

## Target data model

This task uses one fixed data model so type annotations are deterministic:

- LP64: `char` is 8 bits, `short` is 16 bits, `int` is 32 bits, and `long`,
  `long long`, and pointers are 64 bits.
- `size_t` is `unsigned long`.
- Consequently, every `sizeof` expression has
  `repr = "unsigned long"` and `dataKind.kind = "ULong"`, regardless of its
  operand.

## Test execution

```bash
moon test
```

Use `moon test --update` only if you intentionally change snapshots.


## Constraints

### 1. Test Requirements

Implement the complete graded C99 subset documented by the grammar and
normative AST/JSON vocabulary, not only the examples exercised by the provided
tests. Run `moon test` frequently and keep iterating until it passes. Do not
hardcode fixture inputs or expected outputs; build a general lexer, parser,
semantic pass, and serializer for arbitrary inputs within the supported
grammar. When the implementation and verification are complete, finish the
task.

### 2. Code Quality Requirements

**Correctness**:
- Zero compiler errors, warnings, or diagnostics
- No runtime panics or unhandled edge cases
- Proper error handling with meaningful error messages

**Formatting**:
- Run `moon fmt` to format all code
- Run `moon info` to generate interface files (`.mbti`)
- Follow MoonBit style conventions consistently

**Implementation Integrity**:
- Solutions must be real parsers, not test-specific lookup tables
- No hardcoded mappings derived from test fixtures
- Implementation should work for arbitrary inputs within the supported grammar

### 3. Software Engineering Standards

**Modularity and Organization**:
- The required declarations in `c99_spec.mbt` belong to the root `c99`
  package. Tests call root-package APIs such as `@c99.parse`, so those
  declarations must be implemented or forwarded from the root package.
- You may organize implementation across root-level files by functional area
  (for example, lexing, parsing, semantic analysis, JSON encoding, and types).
- If you create subdirectories as separate MoonBit packages, wire them through
  package configuration and keep root-package implementations, `pub using`
  re-exports, or forwarding functions so the required root `@c99` APIs remain
  available.
- Group related functionality together
- Avoid dumping all code in the root directory

**File Size Limits**:
- Please try to keep each file to at most **1000 lines of core code** (excluding blank lines and comments)
- Split large modules into focused, single-responsibility files
- Use meaningful file names that reflect their purpose

**Readability**:
- Clear, descriptive function and variable names
- Add comments for complex algorithms or non-obvious logic
- Document public APIs and key data structures
- Keep functions focused (prefer multiple small functions over large monolithic ones)

**Code Structure**:
- Logical separation of concerns (lexing → parsing → semantic analysis → output)
- Minimize coupling between modules
- Use appropriate abstractions (types, enums, structs)
- Avoid global mutable state

**Example directory structure**:
```
c99/
├── moon.mod
├── moon.pkg
├── c99_spec.mbt           # API declarations (do not modify)
├── c99.mbt                # Main entry point
├── lexer/
│   ├── token.mbt
│   └── lexer.mbt
├── parser/
│   ├── ast.mbt
│   └── parser.mbt
├── semantic/
│   ├── scope.mbt
│   └── typing.mbt
├── json/
│   └── encoder.mbt
└── types/
    ├── ast.mbt
    └── error.mbt
```

These standards ensure your code is maintainable, understandable, and follows professional software engineering practices.

## Documentation

**Write a comprehensive README.md**:

Your implementation must include a `README.md` file that documents:

- **Project overview**: What this parser implements and its purpose
- **Architecture**: High-level design decisions and module organization
- **Implementation approach**: Key algorithms, data structures, and parsing strategy
- **Usage examples**: How to use the API (parsing code, generating JSON)
- **Testing**: How to run tests and interpret results
- **Design decisions**: Rationale for important technical choices

The README should be written **based on your actual implementation** - describe the code you built, not generic information from specifications. It should help future developers understand your codebase quickly.

## External references

This environment has public network access. You may consult C99 documentation,
discussions, and other references online, but treat the vendored spec files in
`specs/` as the authoritative baseline for behavior in this task.

You must not consult any MoonBit implementations online; the task should be completed using only your own knowledge.
