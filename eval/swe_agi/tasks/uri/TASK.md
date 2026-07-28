## Goal

Implement a MoonBit **RFC 3986 URI parser and resolver** that passes this
repository’s RFC-derived test suite. The authoritative references are vendored in:

- `specs/rfc3986.txt`
- `specs/uri.md`

## What This Task Is Really About

This is an exercise in building a **real RFC-compliant parser**:

- Parse generic URI syntax into components (scheme, authority, path, query, fragment).
- Implement reference resolution (`Uri::resolve`) including dot-segment removal.
- Serialize back to string deterministically (`Uri::to_string`).

Avoid hardcoding the RFC examples: implement the general algorithm (especially
RFC 3986 §5.2 and §5.2.4).

## Approach

Build incrementally:

1. Parse absolute URIs and expose component getters.
2. Implement `to_string` serialization.
3. Implement `resolve(base, reference)` per RFC 3986 §5.2.
4. Implement dot-segment removal per RFC 3986 §5.2.4.
5. Ensure behavior matches the RFC examples exercised by tests.

Run tests frequently while adding features.

Important: The core logic must be implemented in MoonBit.

## Scope

In scope for this suite:

- `Uri::parse(input : String) -> Uri raise`
- Component getters:
  - `scheme`, `userinfo`, `host`, `port`, `path`, `query`, `fragment`
- `Uri::resolve(base : Uri, reference : String) -> Uri raise`
- `Uri::to_string(self : Uri) -> String`

Repo-specific note (important):

- The suite validates RFC 3986 resolution behavior; implement the algorithm, not a URI string splitter.

Out of scope (not required by current tests):

- Full percent-decoding/normalization beyond correct splitting/serialization

## Required API

Complete the declarations in `rfc3986_spec.mbt`.

Implementation notes:

- You can **freely decide** the project structure (modules/files/directories),
  the parsing strategy, and any internal data structures.
- Do **not** modify the following files:
  - `rfc3986_spec.mbt` - API specification
  - `specs/` folder - Reference documents
  - Provided `*_test.mbt` files - Test fixtures
- Implement the required declarations by adding new `.mbt` files as needed.
- **You may add additional test files** (e.g., xxx_test.mbt) if needed for testing and maintenance purposes

Required entry points:

- `@uri.Uri::parse(input : String) -> Uri raise`
- `@uri.Uri::resolve(base : Uri, reference : String) -> Uri raise`
- `@uri.Uri::to_string(self : Uri) -> String`

## Behavioral rules

- Follow RFC 3986 for parsing and resolution.
- Do not hardcode tables or special-case only the provided examples.
- Behavior must be deterministic.

## Test execution

```bash
moon test
```

Use `moon test --update` only if you intentionally change snapshots.


## Constraints

### 1. Test Requirements

Implement the complete documented RFC behavior, not only the examples exercised
by the provided tests. Run `moon test` frequently and keep iterating until it
passes. Do not hardcode fixture inputs or expected outputs; implement the RFC
algorithms for arbitrary inputs within the supported grammar. When the
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
- Solutions must be real parsers/algorithms, not test-specific lookup tables
- No hardcoded mappings derived from test fixtures
- Implementation should work for arbitrary URIs within the supported grammar

### 3. Software Engineering Standards

**Modularity and Organization**:
- The required declarations in `rfc3986_spec.mbt` belong to the root `uri`
  package. Tests call root-package APIs such as `@uri.Uri::parse`, so those
  declarations must be implemented or forwarded from the root package.
- You may organize implementation across root-level files by functional area
  (for example, parsing, resolution, serialization, and data types).
- If you create subdirectories as separate MoonBit packages, wire them through
  package configuration and keep root-package implementations, `pub using`
  re-exports, or forwarding functions so the required root `@uri` APIs remain
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
- Logical separation of concerns (parsing → resolution → serialization)
- Minimize coupling between modules
- Use appropriate abstractions (types, enums, structs)
- Avoid global mutable state

**Example directory structure**:
```
uri/
├── moon.mod
├── moon.pkg
├── rfc3986_spec.mbt       # API declarations (do not modify)
├── uri.mbt                # Main entry point
├── parser/
│   └── parser.mbt
├── resolve/
│   └── resolve.mbt
├── serialize/
│   └── to_string.mbt
└── types/
    ├── uri.mbt
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

This environment has public network access. You may consult RFC 3986 resources
online, but treat the vendored spec files in `specs/` as the authoritative
baseline for behavior in this task.
