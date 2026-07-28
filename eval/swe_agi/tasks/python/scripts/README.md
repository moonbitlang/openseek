# Generating MoonBit Tests from `reference_pub_test/`

This directory contains a generator that walks `reference_pub_test/` (a copy
of CPython `Lib/test/`) and extracts **convertible** unittest assertions into a
MoonBit test file.

## Generate

From this task directory:

```bash
python3.10 scripts/generate_tests_from_reference.py
```

The generator requires Python 3.10 or newer because it uses structural pattern
matching while walking the CPython AST.

Outputs:

- `generated_test.mbt` (generated MoonBit tests)
- `generated_test.report.json` (what was skipped and why)

## Notes

- The generator does **not** execute the CPython tests; it only parses them.
- Many CPython tests rely on imports, the stdlib, IO, OS features, etc. Those
  are recorded in the report until the Python-in-MoonBit implementation and
  test translation rules expand.

## Suggested workflow

- Use `@python.check_syntax_file(...)` tests to grow parser coverage quickly.
- Use `@python.Vm::exec_program(...)` tests to cover multi-statement snippets
  where a single `eval_expr` is not enough.
- Use `@python.Vm::run_file(...)` smoke tests (generated for modules that only
  import `unittest`) to validate file loading and basic imports without running
  the entire CPython suite.
