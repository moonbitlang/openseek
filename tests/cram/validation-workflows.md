# Checking, testing, and formatting a MoonBit project

The bundled validation scripts run Moon commands in the current directory.
In OpenSeek, select the project with `cwd`, for example:

```json
{"filename":"@builtin/check-test.mbtx","cwd":"/path/to/project"}
```

Run this document from the repository root:

```sh
moon testcli test tests/cram/validation-workflows.md --timeout-ms 300000
```

The [validation fixture](fixtures/validation-workflows.sh) creates a temporary
project with a compact `answer` function and one passing test. It runs the actual
scripts, checks every command's exit status, and removes the fixture directory
when finished. No model or credentials are needed.

- [`check.mbtx`](../../share/workflow/check.mbtx) runs `moon check`. A successful
  check has no standard output; build progress goes to stderr.
- [`test.mbtx`](../../share/workflow/test.mbtx) runs `moon test` and prints its
  summary without updating snapshots.
- [`check-test.mbtx`](../../share/workflow/check-test.mbtx) checks first and runs
  tests only after checking succeeds.
- [`info-fmt.mbtx`](../../share/workflow/info-fmt.mbtx) generates the public
  interface, then formats the source. The fixture reads both files back.
- [`check-json.mbtx`](../../share/workflow/check-json.mbtx) relays JSON diagnostics
  without filtering; the valid project has no diagnostics.

Finally, the fixture changes the function to return a string instead of an
integer. Both `check.mbtx` and `check-test.mbtx` must exit with status 1. The final
stderr lines identify the failed check; the latter script prints no test summary.
The glob matches only the runtime source location and compiler exit code.

```mooncram
$ moonx ../cli-fixture.mbtx fixtures/validation-workflows.sh
Total tests: 1, passed: 1, failed: 0.
Total tests: 1, passed: 1, failed: 0.
pub fn answer() -> Int32
///|
pub fn answer() -> Int32 {
  42
}
Failure(* FAILED: moon check failed (exit=*)) (glob)
Failure(* FAILED: moon check failed (exit=*)) (glob)
```
