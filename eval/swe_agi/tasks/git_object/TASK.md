## Goal

Implement a MoonBit **git loose object parser** that can decode zlib-compressed
git objects and produce a stable JSON representation matching this repository’s
test suite. The authoritative repo references are vendored in:

- `specs/git_object.md`
- `specs/README.md`

## What This Task Is Really About

This is an exercise in implementing a **real binary/text format combination**:

- zlib decoding for loose objects
- parsing the `"type size\\0"` header and validating sizes
- decoding object payloads (blob/tree/commit/tag) as required by tests
- producing deterministic JSON snapshots

Avoid hardcoding: fixtures cover multiple object kinds and malformed cases.

## Approach

Build incrementally:

1. **Zlib decoding** and error reporting.
2. **Header parsing**: `kind`, `size`, NUL terminator, size validation.
3. **Payload parsing** per kind (tree entries, commit headers, tag structure).
4. **OID verification**: compute SHA-1 when `expected_oid` is provided.
5. **JSON encoding**: implement `GitObject::to_json()` to match snapshots.

Run tests frequently while adding features.

Important: The core logic must be implemented in MoonBit.

## Scope

In scope for this parser implementation:

- Parsing a complete loose object from zlib bytes
- Validating the declared size matches payload length
- Computing SHA-1 and setting `sha1_ok` when requested
- Producing deterministic JSON via `GitObject::to_json()`

Repo-specific note (important):

- Tests treat `GitObject::to_json()` output as the conformance oracle; match it exactly.

Out of scope (not required by current tests):

- Packfile parsing
- Full ref/database plumbing (fetch, index, etc.)

## Required API

Complete the declarations in `git_object_spec.mbt`.

Implementation notes:


- You can **freely decide** the project structure (modules/files/directories)
  and any internal data structures.
- Do **not** modify the following files:
  - `git_object_spec.mbt` - API specification
  - `specs/` folder - Reference documents and helper sources
  - Provided `*_test.mbt` files and fixture directories - Test fixtures
- Implement the required declarations by adding new `.mbt` files as needed.
- **You may add additional test files** (e.g., xxx_test.mbt) if needed for testing and maintenance purposes

Required entry points:

- `@git_object.parse_object_bytes(bytes : Bytes, expected_oid? : String) -> GitObject raise GitObjectError`
- `@git_object.GitObject::to_json(self : GitObject) -> Json`

## Behavioral rules

- Input bytes must be treated as a complete loose object zlib stream.
- Header parsing must validate the `"type size\\0"` format and size consistency.
- When `expected_oid` is provided, compute SHA-1 and set `sha1_ok` accordingly.
- Raise the correct `GitObjectError` variants on malformed input.

## Test execution

```bash
moon test
```

Use `moon test --update` only if you intentionally change snapshots.


## Constraints

### 1. Test Requirements

Implement the complete documented loose-object behavior, not only the examples
exercised by the provided tests. Run `moon test` frequently and keep iterating
until it passes. Do not hardcode fixture inputs or expected outputs; build a
general zlib decoder, object parser, verifier, and serializer for arbitrary
loose objects within the supported kinds. When the implementation and
verification are complete, finish the task.

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
- Solutions must be real parsers/codecs, not test-specific lookup tables
- No hardcoded mappings derived from test fixtures
- Implementation should work for arbitrary loose objects within the supported kinds

### 3. Software Engineering Standards

**Modularity and Organization**:
- The required declarations in `git_object_spec.mbt` belong to the root
  `git_object` package. Tests call root-package APIs such as
  `@git_object.parse_object_bytes`, so those declarations must be implemented
  or forwarded from the root package.
- You may organize implementation across root-level files by functional area
  (for example, zlib decoding, object parsing, SHA-1, JSON encoding, and types).
- If you create subdirectories as separate MoonBit packages, wire them through
  package configuration and keep root-package implementations, `pub using`
  re-exports, or forwarding functions so the required root `@git_object` APIs
  remain available.
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
- Logical separation of concerns (decode → parse → validate → output)
- Minimize coupling between modules
- Use appropriate abstractions (types, enums, structs)
- Avoid global mutable state

**Example directory structure**:
```
git_object/
├── moon.mod
├── moon.pkg
├── git_object_spec.mbt    # API declarations (do not modify)
├── git_object.mbt         # Main entry point
├── zlib/
│   └── decode.mbt
├── parser/
│   ├── header.mbt
│   ├── tree.mbt
│   ├── commit.mbt
│   └── tag.mbt
├── hash/
│   └── sha1.mbt
├── json/
│   └── encoder.mbt
└── types/
    ├── object.mbt
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

This environment has public network access. You may consult Git object format
references online, but treat the vendored spec files in `specs/` as the
authoritative baseline for behavior in this task.
