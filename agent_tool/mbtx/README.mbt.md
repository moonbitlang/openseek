# mbtx

Compile and run a **self-contained MoonBit program** and return its merged
stdout/stderr and exit status. It is the agent's way to *script in MoonBit* —
for automation (read and transform files, parse JSON, compute) and for probing
how a language feature behaves — instead of reaching for shell `python`/`node`.
The default wasm backend runs under moonrun's policy, making it the natural
sandboxed automation surface.

## How it works

The `source` is a `.mbtx` **single-file script** — MoonBit's own one-file
program format. The tool writes it into a throwaway directory and, for the
default wasm target, runs it in **two phases**. The BUILD runs first,
synchronously: `moon run <file>.mbtx --build-only --target wasm --target-dir
<temp>`, bounded by its own wall clock (10s by default) so a hung dependency
download cannot hold the turn. A nonzero exit here is reported immediately as
`BUILD failed (exit N)` — a build failure **by construction**, since the run
phase never starts; no exit-code or output archaeology is needed to tell the
stages apart, which matters because `moon run` alone exits 1 for a rejected
build and a trapped program alike, and diagnostics in a merged stream prove
nothing (a snippet legitimately runs `moon check` as a child process). On
success the RUN phase execs `moonrun` directly on the artifact moon reported
in its `{"artifacts_path":[…]}` line — the same process `moon run` would have
exec'd — with the workspace (or explicit `cwd`) as the program's working
directory, so relative reads reach workspace files while build artifacts stay
out of your `_build`. A failure there is labeled `at RUNTIME — … from the
run, not the build`. Compiler diagnostics are rewritten to stable
`source:LINE:COL` locations, and build output (warnings under
`warning: "on"`) is kept apart from program output by construction. The
non-wasm targets keep the single-shot `moon run` and their reports claim no
stage.

With the agent's background runtime, every call's RUN waits inline for up to
five seconds — build time deliberately does not count against that allowance.
A still-running program is then adopted as the same background execution: the
call returns its job id, completion is pushed later, and its compiler inputs
and build artifacts are reclaimed when the job becomes terminal. An adopted
job is therefore always a running program, never a build. Files the snippet
writes under its temporary result directory remain readable until session
teardown, so paths printed in completion output stay valid. There is no
foreground/background argument to choose. A standalone definition without a
job runtime stays in the foreground for up to 300 seconds of run time and is
cancelled at that deadline.

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

## Hosting a workflow

Two decisions, made by two parties.

The CLI says whether this session CAN host: `definition(…, subrun?)` takes a
`SubrunInjection` from `agent_subrun/host` — the engine path, the session store, the parent id, and the
session's one child-ordinal allocator — when the conversation has a durable
session, and nothing when it does not (a `--no-session` run, a read-only
child's own snippets). That is a capability, not a switch.

The model says whether this snippet WILL delegate: the `subrun: true` argument.
Only then does the tool reserve a block of 32 child ordinals, create a run
directory in the session store, write a `WORKFLOW_HOST` handoff into the guest
environment for `moonbitlang/workflow/hosted` to read, admit the engine to the
spawn allowlist (by absolute path, `subrun` only), grant the run directory as
the one writable store path, and announce the run with `workflow_started`.
Every other snippet gets none of that — reserving children a script never
starts would waste ids and announce a workflow that does not exist.

Asked on a session that cannot host, the call is refused with a result that
says why, rather than running the snippet without the coordinates it expects
and letting its subagents vanish. And whether or not the flag is set,
`WORKFLOW_HOST` is always DECIDED by the policy — the handoff, or nothing — so
a child engine's snippet can never inherit its grandparent's handoff and mint
child ids from a block that is not its own.
