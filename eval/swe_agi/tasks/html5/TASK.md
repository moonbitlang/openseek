## Goal

Implement a MoonBit **HTML5 parser** compatible with the WHATWG HTML parsing
algorithm and this repository’s test suite. The authoritative repo reference is
vendored in:

- `specs/html5.md`

## What This Task Is Really About

This is an exercise in implementing a **real HTML5 parser**:

- a tokenizer that follows the HTML parsing states
- a tree builder that constructs a DOM-like document
- a serializer / inspector used by tests

Avoid hardcoding: HTML parsing has many special cases and error-recovery rules.

## Approach

Build incrementally:

1. Tokenizer for common tags/text/comments and required states.
2. Tree builder for insertion modes needed by the suite.
3. Attribute handling and namespace/tag name rules.
4. Error collection for `parse_with_errors` where required.
5. Deterministic serialization via `Document::to_html()` / `Document::dump()`.

Run tests frequently while adding features.

Important: The core logic must be implemented in MoonBit.

## Scope

In scope for this suite:

- `parse`, `parse_with_errors`, `parse_with_scripting`, and `tokenize`
- A document model with node accessors/mutators used by tests
- Deterministic serialization/inspection outputs

Repo-specific note (important):

- The test suite defines observable behavior via `Document::dump()`/`to_html()`;
  match it exactly.

Out of scope (not required by current tests):

- Full browser integration (CSS layout, scripting runtime, networking)

## Required API

Complete the declarations in `html5_spec.mbt`.

Implementation notes:

- You can **freely decide** the project structure (modules/files/directories),
  the parsing strategy, and any internal data structures.
- Do **not** modify the following files:
  - `html5_spec.mbt` - API specification
  - `specs/` folder - Reference documents and fixtures
  - Provided `*_test.mbt` files - Test fixtures
- Implement the required declarations by adding new `.mbt` files as needed.
- **You may add additional test files** (e.g., xxx_test.mbt) if needed for testing and maintenance purposes

Required entry points:

- `@html5.parse(input : String) -> Document`
- `@html5.parse_with_errors(input : String) -> (Document, Array[ParseError])`
- `@html5.parse_with_scripting(input : String) -> Document`
- `@html5.tokenize(input : String) -> (Array[Token], Array[ParseError])`
- `@html5.Document::to_html(self : Document) -> String`
- `@html5.Document::dump(self : Document) -> String`

## Behavioral rules

- Follow the WHATWG HTML parsing algorithm for the subset exercised by tests.
- Handle malformed HTML with HTML5-style error recovery (not strict XML rules).
- Tokenization and tree construction must be deterministic.
- Serialization/inspection output must match tests exactly.

## Test execution

```bash
moon test
```

Use `moon test --update` only if you intentionally change snapshots.

If tests hang due to infinite loops or run out of memory, `try.py` (requires python3) can run each test individually with timeout and OOM detection:

```bash
python3 try.py
python3 try.py --timeout 60              # custom timeout (default: 30s)
python3 try.py --test-file foo_test.mbt  # run specific file
python3 try.py --json                    # output as JSONL
```

This is slower than `moon test` since it runs tests one by one.


## Constraints

### 1. Test Requirements

Implement the complete documented HTML5 subset, not only the examples exercised
by the provided tests. Run `moon test` frequently and keep iterating until it
passes. Do not hardcode fixture inputs or expected outputs; build a general
tokenizer, tree builder, document model, and serializer for arbitrary HTML
inputs within the supported subset. When the implementation and verification
are complete, finish the task.

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
- Implementation should work for arbitrary HTML inputs in the supported subset

### 3. Software Engineering Standards

**Modularity and Organization**:
- The required declarations in `html5_spec.mbt` belong to the root `html5`
  package. Tests call root-package APIs such as `@html5.parse`, so those
  declarations must be implemented or forwarded from the root package.
- You may organize implementation across root-level files by functional area
  (for example, tokenization, tree building, the document model,
  serialization, and core types).
- If you create subdirectories as separate MoonBit packages, wire them through
  package configuration and keep root-package implementations, `pub using`
  re-exports, or forwarding functions so the required root `@html5` APIs remain
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
- Logical separation of concerns (tokenization → tree building → output)
- Minimize coupling between modules
- Use appropriate abstractions (types, enums, structs)
- Avoid global mutable state

**Example directory structure**:
```
html5/
├── moon.mod
├── moon.pkg
├── html5_spec.mbt         # API declarations (do not modify)
├── html5.mbt              # Main entry point
├── tokenizer/
│   └── tokenizer.mbt
├── tree_builder/
│   └── builder.mbt
├── dom/
│   ├── document.mbt
│   └── node.mbt
├── serialize/
│   ├── html.mbt
│   └── dump.mbt
└── types/
    ├── token.mbt
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

This environment has public network access. You may consult HTML parsing
references online, but treat the vendored spec files in `specs/` as the
authoritative baseline for behavior in this task.
