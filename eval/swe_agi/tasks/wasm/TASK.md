## Goal

Implement a MoonBit **WebAssembly binary decoder and validator** that:

- decodes `.wasm` binaries into a `Module`
- validates decoded modules (`validate_module`)
- prints modules in the canonical text format used by this repository’s snapshots

The authoritative repo references are vendored in:

- `specs/wasm.md`
- `specs/w3.txt`

## What This Task Is Really About

This is an exercise in implementing a **real binary format** with:

- strict length/bounds checking during decoding
- a separate semantic validation phase
- deterministic printing that matches a canonical reference tool

Avoid hardcoding: the corpus includes many modules and both valid and invalid cases.

## Approach

Build incrementally:

1. Header parsing (magic/version) and LEB128 decoding helpers.
2. Section parsing with correct size accounting and bounds checks.
3. Code section parsing (locals + instruction stream) sufficient for printing.
4. Validation rules required by the invalid corpus (indices/types/structure).
5. `Module::print` formatting to match reference snapshots.

Run tests frequently while adding features.

Important: The core logic must be implemented in MoonBit.

## Scope

In scope for this suite:

- `decode_module(data : Bytes) -> Module raise DecodeError`
- `validate_module(mod_ : Module) -> Unit raise ValidationError`
- `Module::print(self : Module) -> String`
- The proposal features present in the committed `wasm-tools --features all`
  corpus, including SIMD, reference types, exceptions, and GC types.

Repo-specific note (important):

- Snapshot output is generated from canonical tooling; match the exact printed format.

Out of scope (not required by current tests):

- Executing WebAssembly (no interpreter/JIT)
- Text-format parsing (WAT)
- Feature negotiation for disabling proposals represented by the committed
  corpus

## Required API

Complete the declarations in `wasm_spec.mbt`.

Implementation notes:

- You can **freely decide** the project structure (modules/files/directories),
  the decoding/validation strategy, and any internal data structures.
- Do **not** modify the following files:
  - `wasm_spec.mbt` - API specification
  - `specs/` folder - Reference documents
  - Provided `*_test.mbt` files - Test fixtures
- Implement the required declarations by adding new `.mbt` files as needed.
- **You may add additional test files** (e.g., xxx_test.mbt) if needed for testing and maintenance purposes

Required entry points:

- `@wasm.decode_module(data : Bytes) -> Module raise DecodeError`
- `@wasm.validate_module(mod_ : Module) -> Unit raise ValidationError`
- `@wasm.Module::print(self : Module) -> String`
- `@wasm.DecodeError::to_string(self : DecodeError) -> String`
- `@wasm.ValidationError::to_string(self : ValidationError) -> String`

## Behavioral rules

- Malformed binaries must raise `DecodeError` (invalid header, truncated input, invalid lengths, etc.).
- Well-formed but invalid modules must raise `ValidationError`.
- Printing must be deterministic and match the suite’s expected snapshots.

## Test execution

```bash
moon test
```

Use `moon test --update` only if you intentionally change snapshots.


## Constraints

### 1. Test Requirements

Implement the complete documented WebAssembly behavior, not only the examples
exercised by the provided tests. Run `moon test` frequently and keep iterating
until it passes. Do not hardcode fixture inputs or expected outputs; implement
the decoder, validator, and printer for arbitrary modules within the supported
subset. When the implementation and verification are complete, finish the task.

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
- Solutions must be real decoders/validators, not test-specific lookup tables
- No hardcoded mappings derived from test fixtures
- Implementation should work for arbitrary modules within the supported subset

### 3. Software Engineering Standards

**Modularity and Organization**:
- **Use subdirectories** to organize code by functional area:
  - `decode/` - Binary decoding and bounds checking
  - `validate/` - Semantic validation rules
  - `print/` - Canonical printing
  - `types/` - Core AST and error types
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
- Logical separation of concerns (decode → validate → print)
- Minimize coupling between modules
- Use appropriate abstractions (types, enums, structs)
- Avoid global mutable state

**Example directory structure**:
```
wasm/
├── moon.mod
├── moon.pkg
├── wasm_spec.mbt          # API declarations (do not modify)
├── wasm.mbt               # Main entry point
├── decode/
│   └── decode.mbt
├── validate/
│   └── validate.mbt
├── print/
│   └── print.mbt
└── types/
    ├── module.mbt
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

This environment has public network access. You may consult WebAssembly binary
format references online, but treat the vendored spec files in `specs/` as the
authoritative baseline for behavior in this task.
