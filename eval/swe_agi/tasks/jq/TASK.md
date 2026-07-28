## Goal

Implement a MoonBit **jq query language interpreter** that can parse jq queries,
parse JSON input, evaluate the query, and collect all output values as an
`Array[Json]`. The authoritative references are vendored in:

- `specs/jq.md`
- `specs/README.md`

## What This Task Is Really About

This is an exercise in building a **real query language**:

- A lexer/parser for jq expressions
- An evaluator that can produce **0..N outputs** (jq is stream-based)
- A runtime for built-ins as covered by tests

Avoid hardcoding: the valid and invalid suites are broad.

## Approach

Build incrementally:

1. JSON parsing for input (use `@json.parse`).
2. Core filters (`.`, field access, indexing, `.[]`) and output collection.
3. Composition (`|`, `,`) and constructors (`[]`, `{}`).
4. Operators and type rules as exercised by tests.
5. Built-ins required by the suite (expand iteratively).
6. Error handling (parse/runtime/type errors) matching invalid tests.

Run tests frequently while adding features.

Important: The core logic must be implemented in MoonBit.

## Scope

In scope for this interpreter (as exercised by tests):

- Parsing jq queries in the supported subset
- Evaluating queries over JSON input with jq-like semantics
- Collecting all outputs deterministically into `Array[Json]`
- Raising on invalid JSON/query/runtime errors where required by invalid tests

Repo-specific note (important):

- Multiple-output semantics are observable: collect outputs **in order** exactly.

Out of scope (not required by current tests):

- Full jq language feature completeness beyond what the corpus covers

## Required API

Complete the declarations in `jq_spec.mbt`.

Implementation notes:

- You can **freely decide** the project structure (modules/files/directories),
  the parsing/evaluation strategy, and any internal data structures.
- Do **not** modify the following files:
  - `jq_spec.mbt` - API specification
  - `specs/` folder - Reference documents
  - Provided `*_test.mbt` files - Test fixtures
- Implement the required declarations by adding new `.mbt` files as needed.
- **You may add additional test files** (e.g., xxx_test.mbt) if needed for testing and maintenance purposes

Required entry points:

- `@jq.run(query : String, input : String) -> Array[Json] raise`

## Behavioral rules

- Must parse the JSON input and raise on invalid JSON.
- Must parse the jq query and raise on invalid syntax.
- Must evaluate with jq-like semantics for the tested subset.
- Must collect all produced outputs in order into an array.
- Must raise on runtime/type errors where the invalid suite expects it.

## Test execution

```bash
moon test
```

Use `moon test --update` only if you intentionally change snapshots.

## Constraints

### 1. Test Requirements

Implement the complete documented jq behavior, not only the examples exercised
by the provided tests. Run `moon test` frequently and keep iterating until it
passes. Do not hardcode fixture inputs or expected outputs; build a general
parser and evaluator for arbitrary inputs within the supported subset. When
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
- Implementation should work for arbitrary inputs within the supported subset

### 3. Software Engineering Standards

**Modularity and Organization**:
- **Use subdirectories** to organize code by functional area:
  - `lexer/` - Tokenization
  - `parser/` - AST construction
  - `runtime/` - Evaluation engine and value model
  - `builtins/` - Built-in library implementations
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
- Logical separation of concerns (lexing → parsing → evaluation)
- Minimize coupling between modules
- Use appropriate abstractions (types, enums, structs)
- Avoid global mutable state

**Example directory structure**:
```
jq/
├── moon.mod
├── moon.pkg
├── jq_spec.mbt            # API declarations (do not modify)
├── jq.mbt                 # Main entry point
├── lexer/
│   └── lexer.mbt
├── parser/
│   └── parser.mbt
├── runtime/
│   └── eval.mbt
├── builtins/
│   └── builtins.mbt
└── types/
    ├── ast.mbt
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

This environment has public network access. You may consult jq documentation
online, but treat the vendored spec files in `specs/` as the authoritative
baseline for behavior in this task.
