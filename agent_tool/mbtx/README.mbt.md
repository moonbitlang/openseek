# mbtx

Compile and run a **self-contained MoonBit program** and return its merged
stdout/stderr and exit status. It is the agent's way to *script in MoonBit* —
for automation (read and transform files, parse JSON, compute) and for probing
how a language feature behaves — instead of reaching for shell `python`/`node`.
The default wasm backend runs under moonrun's policy, making it the natural
sandboxed automation surface.

## How it works

The `source` is a `.mbtx` **single-file script** — MoonBit's own one-file
program format. The tool writes it into a throwaway directory and runs
`moon run <file>.mbtx --target <target> --target-dir <temp>` with the workspace
(or explicit `cwd`) as the program's working directory. Relative reads therefore
reach workspace files, while snippet build artifacts stay out of your `_build`.
Moon's single-file runner handles the inline import block, and compiler
diagnostics are rewritten to stable `source:LINE:COL` locations.

A failed run says **which stage failed**. `moon run` exits 1 for a rejected
build and for a trapped program alike, so the tool probes the throwaway target
dir for the runnable artifact moon links only after a successful build
(`single/single.wasm`/`.js`/`.exe`): absence means the **build failed and the
program never ran** (most often compiler diagnostics about `source`, though
the output itself says whether it was that or a toolchain/dependency fault),
presence means the **build completed and the failure came from the run** —
the program failing at runtime, or its runner failing to launch; either way
not a compile problem — and a foreground timeout likewise says whether the
build or the run is what never finished. A probe fault claims neither stage and keeps the plain exit
report. The probe is structural on purpose: a snippet legitimately runs
`moon check` as a child process, so compiler-diagnostic text in the output
proves nothing about the snippet itself. For a run that was handed off, the
same classification is computed when the job exits (before its build dir is
reclaimed, and single-flight so a racing `job_output` read can never cache a
stale answer) and rides the completion notice and `job_output`.

With the agent's background runtime, every call waits inline for up to five
seconds. A still-running compile or program is then adopted as the same
background execution: the call returns its job id, completion is pushed later,
and its compiler inputs and build artifacts are reclaimed when the job becomes
terminal. Files the snippet writes under its temporary result directory remain
readable until session teardown, so paths printed in completion output stay
valid. There is no foreground/background argument to choose. A standalone
definition without a job runtime stays in the foreground for up to 300 seconds
and is cancelled at that deadline.

## Arguments

- `source` (string, required): a full `.mbtx` program. It may open with an
  inline `import { "pkg", "pkg", … }` block (comma-separated module paths),
  then the program including its own `main`. Use `async fn main` for
  filesystem/stdio work.
- `target` (string, optional, default `wasm`): one of `wasm`, `wasm-gc`, `js`,
  or `llvm`. The default wasm backend is the policy-bound command/IO surface;
  the other targets are intended for pure compute, reject explicit native FFI,
  and run without that policy. `native` is deliberately unavailable because
  moonrun cannot apply the policy to it.
- `cwd` (string, optional, default workspace root): the working directory the
  program runs in. A relative `cwd` resolves against the workspace root, like
  the `shell` tool.
- `escalated` (boolean, optional, default `false`): ask the user to run this
  one snippet with **no sandbox policy**. Offered only when the tool was built
  with an `ask_approval` channel — see *Escalation* below. Absent from the
  schema otherwise, so a build with nobody to ask does not advertise a field
  whose every use would be refused.
- `warning` (string, optional, `"off"`/`"on"`, default `"off"`): whether
  compiler warnings appear in the output. Snippets are throwaway scripts, so
  unused-value style noise is suppressed unless the warnings themselves are
  what you are probing. Selected correctness diagnostics whose default state
  is `error` (such as `partial_match`) are maintained as explicit mnemonic
  exceptions and still fail compilation with warnings off.

