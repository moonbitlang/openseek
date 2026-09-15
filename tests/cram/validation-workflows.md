# Checking, testing, and formatting a MoonBit project

The bundled validation scripts run Moon commands in the current directory.
In OpenSeek, select the project with `cwd`, for example:

```json
{"filename":"@builtin/check-test.mbtx","cwd":"/path/to/project"}
```

This page executes the actual scripts against a small temporary project,
with no model or credentials. Run it from the repository root:

```sh
moon cram test tests/cram/validation-workflows.md --shell bash
```

## Define the commands once

As in the [read guide](read-workflow.md), shell functions keep each example
short. Cram preserves the functions between blocks. `"$@"` forwards arguments
without splitting paths containing spaces.

```mooncram
$ CHECK() { moon run "$TESTDIR/../../share/workflow/check.mbtx" -- "$@"; }
```

```mooncram
$ TEST() { moon run "$TESTDIR/../../share/workflow/test.mbtx" -- "$@"; }
```

```mooncram
$ CHECK_TEST() { moon run "$TESTDIR/../../share/workflow/check-test.mbtx" -- "$@"; }
```

```mooncram
$ INFO_FMT() { moon run "$TESTDIR/../../share/workflow/info-fmt.mbtx" -- "$@"; }
```

```mooncram
$ CHECK_JSON() { moon run "$TESTDIR/../../share/workflow/check-json.mbtx" -- "$@"; }
```

## Create a project with one test

The project files live in Cram's temporary working directory. The source is
deliberately compact so the formatting example below has something to change.

```mooncram
$ cat > moon.mod <<'EOF'
> name = "example/workflow_docs"
> EOF
```

```mooncram
$ touch moon.pkg
```

```mooncram
$ cat > answer.mbt <<'EOF'
> ///|
> pub fn answer() -> Int {42}
> EOF
```

```mooncram
$ cat > answer_test.mbt <<'EOF'
> ///|
> test "answer" { assert_eq(@workflow_docs.answer(), 42) }
> EOF
```

## Check types

[`check.mbtx`](../../share/workflow/check.mbtx) runs `moon check`.
Successful checking has no standard output; Moon's build progress goes to
stderr. Cram checks stdout and the exit status by default, so no quiet flag
is needed.

```mooncram
$ CHECK
```

## Run tests

[`test.mbtx`](../../share/workflow/test.mbtx) runs `moon test` and prints its
summary. It does not update snapshots.

```mooncram
$ TEST
Total tests: 1, passed: 1, failed: 0.
```

[`check-test.mbtx`](../../share/workflow/check-test.mbtx) checks first, then
runs the tests when checking succeeds.

```mooncram
$ CHECK_TEST
Total tests: 1, passed: 1, failed: 0.
```

## Generate interfaces and format source

[`info-fmt.mbtx`](../../share/workflow/info-fmt.mbtx) runs `moon info`, then
`moon fmt`. It modifies files in the selected project.

```mooncram
$ INFO_FMT
```

The public function is now listed in the generated interface:

```mooncram
$ grep '^pub fn' pkg.generated.mbti
pub fn answer() -> Int
```

The compact function body has been formatted:

```mooncram
$ cat answer.mbt
///|
pub fn answer() -> Int {
  42
}
```

## Check with JSON diagnostics

[`check-json.mbtx`](../../share/workflow/check-json.mbtx) runs
`moon check --output-json` and relays diagnostics without filtering them.
This valid project has no diagnostics:

```mooncram
$ CHECK_JSON
```

## Fail when checking fails

Change the function to return a string where its signature requires an integer:

```mooncram
$ cat > answer.mbt <<'EOF'
> ///|
> pub fn answer() -> Int { "wrong" }
> EOF
```

`CHECK` fails. Compiler diagnostics go to stderr; the workflow's failure
message appears on stdout. `(glob)` matches the runtime's source location and
the compiler's exit code, while `[1]` checks the script's own exit status.

```mooncram
$ CHECK
Failure(* FAILED: moon check failed (exit=*)) (glob)
[1]
```

`CHECK_TEST` also fails at the check step, without printing a test summary:

```mooncram
$ CHECK_TEST
Failure(* FAILED: moon check failed (exit=*)) (glob)
[1]
```
