# The shell execution model

> Status (2026-09-11): the execution model is kept (`agent_tool/shell_exec`,
> `bgjobs`, `job_output`, `job_stop`, `job_wait`). The model-facing `shell`,
> `shell_output`, and `shell_stop` tools this document describes as shipped
> were removed in 43b5ea224; commands now run as `mbtx` snippets over the same
> execution objects.

A single, layered model for running shell commands — foreground and background —
in the OpenSeek agent. This document is the architecture north star; the code is
organized to match it, foundation-first.

## The one idea

A shell command is **one process object with one output owner and one status
flag.** "Foreground" vs "background" is not two code paths — it is only *whether a
tool call is currently awaiting the object*. Detaching a command is therefore a
**status flip**, not a re-route or a conversion.

This is the lesson of the earlier attempt (a spike on `spike/detach-on-timeout`):
routing a foreground command *through* a separate background-job runtime on
timeout failed, because the two runtimes had opposite, lossy policies (output
retention prefix-vs-tail, output-limit kill-vs-continue, exit notify-vs-not), and
reconstructing a foreground result from a background snapshot discarded the
information. The fix is not to reconcile two runtimes — it is to have **one**.

## The layers

```
┌─────────────────────────────────────────────────────────────┐
│ tools:  shell (run_in_background, foreground, detach)        │  L3
│         shell_output (poll) · shell_stop (cancel)            │
├─────────────────────────────────────────────────────────────┤
│ integration: push-completion notice · serve-loop wake · TUI │  L3.5
├─────────────────────────────────────────────────────────────┤
│ registry:  BgJobRuntime — id → ShellExecution, on_exit hook │  L2
├─────────────────────────────────────────────────────────────┤
│ execution: ShellExecution — process + sink + status flag    │  L1
├─────────────────────────────────────────────────────────────┤
│ output:    ShellOutputSink — one owner, file-backed          │  L0
└─────────────────────────────────────────────────────────────┘
```

Each layer depends only on the one below. The registry, the tools, foreground,
and detach are all thin — the weight is in L0 and L1.

### L0 — `ShellOutputSink` (the future-proof output owner)

One owner for a command's merged stdout+stderr, with a single retention story so
foreground and background never disagree. **Memory-first, file-backed:**

- The parent reads the child's pipe (so output-limit and sandbox-denial checks
  keep working in-flight), decoding UTF-8 across chunk boundaries.
- Output is buffered in memory up to an **inline cap**. Past it, the sink
  **spills the full output to a file** (opened lazily under a session temp dir)
  and keeps only a bounded in-memory *head* for cheap inline rendering.
- The **file is the source of truth for full output** — so a reader can later
  ask for any window (prefix / tail / all / range) without the sink having to
  pre-commit to one. That is what makes this future-proof: retention is no longer
  a policy choice baked into the buffer; it is a read-time decision.
- `inline_or_pointer`: small output renders inline; large output renders a
  `<system>output_file=… size=…>` pointer plus a head preview, and the model
  reads the rest with `shell_output`.
- A **hard cap** bounds the file (disk), enforced by the size watchdog (L1).

Why memory-first rather than always-file (Claude Code's bash mode writes straight
to a file): the agent runs a flood of tiny commands (`ls`, `git status`); keeping
those in memory avoids a temp file per command, and the file appears only when
output is genuinely large — where its cost is already justified.

### L1 — `ShellExecution` (the shared process object)

`status : Running | Backgrounded | Exited(Int) | Killed`. Owns the process
(spawned on the **session** task group, so it can outlive a single tool call and
be detached), the sink, and a monitor task (concurrent pipe reader + the
authoritative `process.wait()` + drain-to-EOF + terminal flush). Methods:

- `wait()` — await terminal; `stop()` — cancel and await terminal.
- `request_stop()` — **synchronous** cancel (uses the sync `Process::cancel`), so
  a cancelled turn can stop a session-group execution during unwinding, where
  awaiting is unsafe — otherwise it orphans.
- `background()` — flip `Running → Backgrounded`, disabling the foreground
  output-limit kill (a detached job keeps running like any background job).
- `kill_when_full` — foreground semantics: kill an un-timed runaway once the sink
  fills, so it cannot hang the tool call.
- size watchdog — kill a job whose spill file passes the hard cap (disk guard).

### L2 — `BgJobRuntime` (the registry)

