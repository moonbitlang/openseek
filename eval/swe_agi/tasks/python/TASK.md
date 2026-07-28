## Goal

Implement a MoonBit **Python interpreter** (CPython-compatible subset) that can
execute curated CPython regression-test-derived cases included in this
repository. The authoritative repo references are vendored in:

- `specs/python.md`
- `specs/README.md`

## What This Task Is Really About

This is an exercise in building a **real interpreter**:

- Parse Python source with indentation and multi-statement modules
- Implement runtime semantics for the tested subset
- Provide stable observable behavior via `Value::repr/str/to_test_json`

Avoid hardcoding: the test corpus is broad and derived from real CPython tests.

## Approach

Build incrementally:

1. Lexer/parser for the subset needed by tests (indentation-sensitive).
2. Runtime value model and environments (globals/builtins).
3. Execute modules (`exec`) and evaluate expressions (`eval`).
4. Implement builtins/types as required by tests.
5. Ensure formatting/JSON representation contracts match the suite exactly.

Run tests frequently while adding features.

Important: The core logic must be implemented in MoonBit.

## Scope

In scope for this suite:

- VM creation and execution APIs (`Vm::new`, `Vm::exec`, `Vm::exec_program`, `Vm::eval_expr`)
- Convenience helpers (`eval_expr`, `exec_program`, `run_file`, syntax checks)
- Stable observable behavior via `Value::repr`, `Value::str`, and `Value::to_test_json`
- Error behavior via `PyError` variants

Repo-specific note (important):

- Tests are derived from CPython’s `Lib/test/` (curated subset); correctness should generalize beyond exact fixture strings.

Out of scope (not required by current tests):

- Full CPython compatibility beyond the suite’s exercised subset
- C extensions or full standard library coverage

## Required API

Complete the declarations in `python_spec.mbt`.

Implementation notes:

- You can **freely decide** the project structure (modules/files/directories),
  the parsing/evaluation strategy, and any internal data structures.
- Do **not** modify the following files:
  - `python_spec.mbt` - API specification
  - `specs/` folder - Reference documents
  - Provided `*_test.mbt` files - Test fixtures
- Implement the required declarations by adding new `.mbt` files as needed.
- **You may add additional test files** (e.g., xxx_test.mbt) if needed for testing and maintenance purposes

Required entry points:

- `@python.Vm::new() -> Vm`
- `@python.Vm::exec(self : Vm, src : StringView) -> Unit raise PyError`
- `@python.Vm::exec_program(self : Vm, src : StringView) -> Value raise PyError`
- `@python.Vm::eval_expr(self : Vm, expr : StringView) -> Value raise PyError`
- `@python.eval_expr(expr : StringView) -> Value raise PyError`
- `@python.exec_program(src : StringView) -> Value raise PyError`
- `@python.Vm::run_file(self : Vm, path : String) -> Unit raise PyError`
- `@python.run_file(path : String) -> Unit raise PyError`
- `@python.check_syntax(src : StringView, mode : String) -> Unit raise PyError`
- `@python.check_syntax_file(path : String) -> Unit raise PyError`
- `@python.Value::repr(self : Value) -> String`
- `@python.Value::str(self : Value) -> String`
- `@python.Value::to_test_json(self : Value) -> Json`

## Behavioral rules

- Must support indentation-sensitive parsing for module execution.
- VM globals must persist across calls within the same `Vm`.
- Must raise `PyError::SyntaxError` on invalid syntax and appropriate `PyError` variants at runtime.
- `Value::repr/str/to_test_json` outputs are part of the contract; match tests exactly.

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

Implement the complete documented Python behavior, not only the examples
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

**Prohibited shortcuts (cheating)**:

- Do NOT invoke `python`, `python3`, or any Python interpreter via shell commands, subprocess calls, or FFI
- Do NOT delegate interpretation to any external Python runtime
- The implementation must be a genuine MoonBit interpreter, not a wrapper around CPython

### 3. Software Engineering Standards

**Modularity and Organization**:

- **Use subdirectories** to organize code by functional area:
  - `lexer/` - Tokenization and indentation handling
  - `parser/` - AST construction
  - `runtime/` - VM/value model/evaluation engine
  - `builtins/` - Built-in functions and core types
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

- Logical separation of concerns (lexing → parsing → runtime)
- Minimize coupling between modules
- Use appropriate abstractions (types, enums, structs)
- Avoid global mutable state

**Example directory structure**:

```
python/
├── moon.mod
├── moon.pkg
├── python_spec.mbt        # API declarations (do not modify)
├── python.mbt             # Main entry point
├── lexer/
│   └── lexer.mbt
├── parser/
│   └── parser.mbt
├── runtime/
│   └── vm.mbt
├── builtins/
│   └── builtins.mbt
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

This environment has public network access. You may consult Python language
references online, but treat the vendored spec files in `specs/` as the
authoritative baseline for behavior in this task.
