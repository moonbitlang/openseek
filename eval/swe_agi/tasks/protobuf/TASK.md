## Goal

Implement a MoonBit **streaming protobuf encoder/decoder** that matches the
Protocol Buffers binary wire format and passes this repository’s spec-driven
tests (including chunked/partial read scenarios). The authoritative references
are vendored in:

- `specs/protobuf.md`
- `specs/encoding.md`
- `specs/README.md`

## What This Task Is Really About

This is an exercise in implementing a **real streaming binary codec**:

- varint and zigzag encoding/decoding
- fixed32/fixed64 and float/double little-endian encoding
- length-delimited fields (strings/bytes/embedded/packed)
- correct behavior under **chunked readers** (read() may return partial data)

Avoid hardcoding: tests include many cases and chunking patterns.

## Approach

Build incrementally:

1. Implement varint read/write (with overflow and truncation detection).
2. Implement tag read/write and wire-type dispatch.
3. Implement fixed32/fixed64 and float/double endian correctness.
4. Implement length-delimited reads/writes and UTF-8 string rules.
5. Implement packed repeated field helpers.
6. Harden streaming behavior to work with partial reads.

Run tests frequently while adding features.

Important: The core logic must be implemented in MoonBit.

## Scope

In scope for this suite:

- Reader APIs in `reader_spec.mbt`
- Writer APIs in `writer_spec.mbt`
- Supporting types/utilities in `types_spec.mbt`, `sizeof_spec.mbt`
- Streaming behavior that does not assume a single read fills the buffer

Repo-specific note (important):

- Chunked/partial read behavior is a first-class requirement; treat it as part of correctness, not a performance detail.

Out of scope (not required by current tests):

- `.proto` schema parsing or code generation

## Required API

Complete the declarations in the `*_spec.mbt` files in this directory.

Implementation notes:


- You can **freely decide** the project structure (modules/files/directories)
  and any internal data structures.
- Do **not** modify the following files:
  - `*_spec.mbt` - API specifications
  - `specs/` folder - Reference documents and fixtures
  - `*_test.mbt` - Test files in this directory
- Implement the required declarations by adding new `.mbt` files as needed.
- **You may add additional test files** (e.g., xxx_test.mbt) if needed for testing and maintenance purposes

Required entry points:

- All `declare` declarations in `reader_spec.mbt`, `writer_spec.mbt`, `types_spec.mbt`, and `sizeof_spec.mbt`

## Behavioral rules

- Correctly implement wire types: 0 (varint), 1 (64-bit), 2 (length-delimited), 5 (32-bit).
- Tag = `(field_number << 3) | wire_type`, encoded as varint.
- Zigzag encoding for `sint32`/`sint64`.
- Must correctly handle values split across chunks for reader APIs.
- Raise/return errors for malformed/truncated inputs as required by tests.

## Test execution

```bash
moon test
```

Use `moon test --update` only if you intentionally change snapshots.

## Constraints

### 1. Test Requirements

Implement the complete documented protobuf behavior, not only the examples
exercised by the provided tests. Run `moon test` frequently and keep iterating
until it passes. Do not hardcode fixture values or chunk layouts; build a
general streaming encoder and decoder for arbitrary inputs within the supported
wire-format subset. When implementation and verification are complete, finish
the task.

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
- Solutions must be real encoders/decoders, not test-specific lookup tables
- No hardcoded mappings derived from test fixtures
- Implementation should work for arbitrary inputs within the supported subset

### 3. Software Engineering Standards

**Modularity and Organization**:
- **Use subdirectories** to organize code by functional area:
  - `varint/` - Varint and zigzag coding
  - `reader/` - Streaming reader implementations
  - `writer/` - Writer implementations and helpers
  - `types/` - Scalar wrappers and size computations
  - `wire/` - Tag and wire-type dispatch
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
- Logical separation of concerns (wire coding → streaming IO → typed helpers)
- Minimize coupling between modules
- Use appropriate abstractions (types, enums, structs)
- Avoid global mutable state

**Example directory structure**:
```
protobuf/
├── moon.mod
├── moon.pkg
├── reader_spec.mbt        # API declarations (do not modify)
├── writer_spec.mbt        # API declarations (do not modify)
├── types_spec.mbt         # API declarations (do not modify)
├── protobuf.mbt           # Main entry point
├── varint/
│   └── varint.mbt
├── wire/
│   └── tag.mbt
├── reader/
│   └── read.mbt
├── writer/
│   └── write.mbt
└── types/
    ├── scalar.mbt
    └── sizeof.mbt
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

This environment has public network access. You may consult Protocol Buffers
encoding references online, but treat the vendored spec files in `specs/` as the
authoritative baseline for behavior in this task.
