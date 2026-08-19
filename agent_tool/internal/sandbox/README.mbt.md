# agent_tool/internal/sandbox

The source-write sandbox as one prepared-command capability. `shell`,
`run_moonbit`, `bgjobs`, and `shell_output` share one macOS `sandbox-exec`
integration: describe command intent with the `Shell` or `Exec` variants of
`Command`,
prepare an opaque `SandboxedCommand`, run its program and arguments, then ask
that same value to judge the output. Everything SBPL-specific — profile text,
denial subjects, escaping, the `sandbox-exec` path, and the availability probe
— stays behind the API.

This package does not own workspace path manipulation or protection-policy
predicates. Generic lexical operations live in `internal/workspace_path`,
MoonBit source classification lives in
`agent_tool/internal/source_write_policy`, and the platform shell pair lives
in `agent_tool/internal/platform_shell`.

## The contract

Prepare, run, classify:

```mbt check
///|
async test "prepare, run, and classify a shell command" {
  let shell_text = "echo sandbox-ready"
  let prepared = @sandbox.SandboxedCommand::create_if_available(
    ".",
    Shell(shell_text),
  )
  let (program, args) = match prepared {
    Some(command) => (command.program(), command.args())
    // Enforcement is unavailable outside macOS and inside some nested
    // sandboxes. Running without it is an explicit caller policy decision.
    None => (@platform_shell.program, @platform_shell.args(shell_text))
  }
  let (exit_code, output) = @process.collect_output_merged(program, args)
  let output = output.text()
  assert_eq(exit_code, 0)
  assert_eq(output.trim(), "sandbox-ready")
  if prepared is Some(command) {
    // Classify with the same value that supplied the executed program/argv.
    assert_false(command.output_reports_denial(output))
  }
}
```

`None` means exactly "enforcement unavailable". Invalid input — an
unresolvable workspace root, or a `writable_subtree` at or above the root —
raises instead, on every platform, so a caller bug cannot silently disable
protection where the probe happens to fail. The root is realpath'd inside the
constructor, because the kernel matches profile rules against real paths.

The profile is built from the tree as it exists at preparation; renaming the
root or subtree afterwards makes the rules stale. Prepare close to where the
command runs.

## Commands

`Shell(cmd)` runs shell text through the platform shell under the profile.
`Exec(program, args)` prepares a pre-tokenized argv with no
shell involved — the shape `run_moonbit` uses to run `moon` directly. Both
produce the same opaque `SandboxedCommand`. Its executable, arguments, and
denial subjects travel together because classification is meaningful only for
output produced by that prepared invocation.

`writable_subtree` re-allows one directory tree — a scratch lab for a
read-only subagent, `run_moonbit`'s throwaway build dir — via a
last-match-wins SBPL allow rule. A subtree covering the workspace root is
rejected outright: it would re-allow every write the profile exists to deny.

## Classifying denials

A denial surfaces as an "Operation not permitted" line in the child's output.
`SandboxedCommand::output_reports_denial` recognizes the shapes the tools
actually produce, and only on a line that also names a protected source path.
A generic denial, a read denial, or a mere mention of a source file does not
match.

A denied *directory* has no protected suffix, so it is recognized only
through the subjects the profile scan discovered. Those subjects never leave
the prepared command, so a background reader cannot accidentally classify
output using metadata from another profile. The exhaustive platform-independent
line-shape pins live in `denial_output_wbtest.mbt`; the end-to-end kernel tests
— a real denied write and a real subtree allow — live in
`capability_test.mbt`.

## The profile underneath

The generated profile starts from `(allow default)` and then:

- denies writes to `*.mbt`, `*.mbti`, `*.mbt.md`, `moon.mod`, `moon.pkg`, and
  `moon.work`, including the legacy JSON manifests, under the workspace root;
- re-allows `_build` and `.mooncakes` trees where Moon writes generated
  sources;
- denies source-containing directories literally, preventing a direct rename
  or removal of those directories.

The base profile is cached by normalized workspace root; directory mtimes
from the source-tree scan invalidate the cache when the tree changes. The
`writable_subtree` variant is composed per command preparation and never cached.
`sandbox_wbtest.mbt` pins the emitted SBPL byte for byte.

The profile builder classifies names through `@source_write_policy`; callers
performing static command preflight (the `shell` tool) use those packages
directly, so the static and kernel layers agree on what counts as source.

## Availability and limitations

Preparation's availability gate is a cached behavioral probe, not an
existence check: it requires an allowed no-op to succeed and a denied
temporary write to fail. Nested sandboxes that prohibit re-sandboxing
therefore yield `None`, and the result is cached for the process — a probe
that failed transiently stays failed, deliberately, because in the
environments where it genuinely cannot pass (nested sandboxes), re-probing
on every command would cost two spawns each and never succeed.

The profile is a best-effort write guard, not a complete process-security
boundary:

- reads and non-source writes remain allowed;
- callers may run unsandboxed when preparation returns `None`;
- filesystem aliasing and directory operations can exceed purely path-based
  policy assumptions;
- `shell` supplements the runtime profile with static command preflight,
  while arbitrary code run by `run_moonbit` cannot receive the same analysis.
