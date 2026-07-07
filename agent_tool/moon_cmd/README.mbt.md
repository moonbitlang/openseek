# Moon Cmd Tool

`moon_cmd` runs selected `moon` subcommands directly without going through
`sh -c`. It is intended for end-to-end validation: run tests, execute CLIs,
refresh package interfaces, and verify README commands with the same argument
shape users will run.

For raw compiler diagnostics, run `moon check` through `shell`; its post-command
auto-check surfaces structured compiler feedback. Use `moon_cmd` when the
important behavior is the actual command line and process result.

## Arguments

| Name | Type | Required | Notes |
| --- | --- | --- | --- |
| `command` | string | yes | `check`, `test`, `run`, `info`, `fmt`, or `build`. |
| `cwd` | string | no | Working directory. Empty is treated as missing. |
| `target` | string | no | `wasm`, `wasm-gc`, `js`, `native`, `llvm`, or `all`. Not accepted for `fmt`. |
| `arg` | string | no | One extra moon argument, such as `--update` or `--output-json`. |
| `args` | string array | no | Additional moon arguments placed after common flags. |
| `path` | string | no | One package/file path or main package. |
| `paths` | string array | no | Additional package/file paths. |
| `program_args` | string array | no | Arguments after `--`; only valid with `command = "run"`. |
| `stdin` | string | no | Text sent to process stdin; only valid with `command = "run"`. |
| `test_update_kind` | string | for `moon test --update` | `stale_snapshot` or `intentional_output_change`. |
| `test_update_reason` | string | for `moon test --update` | Short explanation of the prior plain `moon test` failure review. |
| `max_output_chars` | number | no | Defaults to 12000, capped at 50000. Truncated output is a tool error. |

`moon test --update` is guarded deliberately. Run plain `moon test` first,
review the failure, and only pass `--update` when it is a stale snapshot or an
intentional output change. Do not use `--update` for behavior bugs.

## Design Rationale

`moon_cmd` covers the MoonBit commands whose success criteria are more than
compiler diagnostics: tests, CLI behavior, package interface generation,
formatting, and builds. Running these commands directly avoids shell status
masking and keeps the command line visible in a stable output header.

The tool accepts only selected `moon` subcommands because that lets the host add
policy around high-risk actions. The `moon test --update` guardrail is an
example: snapshot refreshes are allowed only after the agent states whether the
change is a stale snapshot or an intentional output change. Output caps mirror
the shell tool because `moon run --target native` can produce very large
compiler or generated-artifact output when a CLI is miswired.

## API Style

Use `command`, optional `target`, optional `path` or `paths`, and `program_args`
for the command after `--`:

```json
{
  "command": "run",
  "cwd": "/tmp/example_project",
  "target": "native",
  "path": "cmd/main",
  "program_args": ["fixtures/schema.json", "fixtures/valid.json"]
}
```

For stdin acceptance probes, pass `stdin` directly instead of using shell pipes:

```json
{
  "command": "run",
  "cwd": "/tmp/example_project",
  "target": "native",
  "path": "cmd/main",
  "program_args": ["--from-stdin"],
  "stdin": "{\"a\":1}\n"
}
```

For snapshot updates, first run plain `moon test`, inspect the failure, then
include both guard fields:

```json
{
  "command": "test",
  "args": ["--update"],
  "test_update_kind": "intentional_output_change",
  "test_update_reason": "Parser error messages now include source paths."
}
```

## Action

The action is always `Respond(ToolOutput(...))`. `is_error` is true when the
direct `moon` process exits non-zero, when argument validation fails, when
output is truncated, or when the process cannot be launched. The string body
has one of these shapes:

- `"cwd=<cwd>\ncommand=moon <subcommand> ...\nexit=<code>\n<output>"`.
- `"cwd=<cwd>\ncommand=moon <subcommand> ...\nexit=<code>\ntruncated=true\noutput_chars=<n>\nshown_chars=<n>\n<output-prefix>"`.
- `"error running moon_cmd: <error>"`.
- `"error: moon_cmd requires <field description>"`.

## Example

```moonbit check
///|
test "moon_cmd tool advertises run validation fields" {
  let tool = @moon_cmd.definition()
  assert_eq(tool.name, "moon_cmd")
  let JsonSchema(schema) = tool.schema
  let text = schema.stringify()
  assert_true(text.contains("\"command\""))
  assert_true(text.contains("\"program_args\""))
  assert_true(text.contains("\"test_update_kind\""))
  assert_true(text.contains("\"max_output_chars\""))
}
```

Process execution is covered by fixture tests that copy a native-only CLI
project into `/tmp`, then verify a failing default-target invocation, a passing
explicit `--target native` CLI run, snapshot output from `moon test`, and a
failing test reported as a tool error.
