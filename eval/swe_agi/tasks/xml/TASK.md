## Goal

Implement a MoonBit **streaming XML parser and writer** that matches this
repository’s test suite and the repo’s XML contract. The authoritative repo
reference is vendored in:

- `specs/xml.md`

## What This Task Is Really About

This is an exercise in implementing a **real streaming parser** (pull-parser model):

- read XML events one at a time from a reader
- handle entities, attributes, namespaces, and error cases as required by tests
- provide a writer and JSON conversion helpers used by the suite

Avoid hardcoding: fixtures cover many XML forms and invalid inputs.

## Approach

Build incrementally:

1. Tokenization and event model (`Event`) for start/end/text/cdata/comment, etc.
2. Streaming reader that tracks line/column and returns events deterministically.
3. Entity and attribute parsing rules required by tests.
4. Writer/serialization helpers required by the suite.
5. JSON conversion helpers used by snapshot tests.

Run tests frequently while adding features.

Important: The core logic must be implemented in MoonBit.

## Scope

In scope for this suite:

- Reader API (`Reader::from_string`, `read_event`, `read_events_until_eof`, etc.)
- Writer API for generating XML output as required by tests
- Error behavior via `XmlError` variants

Repo-specific note (important):

- This is a streaming API; correctness includes event ordering and deterministic reader state progression.

Out of scope (not required by current tests):

- Full validating DTD/schema support

## Required API

Complete the declarations in `xml_spec.mbt`.

Implementation notes:

- You can **freely decide** the project structure (modules/files/directories),
  the parsing strategy, and any internal data structures.
- Do **not** modify the following files:
  - `xml_spec.mbt` - API specification
  - `specs/` folder - Reference documents and fixtures
  - Provided `*_test.mbt` files - Test fixtures
- Implement the required declarations by adding new `.mbt` files as needed.
- **You may add additional test files** (e.g., xxx_test.mbt) if needed for testing and maintenance purposes

Required entry points:

- All `declare` declarations in `xml_spec.mbt` (Reader/Writer APIs, event types, errors, and JSON helpers)

## Behavioral rules

- Parsing must be streaming and deterministic.
- Line/column tracking must match the suite’s expectations.
- Must raise the correct `XmlError` variants on malformed input.
- Writer output must match required canonical forms where asserted by tests.

## Test execution

```bash
moon test
```

Use `moon test --update` only if you intentionally change snapshots.


## Constraints

### 1. Test Requirements

Implement the complete documented XML behavior, not only the examples exercised
by the provided tests. Run `moon test` frequently and keep iterating until it
passes. Do not hardcode fixture inputs or expected outputs; build a general
streaming parser and writer for arbitrary XML within the supported subset.
When the implementation and verification are complete, finish the task.

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
- Solutions must be real parsers/writers, not test-specific lookup tables
- No hardcoded mappings derived from test fixtures
- Implementation should work for arbitrary XML inputs within the supported subset

### 3. Software Engineering Standards

**Modularity and Organization**:
- **Use subdirectories** to organize code by functional area:
  - `reader/` - Streaming reader and tokenization
  - `events/` - Event model and conversions
  - `writer/` - Writer/serialization helpers
  - `types/` - Core data structures and errors
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
- Logical separation of concerns (tokenize → read events → write)
- Minimize coupling between modules
- Use appropriate abstractions (types, enums, structs)
- Avoid global mutable state

**Example directory structure**:
```
xml/
├── moon.mod
├── moon.pkg
├── xml_spec.mbt           # API declarations (do not modify)
├── xml.mbt                # Main entry point
├── reader/
│   └── reader.mbt
├── events/
│   └── event.mbt
├── writer/
│   └── writer.mbt
└── types/
    ├── error.mbt
    └── token.mbt
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

This environment has public network access. You may consult XML references
online, but treat the vendored spec files in `specs/` as the authoritative
baseline for behavior in this task.
