## Goal

Implement a MoonBit **HPACK encoder/decoder** compatible with RFC 7541 and this
repository’s test suite. The authoritative references are vendored in:

- `specs/rfc7541.txt`
- `specs/hpack.md`
- `specs/README.md`

## What This Task Is Really About

This is an exercise in implementing a **real compression format**:

- integer decoding/encoding
- Huffman decoding/encoding
- static and dynamic table behavior
- deterministic encoding choices that match fixture expectations

Avoid hardcoding: tests cover many header blocks and invalid encodings.

## Approach

Build incrementally:

1. Integer coding per RFC 7541.
2. Huffman coding (including invalid encodings).
3. Dynamic table implementation with correct eviction and size accounting.
4. Decoder for all representation types and correct error reporting.
5. Encoder that follows the greedy matching strategy required by fixtures.

Run tests frequently while adding features.

Important: The core logic must be implemented in MoonBit.

## Scope

In scope for this suite:

- `Decoder::decode` for header blocks
- `Encoder::encode` (and related helpers) for deterministic fixture outputs
- Error behavior per `HpackError`
- JSON inspection helper `headers_to_test_json`

Repo-specific note (important):

- Encoder behavior must be deterministic and match the suite’s greedy strategy;
  this is part of the observable contract.

Out of scope (not required by current tests):

- Integrating into a full HTTP/2 stack

## Required API

Complete the declarations in `hpack_spec.mbt`.

Implementation notes:


- You can **freely decide** the project structure (modules/files/directories)
  and any internal data structures.
- Do **not** modify the following files:
  - `hpack_spec.mbt` - API specification
  - `specs/` folder - Reference documents and fixtures
  - Provided `*_test.mbt` files - Test fixtures
- Implement the required declarations by adding new `.mbt` files as needed.
- **You may add additional test files** (e.g., xxx_test.mbt) if needed for testing and maintenance purposes

Required entry points:

- `@hpack.Decoder::new(max_table_size? : Int) -> Decoder`
- `@hpack.Decoder::decode(self : Decoder, data : BytesView) -> Array[HeaderField] raise HpackError`
- `@hpack.Encoder::new(max_table_size? : Int, use_huffman? : Bool) -> Encoder`
- `@hpack.Encoder::encode(self : Encoder, headers : Array[HeaderField]) -> Bytes`
- `@hpack.Encoder::encode_to(self : Encoder, buf : @buffer.Buffer, headers : Array[HeaderField]) -> Unit`
- `@hpack.Encoder::encode_without_indexing(self : Encoder, header : HeaderField) -> Bytes`
- `@hpack.Encoder::encode_without_indexing_to(self : Encoder, buf : @buffer.Buffer, header : HeaderField) -> Unit`
- `@hpack.Encoder::encode_never_indexed(self : Encoder, header : HeaderField) -> Bytes`
- `@hpack.Encoder::encode_never_indexed_to(self : Encoder, buf : @buffer.Buffer, header : HeaderField) -> Unit`
- `@hpack.Encoder::set_max_size(self : Encoder, new_size : Int) -> Unit`
- `@hpack.headers_to_test_json(headers : Array[HeaderField]) -> Json`

## Behavioral rules

- Static table has 61 entries (RFC 7541 Appendix A).
- Dynamic table entry size is `name.len + value.len + 32` (RFC 7541 §4.1).
- Must raise the correct `HpackError` variants on malformed input.
- Encoder must follow the greedy matching strategy described in `hpack_spec.mbt`.

## Test execution

```bash
moon test
```

Use `moon test --update` only if you intentionally change snapshots.


## Constraints

### 1. Test Requirements

Implement the complete documented HPACK behavior, not only the examples
exercised by the provided tests. Run `moon test` frequently and keep iterating
until it passes. Do not hardcode fixture inputs or expected outputs; implement
the codec for arbitrary inputs within the supported subset. When the
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
- Solutions must be real encoders/decoders, not test-specific lookup tables
- No hardcoded mappings derived from test fixtures
- Implementation should work for arbitrary header blocks within the supported subset

### 3. Software Engineering Standards

**Modularity and Organization**:
- The required declarations in `hpack_spec.mbt` belong to the root `hpack`
  package. Tests call root-package APIs such as `@hpack.Decoder::decode`, so
  those declarations must be implemented or forwarded from the root package.
- You may organize implementation across root-level files by functional area
  (for example, integer coding, Huffman coding, table state, and encoding).
- If you create subdirectories as separate MoonBit packages, wire them through
  package configuration and keep root-package implementations, `pub using`
  re-exports, or forwarding functions so the required root `@hpack` APIs remain
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
- Logical separation of concerns (coding → table state → encode/decode)
- Minimize coupling between modules
- Use appropriate abstractions (types, enums, structs)
- Avoid global mutable state

**Example directory structure**:
```
hpack/
├── moon.mod
├── moon.pkg
├── hpack_spec.mbt         # API declarations (do not modify)
├── hpack.mbt              # Main entry point
├── integer/
│   └── int.mbt
├── huffman/
│   ├── tables.mbt
│   └── codec.mbt
├── table/
│   ├── static.mbt
│   └── dynamic.mbt
├── decoder/
│   └── decode.mbt
├── encoder/
│   └── encode.mbt
└── types/
    ├── header.mbt
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

This environment has public network access. You may consult RFC 7541 and HPACK
resources online, but treat the vendored spec files in `specs/` as the
authoritative baseline for behavior in this task.
