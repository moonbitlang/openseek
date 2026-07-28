## Goal

Implement a MoonBit **R6RS Scheme interpreter** that can parse and evaluate a
large subset of R6RS and pass the comprehensive test corpus included in this
repository. The authoritative repo reference is vendored in:

- `specs/r6rs.md`

## What This Task Is Really About

This is an exercise in building a **real language implementation**:

- A reader (lexer/parser) for R6RS datum syntax and program forms
- A macro system sufficient for the suite
- An evaluator/runtime implementing R6RS semantics for covered libraries
- A value printer (`value_to_string`) whose output matches tests exactly

Avoid hardcoding: the suite is large and includes non-trivial programs.

## Approach

Build incrementally:

1. Reader: symbols, lists, numbers, strings, quote/quasiquote forms.
2. Core evaluator: variables, `lambda`, application, `if`, `define`, `set!`.
3. Core data structures: pairs, lists, vectors, bytevectors, strings/chars.
4. Control forms and library procedures required by the suite.
5. Exceptions/conditions, continuations, and macro system as needed by tests.
6. Ensure `value_to_string` matches expected canonical surface syntax.

Run tests frequently while adding features.

Important: The core logic must be implemented in MoonBit.

## Scope

In scope for this interpreter (as exercised by tests):

- `eval_program`: evaluate a program and return the last form’s value
- `eval_program_all`: evaluate all top-level forms and return values in order
- `value_to_string`: canonical Scheme surface syntax printing
- Large portions of R6RS libraries as covered by the included test modules

Repo-specific note (important):

- Output formatting from `value_to_string` is part of the conformance oracle; match it exactly.

Out of scope (not required by current tests):

- Full R6RS library completeness beyond what the suite uses

## Required API

Complete the declarations in `r6rs_spec.mbt`.

Implementation notes:

- You can **freely decide** the project structure (modules/files/directories),
  the parsing/evaluation strategy, and any internal data structures.
- Do **not** modify the following files:
  - `r6rs_spec.mbt` - API specification
  - `specs/` folder - Reference documents
  - Provided `*_test.mbt` files - Test fixtures
  - `racket-r6rs-test/` - Migrated test corpus
- Implement the required declarations by adding new `.mbt` files as needed.
- **You may add additional test files** (e.g., xxx_test.mbt) if needed for testing and maintenance purposes

Required entry points:

- `@r6rs.eval_program(src : String) -> Value raise`
- `@r6rs.eval_program_all(src : String) -> Array[Value] raise`
- `@r6rs.value_to_string(value : Value) -> String`

## Behavioral rules

- Must implement R6RS semantics for the features exercised by tests.
- `value_to_string` output is part of the contract; match exact expected text.
- Errors must raise (exact message text usually not asserted; behavior is).

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

Implement the complete documented R6RS behavior, not only the examples
exercised by the provided tests. Run `moon test` frequently and keep iterating
until it passes. Do not hardcode fixture programs or expected results; build a
general interpreter for arbitrary programs within the supported subset. When
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
- Solutions must be real interpreters, not test-specific lookup tables
- No hardcoded mappings derived from test fixtures
- Implementation should work for arbitrary programs within the supported subset

### 3. Software Engineering Standards

**Modularity and Organization**:
- **Use subdirectories** to organize code by functional area:
  - `reader/` - Datum/program parsing
  - `expand/` - Macro expansion
  - `runtime/` - Evaluator and core data structures
  - `library/` - Built-in procedures/libraries used by tests
  - `print/` - `value_to_string` implementation
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
- Logical separation of concerns (reader → expansion → evaluation → printing)
- Minimize coupling between modules
- Use appropriate abstractions (types, enums, structs)
- Avoid global mutable state

**Example directory structure**:
```
r6rs/
├── moon.mod
├── moon.pkg
├── r6rs_spec.mbt          # API declarations (do not modify)
├── r6rs.mbt               # Main entry point
├── reader/
│   └── reader.mbt
├── expand/
│   └── expand.mbt
├── runtime/
│   └── eval.mbt
├── library/
│   └── base.mbt
├── print/
│   └── print.mbt
└── types/
    ├── value.mbt
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

This environment has public network access. You may consult R6RS/Scheme
resources online, but treat the vendored spec files in `specs/` as the
authoritative baseline for behavior in this task.
