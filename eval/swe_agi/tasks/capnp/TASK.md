## Goal

Implement a MoonBit **Cap’n Proto** low-level encoder/decoder that can:

- decode messages from bytes using the Cap’n Proto wire format
- traverse pointers to structs/lists safely and correctly
- encode/write messages back to bytes matching fixture expectations

The authoritative references are vendored in:

- `specs/capnp.md`
- `specs/README.md`

## What This Task Is Really About

This is an exercise in implementing a **real binary wire format**:

- segment table framing (unpacked messages)
- pointer decoding (struct/list/far pointers)
- alignment and bounds checking
- deterministic encoding that matches fixture expectations

Avoid hardcoding: fixtures are generated and cover many layouts.

## Approach

Build incrementally:

1. Segment table parsing and root pointer access.
2. Struct pointer decoding and primitive field reads.
3. List pointer decoding (all element size classes used by fixtures).
4. Far pointer/landing pad support (multi-segment cases).
5. Writer allocation model and serialization back to bytes.
6. Traversal/bounds safety checks required by tests.

Run tests frequently while adding features.

Important: The core logic must be implemented in MoonBit.

## Scope

In scope for this suite (as exercised by tests):

- Decoding messages from bytes into a decoder and reading structs/lists
- Encoding/writing messages into bytes with correct framing/pointers
- Safety checks (bounds, traversal limits) as tested

Repo-specific note (important):

- Safety checks are part of the contract; out-of-bounds traversal must raise the correct errors, not panic.

Out of scope (not required by current tests):

- Packed encoding
- Schema compilation/codegen
- RPC/capabilities

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

- All `declare` declarations in `decoder_spec.mbt`, `encoder_spec.mbt`, `segment_spec.mbt`, `pointer_spec.mbt`, and `errors_spec.mbt`

## Behavioral rules

- Must correctly parse message framing and segment tables.
- Must decode pointers (struct/list/far) with correct bounds checks.
- Must enforce traversal limits when provided.
- Encoding must be deterministic and match fixture expectations.

## Test execution

```bash
moon test
```

Use `moon test --update` only if you intentionally change snapshots.


## Constraints

### 1. Test Requirements

Implement the complete documented Cap'n Proto subset, not only the examples
exercised by the provided tests. Run `moon test` frequently and keep iterating
until it passes. Do not hardcode fixture inputs or expected outputs; build a
general decoder and writer for arbitrary messages within the supported wire
format. When the implementation and verification are complete, finish the task.

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
- Implementation should work for arbitrary messages within the supported subset

### 3. Software Engineering Standards

**Modularity and Organization**:
- The required declarations in the `*_spec.mbt` files belong to the root
  `capnp` package. Tests call root-package APIs, so those declarations must be
  implemented or forwarded from the root package.
- You may organize implementation across root-level files by functional area
  (for example, segment framing, decoding, encoding, and core types).
- If you create subdirectories as separate MoonBit packages, wire them through
  package configuration and keep root-package implementations, `pub using`
  re-exports, or forwarding functions so the required root `@capnp` APIs remain
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
- Logical separation of concerns (framing → decode/traverse → encode/write)
- Minimize coupling between modules
- Use appropriate abstractions (types, enums, structs)
- Avoid global mutable state

**Example directory structure**:
```
capnp/
├── moon.mod
├── moon.pkg
├── decoder_spec.mbt       # API declarations (do not modify)
├── encoder_spec.mbt       # API declarations (do not modify)
├── segment_spec.mbt       # API declarations (do not modify)
├── capnp.mbt              # Main entry point
├── segment/
│   └── segment.mbt
├── decode/
│   └── decoder.mbt
├── encode/
│   └── encoder.mbt
└── types/
    ├── pointer.mbt
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

This environment has public network access. You may consult Cap’n Proto wire
format references online, but treat the vendored spec files in `specs/` as the
authoritative baseline for behavior in this task.
