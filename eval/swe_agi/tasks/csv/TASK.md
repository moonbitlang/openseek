## Goal

Implement a MoonBit **CSV parser** that is compatible with this repository’s
test suite and the RFC 4180 model (with a few explicit repo-specific choices).
The authoritative references are vendored in:

- `specs/rfc4180.txt`
- `specs/csv.md`

## What This Task Is Really About

This is an exercise in building a **real parser** for a real data format.
The goal is to parse CSV inputs correctly in general — not to hardcode behaviors
for specific test strings.

A proper implementation will have:

- A state machine / lexer that handles commas, quotes, and record boundaries
- A parser that produces a structured `Csv` value
- A deterministic JSON encoding layer via `Csv::to_test_json()` used by tests

**Important mindset**: If the test suite were regenerated with different literal
values or different newline/quoting placement, your implementation should still
pass. If it wouldn’t, you haven’t built a parser — you’ve built a lookup table.

## Approach

Build incrementally:

1. **Record splitting**: handle LF/CRLF/CR and empty records.
2. **Unquoted fields**: comma separation and empty fields.
3. **Quoted fields**: `""` escaping and commas/newlines inside quotes.
4. **Error detection**: reject malformed quoting patterns required by invalid tests.
5. **JSON encoding**: implement `Csv::to_test_json()` exactly as specified in
   `csv_spec.mbt` so snapshot tests match.

Run tests frequently while adding features.

Important: The core logic must be implemented in MoonBit.

## Scope

In scope for this parser implementation:

- Comma-separated fields with:
  - empty fields
  - quoted fields (`"..."`)
  - escaped quotes inside quoted fields (`""`)
  - commas/newlines inside quoted fields
- Line endings:
  - LF (`\n`)
  - CRLF (`\r\n`)
  - CR (`\r`) (suite-specific tolerance)
- Structural constraints required by this suite’s invalid tests (malformed quotes, etc.)

Repo-specific note (important):

- This suite tolerates CR line endings in addition to LF/CRLF; follow the fixtures.

Out of scope (not required by current tests):

- Dialect options (custom separators, trimming rules, etc.)
- Type inference (everything is a string)

## Required API

Complete the declarations in `csv_spec.mbt`.

Implementation notes:

- You can **freely decide** the project structure (modules/files/directories),
  the parsing strategy, and any internal data structures.
- Do **not** modify the following files:
  - `csv_spec.mbt` - API specification
  - `specs/` folder - Reference documents
  - `*_pub_test.mbt` - Public test files (`csv_valid_pub_test.mbt`, `csv_invalid_pub_test.mbt`)
  - `*_priv_test.mbt` - Private test files (`csv_valid_priv_test.mbt`, `csv_invalid_priv_test.mbt`)
- Implement the required declarations by adding new `.mbt` files as needed.
- **You may add additional test files** (e.g., xxx_test.mbt) if needed for testing and maintenance purposes
  - Create additional test files (e.g., `xxx_test.mbt`) to validate edge cases
  - Derive test scenarios from `specs/rfc4180.txt` and `specs/csv.md`
  - All added tests must remain faithful to the CSV/RFC 4180 behaviors used by this repo

Required entry points:

- `@csv.parse(input : StringView) -> Result[Csv, ParseError]`
- `@csv.ParseError::to_string(self) -> String`
- `@csv.Csv::to_test_json(self) -> Json`

## Behavioral rules

- Accept LF/CRLF consistently and tolerate CR as specified by this suite.
- Treat comments as ordinary text (CSV has no comments in this suite).
- Reject malformed quoting patterns as invalid tests require:
  - unterminated quotes
  - `"` inside unquoted fields
  - non-separator text after a closing quote
  - backslash-escaped quotes (`\"`) are not supported
- `Csv::to_test_json()` must match the encoding contract in `csv_spec.mbt`.

## Test execution

```bash
moon test
```

Use `moon test --update` only if you intentionally change snapshots.


## Constraints

### 1. Test Requirements

**All tests must pass for task completion**:

The model should keep running until all tests pass.

- **Public tests** (`*_pub_test.mbt`): 10 cases, visible in this repository for development and debugging
- **Private tests** (`*_priv_test.mbt`): 88 additional cases, vendored as ordinary files in this local task and run by `moon test`

**CRITICAL - Full Suite Evaluation**:

Passing only the public tests is **INSUFFICIENT** and will result in task failure. The task is complete **only when both public and private test suites in this directory pass**.

**Why Private Tests Matter**:
- **Coverage**: Private tests represent 90% of the total evaluation - they are the primary measure of success
- **Comprehensiveness**: Validate full CSV behavior compliance, including edge cases, corner cases, and subtle semantic rules not exposed in public tests
- **Real-world scenarios**: Test combinations and patterns that occur in actual CSV files but may not be obvious from the spec
- **Implementation integrity**: Even though these tests are visible here, the goal is a genuine parser, not a lookup table for fixture outputs

**Evaluation Process**:

Make all tests pass locally by running `moon test` in this directory. Iterate
until they pass, then `finish`.

There is **no submission step and no evaluation server** in this environment.
`moon test` is the grading command for this vendored native workflow.

Because the private tests (~90% of the suite) decide success, a genuine,
general implementation is essential: do **not** hardcode or memorize responses
to the fixtures — build a real parser/state machine that works for arbitrary
inputs within the supported dialect.

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
- Solutions must be real parsers/state machines, not test-specific lookup tables
- No hardcoded mappings derived from test fixtures
- Implementation should work for arbitrary CSV inputs within the supported dialect

### 3. Software Engineering Standards

**Modularity and Organization**:
- The required declarations in `csv_spec.mbt` belong to the root `csv`
  package. Tests call root-package APIs such as `@csv.parse`, so those
  declarations must be implemented or forwarded from the root package.
- You may organize implementation across root-level files by functional area
  (for example, scanning, parsing, JSON encoding, and data types).
- If you create subdirectories as separate MoonBit packages, wire them through
  package configuration and keep root-package implementations, `pub using`
  re-exports, or forwarding functions so the required root `@csv` APIs remain
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
csv/
├── moon.mod
├── moon.pkg
├── csv_spec.mbt           # API declarations (do not modify)
├── csv.mbt                # Main entry point
├── lexer/
│   └── lexer.mbt
├── parser/
│   └── parser.mbt
├── json/
│   └── encoder.mbt
└── types/
    ├── csv.mbt
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

This environment has public network access. You may consult CSV documentation
and discussions online, but treat the vendored spec files in `specs/` as the
authoritative baseline for behavior in this task.