Only **dependency resolution** is isolated: a local-package import resolves to
the **published registry snapshot** (not your uncommitted edits), and a
third-party import resolves to its **latest** registry version, which can differ
from your workspace's pinned versions — so verify dependency-API probes against
the workspace, not mbtx. Use it for self-contained scripts; to exercise
your working-tree code, add a `*_test.mbt` to that package and run `moon test`
via shell.

## Sandbox policy and source-file protection

The default wasm run carries a moonrun policy on every platform. The snippet
may read anywhere but may write only inside its own `@fs.tmpdir()` and any
caller-provided scratch lab; changing other workspace files belongs to the file
tools. Process spawning is checked against the implementation's allowlist; the
live tool description summarizes the command surface the model should use.
Allowed commands such as `moon fmt` or `git checkout` run as child processes
and are not subject to the guest filesystem rule.

Read-only review/explore roles add a best-effort macOS `sandbox-exec` profile
around the runner to deny writes to protected MoonBit source and manifest
files, including writes attempted by allowed child commands. Worker roles use a
separate profile that permits their own worktree and denies sibling/shared
roots. The moonrun policy remains the cross-platform boundary.

A denied write surfaces inside the program as a bare OS error (e.g.
`OSError("@fs.open(): \"keep.mbt\": Operation not permitted")`), which on its
own reads like a filesystem fault. When a sandboxed run's output shows such a
denial on a protected source path, the tool result appends an explanation: the
sandbox denied the write by design, the snippet should not try to work around
it, and source changes belong to the `edit` tool. The run is reported as an
error even if the snippet caught the failure and exited 0, matching `shell`.

The extra kernel profile is **best-effort** and may be unavailable inside a
nested sandbox; it is defense in depth, not the cross-platform policy. A denied
write is surfaced as a tool error with guidance instead of being mistaken for a
filesystem fault.

## Escalation

`definition` takes an optional `ask_approval` channel. Its presence is the
whole switch: with one wired, the schema grows an `escalated` boolean and the
description grows a paragraph about it; without one, neither exists.

A call with `escalated: true` resolves the question **before** anything is
created or spawned, and after every cheap check — a snippet with a bad `cwd`
fails on the `cwd` rather than spending someone's attention on a prompt for a
run that was never going to happen. A grant applies to that one call and
nothing else: there is no session-scoped permission and no remembered rule, so
the next escalating call asks again.

What a grant changes is exactly one thing: the generated policy file is still
written and simply not passed to `moon run`. Widening the document instead was
not available — its `fs.write` roots are canonicalized existing paths with no
wildcard, and "any program" has no spelling in `process.allow` short of
enumerating one — so *no policy* is both the honest description of what was
approved and the only thing the runtime can express. The `target` list does not
widen: `native` stays refused whatever the answer.

The three ways of not being granted are three different replies, because what
the model should do next differs for each — a person's refusal is final for the
task, a withdrawn request decided nothing, and an absent channel means the
argument is unusable here and the snippet should be retried without it.

```mbt check
///|
async test "mbtx escalation is refused without a grant" {
  let asked = []
  let definition = @mbtx.definition(
    workspace_root=".",
    approval=ApprovalChannel(ask => {
      asked.push(ask.detail)
      Rejected
    }),
  )
  // The argument exists here because a channel is wired.
  let JsonSchema(schema) = definition.schema
  guard schema is { "properties": Object(properties), .. } else {
    fail("expected an object schema")
  }
  assert_true(properties.contains("escalated"))
  let action = match definition.execute {
    Async(execute) =>
      execute({ "source": "fn main { println(1) }", "escalated": true })
    Sync(_) => fail("mbtx is async")
  }
  guard action is Respond(output) else { fail("expected Respond") }
  assert_true(output.is_error)
  assert_true(output.content.contains("declined"))
  // The question stated what would be granted; it carried no copy of the
  // program, which the transcript already shows.
  assert_eq(asked, [
    "run this snippet with no sandbox policy: no spawn allowlist, and writes anywhere",
  ])
}
```

## Examples

A quick language probe — no imports, pure core:

