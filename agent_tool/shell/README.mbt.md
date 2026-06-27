# Shell Tool

`shell` runs a command line through the platform shell and returns the exit code
together with the merged stdout/stderr output. On Windows that shell is
`pwsh -NoProfile -Command` and callers should use PowerShell syntax; elsewhere
it is `sh -c` and callers should use POSIX shell syntax. It is the agent's
escape hatch for running build commands, tests, package managers, version-control
operations, and any other workspace task the other built-in tools don't cover.

## Design Rationale

`shell` is the general escape hatch because an agent occasionally needs a real
workspace command that is not worth modeling as a dedicated tool. It uses
the local platform shell to match developer command-line ergonomics: pipelines,
redirects, environment variables, and existing scripts all work without
inventing a custom argument schema for every possible operation.

stdout and stderr are merged so diagnostics appear in the same order a terminal
would show them. Output is capped while the process pipe is being read because
commands can accidentally emit generated artifacts, dependency listings, or
compiler invocations large enough to damage the model context. When reading
proves the output exceeds the cap, the tool cancels the child process and treats
the result as a tool error so the agent knows it received only an output prefix.

Callers may also set `timeout_ms` for commands that could wait indefinitely.
When the timeout expires, the in-flight process collection is cancelled and the
tool returns an error instead of blocking the agent loop.

## API Style

Use `cwd` whenever the command is workspace-relative, and keep commands
specific:

```json
{
  "cmd": "git status --short",
  "cwd": "/Users/dii/git/openseek"
}
```

Prefer dedicated tools when they encode useful policy. Run Moon commands such as
`moon check` (fast compiler feedback), `moon test`, `moon run`, `moon info`,
`moon fmt`, `moon build`, `moon update`, `moon add`, and `moon remove` through
`shell` with the `cwd` field. Use shell features such as pipes and heredocs for
CLI probes.

After a successful mutating Moon command, `shell` appends bounded
`moon check --diagnostic-limit 1` feedback from the nearest MoonBit module or
workspace root, respecting `moon -C <dir>` and explicit cwd changes such as
`cd ./dir && moon ...`. Bare relative `cd dir` is skipped because `CDPATH` can
change which directory the shell enters. This covers commands such as
`moon add`, `moon remove`, `moon update`, `moon fmt`, `moon info`,
`moon test --update`, and `moon ide rename ... --apply`. Read-only variants
such as dry-run commands and `moon fmt --check` are left alone, as are Moon
invocations with per-command environment overrides such as `FOO=bar moon` or
`env FOO=bar moon`. Follow-up checks are skipped when `timeout_ms` is set and
share the remaining `max_output_chars` budget.

When `/usr/bin/sandbox-exec` is available, agent shell commands run with
MoonBit source files and manifests read-only by default. The profile blocks
shell writes to `.mbt`, `.mbt.md`, `.mbti`, `moon.mod`, `moon.pkg`, `moon.work`,
and the legacy JSON manifest names under the workspace root, while still
allowing Moon-managed build/cache paths such as `_build` and `.mooncakes`. The
profile is cached per normalized workspace root so ordinary read-only shell use
does not rescan the repository every time. `sandbox-exec` is treated as usable
only after a probe proves that a deny rule is actually enforced. If a command
hits that sandbox, the tool keeps the original command output and adds guidance
to retry compiler-feedback or mechanical code fixes with line-anchored `edit`
(or `multi_edit` for several fixes in one file), not shell-generated rewrites
routed through another tool.

Direct output redirects to protected source paths are blocked before the command
runs. This catches masked forms such as `cmd 2>/dev/null > main.mbt || true`
where the shell would otherwise hide the sandbox denial from the tool output.
Direct `mv`/`rm` source-tree operations and obvious source-writing script
snippets are also blocked before execution, including scripts that create
MoonBit source under `_build` and then rename it into a package directory.
Source-mutating Git operations such as `git checkout -- .`, `git restore`,
`git reset --hard`, non-dry-run `git clean`, and non-checking `git apply` are
blocked for the same reason.
Too-complex command strings with in-place `sed` edits are rejected even when the
source paths are indirect, as in `while read f; do sed -i ... "$f"; done`.
Too-complex commands with visible MoonBit source creation or tree transfer
markers are also rejected before execution.

