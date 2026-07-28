## Goal

Implement a MoonBit **TOML parser** that is compatible with the TOML spec and
this repository’s test suite. The authoritative upstream specs are vendored in:

- `specs/toml.md`
- `specs/v1.0.0.md`
- `specs/v1.1.0.md`

## What This Task Is Really About

This is an exercise in building a **real parser** for a real data format.
The goal is to write code that can correctly parse TOML documents in general —
not to hardcode behaviors for specific test strings.

A proper implementation will have:

- A **lexer** that tokenizes TOML (strings, numbers, punctuation, comments, etc.)
- A **parser** that builds a structured document representation (tables, arrays,
  key paths)
- A **semantic layer** that applies TOML’s structural rules (tables vs dotted
  keys vs arrays-of-tables) and produces a deterministic `Toml` value

**Important mindset**: If the test suite were regenerated with different literal
values, different key names, or different whitespace/comment placement, your
implementation should still pass. If it wouldn’t, you haven’t built a parser —
you’ve built a lookup table.

## Approach

Build incrementally:

1. **Lexing**: identifiers/keys, strings, numbers, punctuation, comments,
   newlines (LF/CRLF), whitespace.
2. **Parsing values**: strings, integers, floats, bools, datetimes, arrays,
   inline tables.
3. **Parsing statements**: key/value pairs, dotted keys, table headers, and
   array-of-tables.
4. **Structural checks**: detect conflicts/redefinitions required by the invalid
   tests.
5. **JSON encoding**: implement `Toml::to_test_json()` exactly as specified in
   `toml_spec.mbt` so snapshot tests match.

Run tests frequently while adding features.

Important: The core logic must be implemented in MoonBit.

## Scope

In scope for this parser implementation:

- TOML document parsing with:
  - key/value pairs
  - bare keys, quoted keys, dotted keys
  - tables `[a]` and nested tables `[a.b]`
  - array-of-tables `[[arr]]`
  - comments (`# ...`) and flexible whitespace
  - LF and CRLF newlines
- Values (as used by tests and required by `Toml::to_test_json()`):
  - strings (basic, literal, multiline variants used by tests)
  - integers (decimal, binary/octal/hex, underscores)
  - floats (exponent forms, special values if present in fixtures)
  - bools
  - datetimes:
    - offset datetime (`datetime`)
    - local datetime (`datetime-local`)
    - local date (`date-local`)
    - local time (`time-local`)
  - arrays (including nested arrays)
  - inline tables (where covered by tests)

Repo-specific note (important):

- Upstream TOML requires arrays to be homogeneous.
- **This repository’s tests accept heterogeneous arrays** (e.g. arrays mixing
  ints/floats/nested arrays). Your parser must accept them and encode each
  element with its own `"type"` tag in JSON.

Out of scope (not required by current tests):

- Full roundtrip formatting preservation (comments/whitespace/layout).
- Providing a full TOML serializer (only `to_test_json` is required by tests).

## Required API

Complete the declarations in `toml_spec.mbt`.

Implementation notes:

- You can **freely decide** the project structure (modules/files/directories),
  the parsing strategy, and any internal data structures.
- Do **not** modify the following files:
  - `toml_spec.mbt` - API specification
  - `specs/` folder - TOML specification documents
  - Provided `*_test.mbt` files - Test fixtures
- Implement the required declarations by adding new `.mbt` files as needed.
- **You may add additional test files** (e.g., `xxx_test.mbt`) if needed for testing and maintenance purposes:
  - Create test files to validate edge cases
  - Derive test scenarios from `specs/toml.md`, `specs/v1.0.0.md`, `specs/v1.1.0.md`
  - All added tests must remain faithful to the TOML spec versions referenced by this repo
  - Additional tests help ensure comprehensive spec compliance beyond provided fixtures

Required entry points:

- `@toml.parse(input : StringView) -> Result[Toml, ParseError]`
- `@toml.ParseError::to_string(self) -> String`
- `@toml.Toml::to_test_json(self) -> Json`

## Behavioral rules

- Follow TOML v1.0.0 and the relevant v1.1.0 behaviors covered by tests.
- Preserve key case-sensitivity.
- Treat comments as starting with `#` outside strings only.
- Handle CRLF and LF consistently.
- Enforce structural conflicts as required by invalid tests (duplicate keys,
  redefining tables, invalid array/table mixing, etc.).
- `Toml::to_test_json()` must match the exact JSON encoding contract in
  `toml_spec.mbt`:
  - scalars as `{ "type": "...", "value": "..." }`
  - tables as JSON objects
  - arrays as JSON arrays
  - the only JSON value kinds used are objects/arrays/strings

## Test execution

```bash
moon test
```

Use `moon test --update` only if you intentionally change snapshots.


## Constraints

### 1. Test Requirements

Implement the complete documented TOML behavior, not only the examples
exercised by the provided tests. Run `moon test` frequently and keep iterating
until it passes. Do not hardcode fixture inputs or expected outputs; build a
general parser for arbitrary inputs within the supported TOML versions. When
the implementation and verification are complete, finish the task.

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
- Implementation should work for arbitrary valid TOML inputs

### 3. Software Engineering Standards

**Modularity and Organization**:
- The required declarations in `toml_spec.mbt` belong to the root `toml`
  package. Tests call root-package APIs such as `@toml.parse`, so those
  declarations must be implemented or forwarded from the root package.
- You may organize implementation across root-level files by functional area
  (for example, lexing, parsing, semantic validation, and JSON encoding).
- If you create subdirectories as separate MoonBit packages, wire them through
  package configuration and keep root-package implementations, `pub using`
  re-exports, or forwarding functions so the required root `@toml` APIs remain
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
toml/
├── moon.mod
├── moon.pkg
├── toml_spec.mbt          # API declarations (do not modify)
├── toml.mbt               # Main entry point
├── lexer/
│   ├── token.mbt
│   └── lexer.mbt
├── parser/
│   ├── ast.mbt
│   └── parser.mbt
├── semantic/
│   ├── builder.mbt
│   └── validator.mbt
├── json/
│   └── encoder.mbt
└── types/
    ├── value.mbt
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

This environment has public network access. You may consult upstream TOML
documentation, discussions, and other references online, but treat the vendored
spec files in `specs/` as the authoritative baseline for behavior in this task.
