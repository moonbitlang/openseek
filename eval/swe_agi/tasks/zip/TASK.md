## Goal

Implement a MoonBit **ZIP archive parser** that can produce a tolerant metadata
report matching this repository’s snapshots, for both valid and malformed ZIPs.
The authoritative references are vendored in:

- `specs/zip.md`
- `specs/appnote_iz.txt`
- `specs/README.md`

## What This Task Is Really About

This is an exercise in implementing a **real binary container format**:

- parsing local headers and the central directory
- handling encoding rules for filenames (UTF-8 / extra fields / CP437 fallback)
- attempting partial recovery on malformed inputs
- producing deterministic JSON used by snapshot tests

Avoid hardcoding: fixtures include many archives and structural edge cases.

## Approach

Build incrementally:

1. Parse EOCD and central directory structure.
2. Parse central directory entries into `ZipEntry` fields in the expected format.
3. Implement filename decoding rules and extra field handling required by tests.
4. Implement tolerant recovery behavior: keep recoverable entries and set `invalid`.
5. Implement streaming parsing (`parse_stream`) to match `parse_file` as closely as possible.
6. Implement `ZipReport::to_json()` to match fixture JSON exactly.

Run tests frequently while adding features.

Important: The core logic must be implemented in MoonBit.

## Scope

In scope for this suite:

- `parse_file(file, name?) -> ZipReport raise ZipError` (async)
- `parse_stream(reader, name?) -> ZipReport raise ZipError` (async)
- `ZipReport::to_json(self) -> Json` for snapshot testing
- Tolerant parsing that can still report partial metadata on broken archives

Repo-specific note (important):

- The suite expects **tolerant** behavior: do not fail early if partial recovery is possible; set `invalid` instead.

Out of scope (not required by current tests):

- Extracting/decompressing file contents (metadata/report only)

## Required API

Complete the declarations in `zip_spec.mbt`.

Implementation notes:

- You can **freely decide** the project structure (modules/files/directories),
  the parsing strategy, and any internal data structures.
- Do **not** modify the following files:
  - `zip_spec.mbt` - API specification
  - `specs/` folder - Reference documents and fixtures
  - Provided `*_test.mbt` files - Test fixtures
- Implement the required declarations by adding new `.mbt` files as needed.
- **You may add additional test files** (e.g., xxx_test.mbt) if needed for testing and maintenance purposes

Required entry points:

- `@zip.parse_file(file : @fs.File, name? : String) -> ZipReport raise ZipError` (async)
- `@zip.parse_stream(reader : &@io.Reader, name? : String) -> ZipReport raise ZipError` (async)
- `@zip.ZipReport::to_json(self : ZipReport) -> Json`

## Behavioral rules

- Must attempt partial recovery where possible and set `report.invalid` instead of dropping recoverable entries.
- Filename decoding must follow the suite’s rules (UTF-8 flag, Unicode Path extra field, CP437 fallback).
- JSON output must match the generated fixtures exactly.
- Behavior must be deterministic.

## Test execution

```bash
moon test
```

Use `moon test --update` only if you intentionally change snapshots.


## Constraints

### 1. Test Requirements

Implement the complete documented ZIP behavior, not only the examples exercised
by the provided tests. Run `moon test` frequently and keep iterating until it
passes. Do not hardcode fixture inputs or expected outputs; build a general
parser for arbitrary archives within the supported subset. When the
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
- Implementation should work for arbitrary archives within the supported subset

### 3. Software Engineering Standards

**Modularity and Organization**:
- **Use subdirectories** to organize code by functional area:
  - `decode/` - Binary parsing and endian helpers
  - `central/` - Central directory parsing and entry modeling
  - `extras/` - Extra field decoding (Unicode path, etc.)
  - `stream/` - Streaming reader implementation
  - `json/` - JSON encoding for snapshot tests
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
- Logical separation of concerns (decode → parse → recover → output)
- Minimize coupling between modules
- Use appropriate abstractions (types, enums, structs)
- Avoid global mutable state

**Example directory structure**:
```
zip/
├── moon.mod
├── moon.pkg
├── zip_spec.mbt           # API declarations (do not modify)
├── zip.mbt                # Main entry point
├── decode/
│   └── bytes.mbt
├── central/
│   └── central_dir.mbt
├── extras/
│   └── unicode_path.mbt
├── stream/
│   └── stream.mbt
├── json/
│   └── encoder.mbt
└── types/
    ├── report.mbt
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

This environment has public network access. You may consult ZIP format
references online, but treat the vendored spec files in `specs/` as the
authoritative baseline for behavior in this task.