`id → { command, cwd, ShellExecution }`. Non-generic (captures the session group
in a spawn closure) so it can be an optional tool argument. `start` spawns + adopts;
`adopt` registers an already-running execution (this is how detach works);
`snapshot`/`list`/`stop` delegate to the execution; a per-job watcher fires
`on_job_exit` once on a natural exit (the push-completion hook).

### L3 — tools, and L3.5 — integration

- `shell`: foreground runs through a `ShellExecution` (via a spawner the agent
  wires); `run_in_background:true` starts a job; an omitted `timeout_ms`
  defaults (120s wired / 600s unwired, max 600s explicit) so no foreground
  wait is unbounded, jobs are reaped after 30 minutes of wall clock, and a
  `timeout_ms` that elapses
  **detaches** (background + adopt) rather than kills; turn cancellation
  `request_stop`s the execution.
- `shell_output` / `shell_stop`: poll and cancel — they read straight through the
  registry, i.e. the shared sink, so they need no output logic of their own.
- Push-completion: `on_job_exit → runtime.queue_steer(Notice(…))`, delivered to
  the model at the next step boundary; an idle serve engine is woken by a
  `BackgroundNotice` step and the notice rides an **untagged** event so it
  survives the TUI's stale-run guard; the notice persists as a `Runtime` item.

## Foundation-first delivery (the PRs)

Re-authored from `origin/main` so the history *is* the architecture — no
build-an-old-model-then-refactor. Each PR is one coherent layer, reviewable on
its own, with the layer below already in place.

- **PR 1 — the model (L0–L2).** `agent_tool/shell_exec` (`ShellOutputSink`
  file-backed + `ShellExecution`) and `agent_tool/bgjobs` (registry on it). Pure
  infrastructure, fully unit-tested against real processes, no tool wiring. This
  PR carries the architecture overview.
- **PR 2 — the tools (L3).** `shell` `run_in_background`, `shell_output`,
  `shell_stop`; foreground routed through `ShellExecution`; detach-on-timeout;
  cancellation cleanup. The user-facing surface.
- **PR 3 — integration (L3.5).** push-completion, the serve-loop wake, the
  untagged notice event, and TUI rendering.

Commit gate for every commit: `moon fmt` → `moon check --target native <pkgs>` →
`moon test <pkgs>` → `codex review --base <prev-sha>` (fix real findings,
re-review clean) → regenerate `.mbti` (`moon info`).

## Test plan

Principles: **native target** (async spawn); **deterministic polling** (bounded
ticks + `@async.sleep`, `fail` on a deadline, fast commands with a real sleeper
only for stop/timeout); **isolation** (parallel async tests, per-test temp
cwd/spill dir); **regression** (the full `agent_tool/shell` suite green; the
scope-less `collect_shell_output` path that the TUI `!` uses stays byte-identical).

Per layer:

- **L0 sink** — small output inline, no file; output past the inline cap spills,
  `read_all` returns everything (prefix intact), the head is a bounded preview,
  `over_inline_cap` flips, UTF-8 split across a chunk *and* the spill boundary is
  not corrupted, a non-positive budget is clamped, the hard cap truncates, a
  file-open failure degrades to memory (never crashes).
- **L1 execution** — exit code captured; `stop`/`request_stop` → `Killed`;
  `background` → `Backgrounded` and keeps running; `kill_when_full` stops a
  runaway; descendant-holds-pipe still terminates; the watchdog kills an
  over-cap spill.
- **L2 registry** — `start`/`snapshot`/`list`/`stop`; `adopt` an existing
  execution; `on_job_exit` fires once on natural exit, never on stop; unknown id.
- **L3 tools** — foreground bytes match the old path for small output; large
  output returns the file pointer and `shell_output` reads the remainder;
  `run_in_background` returns an id and enforces guards before spawning; a
  timed-out foreground command detaches; a cancelled turn leaves no orphan.
- **L3.5 integration** — notice decode; serve idle-wake untagged event; TUI `⚙`
  render; notice persists as a `Runtime` item.

## Status of the earlier stack

PRs #375 / #378 / #380 delivered this feature in historical order (explicit jobs →
push → unify-and-refactor) with a bounded *pure-memory* sink. This re-author
supersedes them: same behavior and the same hard-won lessons (detach = flip,
untagged idle notice, sync cancel cleanup), but foundation-first and with the
**file-backed** output layer that makes large-output and tail-follow first-class
instead of deferred. The superseded flawed detach attempt remains on
`spike/detach-on-timeout` as a cautionary reference.