```mbt check
///|
async test "mbtx runs a pure-core probe" {
  let action = match @mbtx.definition(workspace_root=".").execute {
    Async(execute) =>
      execute({ "source": "fn main { println([1, 2, 3].map(x => x * x)) }" })
    Sync(_) => fail("mbtx is async")
  }
  debug_inspect(
    action,
    content=(
      #|Respond(
      #|  {
      #|    content: "[1, 4, 9]\n",
      #|    is_error: false,
      #|    brief: Some("mbtx (exit=0)"),
      #|  },
      #|)
    ),
  )
}
```

The workspace root is also the snippet's default working directory, so a
checked example can exercise real file IO through a relative path:

```mbt check
///|
async test "mbtx reads a workspace file" {
  @vfs.with_tmpdir(prefix="mbtx-readme-io-", workspace => {
    @fs.write_file(
      workspace + "/data.txt",
      "Ada\nGrace\n",
      create_mode=CreateOrTruncate,
    )
    let source =
      #|import { "moonbitlang/async", "moonbitlang/async/fs", "moonbitlang/async/stdio" }
      #|
      #|async fn main {
      #|  let text = @fs.read_file("data.txt").text()
      #|  let lines = [..text.split("\n")].filter(line => !line.is_empty())
      #|  @stdio.stdout.write("lines=\{lines.length()}\n")
      #|}
    let action = match @mbtx.definition(workspace_root=workspace).execute {
      Async(execute) => execute({ "source": source })
      Sync(_) => fail("mbtx is async")
    }
    debug_inspect(
      action,
      content=(
        #|Respond(
        #|  {
        #|    content: "lines=2\n",
        #|    is_error: false,
        #|    brief: Some("mbtx (exit=0)"),
        #|  },
        #|)
      ),
    )
  })
}
```

Pure snippets can select another supported backend explicitly:

```mbt check
///|
async test "mbtx accepts an explicit target" {
  let action = match @mbtx.definition(workspace_root=".").execute {
    Async(execute) =>
      execute({ "source": "fn main { println(6 * 7) }", "target": "js" })
    Sync(_) => fail("mbtx is async")
  }
  debug_inspect(
    action,
    content=(
      #|Respond({ content: "42\n", is_error: false, brief: Some("mbtx (exit=0)") })
    ),
  )
}
```

Warnings are quiet by default and can be restored for diagnostic probes:

```mbt check
///|
async test "mbtx can show compiler warnings" {
  @vfs.with_tmpdir(prefix="mbtx-readme-warning-", workspace => {
    let execute = match @mbtx.definition(workspace_root=workspace).execute {
      Async(execute) => execute
      Sync(_) => fail("mbtx is async")
    }
    let source = "fn main { let unused = 1; println(\"done\") }"
    let quiet = execute({ "source": source })
    let loud = execute({ "source": source, "warning": "on" })
    guard quiet is Respond(quiet_output) else { fail("expected Respond") }
    guard loud is Respond(loud_output) else { fail("expected Respond") }
    assert_false(quiet_output.is_error)
    assert_false(quiet_output.content.contains("Warning"))
    assert_false(loud_output.is_error)
    assert_true(loud_output.content.contains("unused"))
  })
}
```

Reading and transforming a file (what you pass as `source`) — note the inline
import block, with `moonbitlang/async` present so `async fn main` compiles:

```mbt nocheck
///|
import {
  "moonbitlang/async",
  "moonbitlang/async/fs",
  "moonbitlang/async/stdio",
}

///|
async fn main {
  let text = @fs.read_file("data.txt").text()
  let lines = [..text.split("\n")].filter(l => !l.is_empty())
  @stdio.stdout.write("lines=\{lines.length()}\n")
}
```

Probing a language feature (what you pass as `source`):

```mbt nocheck
///|
fn main {
  let classify = c => {
    match c {
      'a'..='z' => "lower"
      '0'..='9' => "digit"
      _ => "other"
    }
  }
  println(classify('k'))
  println(classify('7'))
}
```