Narrowly recognized Moon commands that are expected to write source or package
metadata run outside the source-write sandbox: `moon fmt`, `moon info`,
`moon add`, `moon remove`, `moon update`, `moon test --update`, and
`moon ide rename ... --apply`. Compounds are conservative; `moon fmt &&
moon check` is trusted, while a broad script or source rewrite through shell is
not.

## Arguments

| Name | Type   | Required | Notes |
| ---- | ------ | -------- | ----- |
| `cmd` | string | yes | Passed as the single command argument to the platform shell. |
| `cwd` | string | no  | Working directory. An empty string is treated as missing. |
| `timeout_ms` | number | no | Positive timeout in milliseconds. Timed-out commands are cancelled and reported as tool errors. |
| `max_output_chars` | number | no | Defaults to 12000, capped at 50000. The retained output prefix is bounded while reading; exceeding the limit cancels the command and returns a tool error. |

## Action

The action is always `Respond(ToolOutput(...))` — the agent loop forwards
`ToolOutput.content` to the model as a tool-call response and never finishes
from a `shell` invocation. `is_error` is `true` for launch failures, invalid
arguments, non-zero shell exit codes, and output truncation.

Metadata is a trailing `<system>...</system>` footer (the `read` tool
convention): the merged stdout/stderr output comes first, then a single footer
line. An output-less command returns just the footer. The string body has one of
these shapes:

- `"<stdout/stderr merged>\n<system>exit=<code></system>"` — normal completion.
- For successful mutating `moon` commands, the output may be followed by a
  `moon check:` section with bounded compiler diagnostics before the footer.
- `"<output-prefix>\n<system>exit=<code-or-cancelled> truncated=true output_limit_reached=true shown_chars=<n> max_output_chars=<n></system>"` —
  output exceeded `max_output_chars` while the process pipe was being read. The
  command is cancelled if it has not already exited; no full output length is
  reported because the full output was intentionally not collected.
- `"error: shell command timed out after <n>ms"` — `timeout_ms` elapsed before
  the command completed.
- `"error running shell: <error>"` — the platform shell failed to launch
  (rare; usually a process subsystem error).
- `"error: shell requires arguments.cmd"` — payload was an object but had no
  `cmd` field.
- `"error: shell requires object arguments"` — payload was not a JSON object.

`stderr` is redirected into the same process output pipe as `stdout` so the
model sees the same interleaving a developer would see in a terminal.

## Example

```moonbit check
///|
test "shell tool advertises the expected schema" {
  let tool = @shell.definition()
  assert_eq(tool.name, "shell")
  assert_true(tool.description.contains("arguments.cmd"))
  let JsonSchema(schema) = tool.schema
  let text = schema.stringify()
  assert_true(text.contains("\"cmd\""))
  assert_true(text.contains("\"timeout_ms\""))
  assert_true(text.contains("\"max_output_chars\""))
  assert_true(text.contains("\"required\""))
}
```

```moonbit check
///|
async test "shell tool runs a project-style command through the registry" {
  @vfs.with_tmpdir(prefix="openseek-shell-readme-", dir => {
    let tools = @agent_tool.Tools([@shell.definition()])
    let arguments : Json = {
      "cmd": "echo 'alpha beta'",
      "cwd": dir,
      "timeout_ms": 5000,
    }
    let call = @agent_tool.AgentToolCall(
      ToolCall(
        id="call_shell_count",
        name="shell",
        arguments=arguments.stringify(),
      ),
    )
    let result = @agent_tool.execute_tool_call(call, tools)
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_true(output.content.contains("exit=0"))
    assert_true(output.content.contains("alpha beta"))
  })
}
```
