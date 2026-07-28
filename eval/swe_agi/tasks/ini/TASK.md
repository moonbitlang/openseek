## Goal

Implement a MoonBit **INI parser** compatible with this repository’s INI dialect
as defined by the test suite. The authoritative repo reference is vendored in:

- `specs/ini.md`

## What This Task Is Really About

This is an exercise in building a **real line-oriented parser**:

- Tokenize/parse section headers and key/value lines
- Apply comment and quoting rules consistently
- Produce a structured `Ini` value and a stable JSON encoding for tests

**Important mindset**: Don’t hardcode special cases for particular test strings.
If tests were regenerated with different keys/values, your parser should still
work.

## Approach

Build incrementally:

1. Line splitting (LF/CRLF) and blank/comment lines.
2. Global key/value pairs and section headers.
3. Key/value separators (`=` and `:`) and whitespace handling.
4. Quoted values and inline comment rules.
5. Multiline continuation rules (backslash continuation).
6. Implement `Ini::to_test_json()` as the test oracle.

Run tests frequently while adding features.

Important: The core logic must be implemented in MoonBit.

## Scope

In scope for this parser implementation (as exercised by tests):

- Sections and key/value pairs with the suite’s separators and whitespace rules
- Comments (`;` and `#`) including inline comment behavior for unquoted values
- Quoted values (single/double) and escapes used by tests
- Multiline values with backslash continuation
- Deterministic JSON encoding via `Ini::to_test_json()`

Repo-specific note (important):

- INI has no single universal standard; the tests and `ini_spec.mbt` define the behavior here.

Out of scope (not required by current tests):

- Supporting every INI dialect option from other ecosystems
- Type inference (all values are strings)

## Required API

Complete the declarations in `ini_spec.mbt`.

Implementation notes:

- You can **freely decide** the project structure (modules/files/directories),
  the parsing strategy, and any internal data structures.
- Do **not** modify the following files:
  - `ini_spec.mbt` - API specification
  - `specs/` folder - Reference documents
  - Provided `*_test.mbt` files - Test fixtures
- Implement the required declarations by adding new `.mbt` files as needed.
- **You may add additional test files** (e.g., xxx_test.mbt) if needed for testing and maintenance purposes

Required entry points:

- `@ini.parse(input : StringView) -> Result[Ini, ParseError]`
- `@ini.ParseError::to_string(self) -> String`
- `@ini.Ini::to_test_json(self) -> Json`

## Behavioral rules

- Global (pre-section) keys belong to a special section `""` in JSON.
- Duplicate keys and section redefinition behaviors must match tests.
- Invalid forms described by the specification and exercised by the provided
  tests must be rejected.
- `Ini::to_test_json()` must match the encoding contract in `ini_spec.mbt`.

## Test execution

```bash
moon test
```

Use `moon test --update` only if you intentionally change snapshots.


## Constraints

### 1. Test Requirements

Implement the complete documented INI behavior, not only the examples exercised
by the provided tests. Run `moon test` frequently and keep iterating until it
passes. Do not hardcode fixture inputs or expected outputs; build a general
parser for arbitrary inputs within the supported dialect. When the
implementation and verification are complete, finish the task.

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
- Implementation should work for arbitrary INI inputs within the supported dialect

### 3. Software Engineering Standards

**Modularity and Organization**:
- The required declarations in `ini_spec.mbt` belong to the root `ini`
  package. Tests call root-package APIs such as `@ini.parse`, so those
  declarations must be implemented or forwarded from the root package.
- You may organize implementation across root-level files by functional area
  (for example, scanning, parsing, JSON encoding, and data types).
- If you create subdirectories as separate MoonBit packages, wire them through
  package configuration and keep root-package implementations, `pub using`
  re-exports, or forwarding functions so the required root `@ini` APIs remain
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
- Logical separation of concerns (scanning → parsing → output)
- Minimize coupling between modules
- Use appropriate abstractions (types, enums, structs)
- Avoid global mutable state

**Example directory structure**:
```
ini/
├── moon.mod
├── moon.pkg
├── ini_spec.mbt           # API declarations (do not modify)
├── ini.mbt                # Main entry point
├── lexer/
│   └── lexer.mbt
├── parser/
│   └── parser.mbt
├── json/
│   └── encoder.mbt
└── types/
    ├── ini.mbt
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

This environment has public network access. You may consult INI dialect
references online, but treat the vendored spec files in `specs/` as the
authoritative baseline for behavior in this task.
