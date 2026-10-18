# Plan: subagents as engine-owned background jobs

Date: 2026-10-18. Status: proposal, not implemented. It replaces the draft in
#1872 (branch `subagents-design`, four external review rounds) and makes the
allocator in #1874 unnecessary if the "Ids" section holds. Findings of those
rounds that still apply are kept and marked *(#1872 rN)*.

## Direction

- **One launcher, in the engine, with two entrances.** The model calls a tool;
  a script calls the same tool through `@tools.call`. This is one mechanism, so
  it does not repeat what got `explore` (#1318) and `subtask` (#1320) removed:
  two parent-side paths that launched the same child, which dogfood used
  neither of.
- **Children run for hours.** Nothing may hold the host, a turn, a tool call or
  a script connection for a child's lifetime. Starting returns at once.
- **A subagent is a specialized background job.** It shares the job
  lifecycle (ids, stop, the loop-owned wait, the exit notice, the jobs panel,
  retained records) and adds a typed record of its own (kind, child session,
  outcome, usage, workspace) so a host can show it as an agent, and later as a
  worker with a worktree.
- **Simple.** One new tool to start a child. Waiting, reading and stopping
  use the job tools the model already knows.

## Today

- The model delegates only by writing a `moonbitlang/workflow` snippet and
  calling `mbtx(subrun=true)`. The SNIPPET spawns `openseek run --kind …`
  through `moonbitlang/workflow/hosted`; the engine reserves 32 child ordinals
  in memory beforehand (`agent_subrun/host`, `agent_subrun/injection.mbt`) and
  sees the children only through their transcripts.
- `subrun` and PTC exclude each other (`agent_tool/mbtx/mbtx.mbt:200`).
- The one engine-launched child is the goal-met gate's reviewer, through
  `@agent_subrun.run_subrun` (`internal/openseek/execution/gate.mbt:102`).
  It is a blocking call that brackets the child with turn-scoped
  `SubrunStarted`/`SubrunFinished` events.
- `run_subrun` spawns through `moonbitlang/workflow/spawn` (`contract_run`),
  which returns only when the child ends. The child is
  `openseek run --input-format json --cancel-on-stdin-eof --kind <k>
  --result-file <f> --session <parent>-sr-N`; it refuses a session that
  already exists (`internal/openseek/run/run.mbt:356`).
- Background jobs (`agent_tool/bgjobs`): one `BgJobRuntime` per session, job
  ids are UUIDv7, records persist under `sessions/<id>/jobs/<generation>`,
  `JobChanged(kind, JobRecord)` is emitted session-wide (the desktop's jobs
  panel), a natural exit queues a lossless `Notice` and wakes an idle
  controller (`agent/tool_definition.mbt:144`). A 30-minute wall-clock reaper
  applies to every job (`bgjobs.mbt:37`). The registry wraps
  `@shell_exec.ShellExecution` only.
- `job_wait` is a loop control (`WaitJobs`) with no timeout; user input
  interrupts it. PTC rejects loop controls, so a script cannot call it.
- PTC: 120 s per call on the server (`agent_tool/ptc/server.mbt:230`, exempt
  for approval-capable tools), 125 s in the SDK (`tools_sdk/client.mbt:51`),
  four active calls per program, sixteen connections. The program registry is
  the file tools plus extras (`agent/tool_definition.mbt`).
- Worker machinery is dormant: `agent_worker` (the kind, still runnable),
  `agent_subtask` (provision, capture, integrate, discard; no importer outside
  its own tests), the worker sandbox profile.

## Design

### The record

`JobRecord` (protocol) gains one optional, typed part:

```
subagent : SubagentInfo?        // None for every other job

SubagentInfo {
  kind : String                 // "explore" | "review" (later "worker")
  label : String
  session : String              // "<parent>-sr-N"
  owner : SubagentOwner         // Model | Program(job id of the script)
  outcome : SubagentOutcome?    // None while running
  usage : SubagentUsage?        // None until known; never zeros for unknown
  workspace : SubagentWorkspace // InPlace (first stack); Worktree{..} later
}
SubagentOutcome = Captured | NoReport | MaxSteps | ContextYield | TimedOut
                | Failed(String) | Stopped | OwnerLost
SubagentUsage { steps, prompt_tokens, completion_tokens, cost_usd?,
                source : Result | Transcript, unaccounted : String? }
```

- The job's own state (`Running`, `Exited`, `Stopped`, `Interrupted`) stays
  the process fact; `outcome` is what the child achieved *(#1872 r3:
  process outcome and change state are separate)*.
- Visualization rides `JobChanged`, which is session-scoped. The launcher does
  NOT emit `SubrunStarted`/`SubrunFinished`: those are turn-scoped and a child
  outlives its turn *(#1872 r3)*. The gate keeps its brackets.
- Additive in the session log and the protocol: an old reader ignores the
  field (forward compatibility is a non-goal, so no version bump).

### Running a child as a job

The child is a process, so it fits the job runtime, but not as a shell
execution: it has a request on stdin that must stay open (closing it is the
graceful cancel), a result file that decides the outcome, and stdout that is
only a human log.

Proposal: the job runtime gains a second job body beside the shell
execution, an *agent* body: spawn the child, hold its stdin, capture stdout
as the job log, and on exit read the result file into `SubagentInfo` before
the terminal `JobChanged` and the exit notice. Stop closes stdin, waits a
short grace, then terminates. Everything else (ids, records, retention,
stop, wait, notices, teardown) is shared.

Alternative: keep the runtime shell-only and run the child through
`run_subrun` in a session task, registering a job record by hand. Rejected
here because it duplicates the registry, stop and notice paths; open to the
reviewer's judgment.

Limits: subagent jobs are exempt from the 30-minute reaper. A child is
bounded by its step budget, its context ceiling, and an optional per-start
wall deadline (none by default).

### Starting: the `subagent` tool

`subagent(kind, input, label?, max_steps?)`.

- `kind`: `explore` or `review` in the first stack; anything else is refused.
  `input` is exactly what `run --kind <kind>` takes. `max_steps` is clamped to
  the kind's ceiling. A child does not get this tool (no nesting).
- Admission, with no suspension: refuse if four subagents are already
  running in the session (`busy`, retry after one ends, costs nothing), if a
  program is over its quota (32 starts), or if the session has no durable
  store (`unavailable`). A slot is taken at admission and returned when the
  child's teardown completes *(#1872 r4)*.
- Returns at once. The model reads `content`, never `data`, so the result is
  text: the job id, the child session, and how to wait/read/stop. A script
  reads `data`: `{job_id, session}` *(#1872 r3)*.
- Concurrent-safe, so a script's starts never queue behind the file gate.

### Waiting, reading, stopping

- **The model** uses `job_wait` (loop-owned, no timeout, user input
  interrupts), `job_output` and `job_stop` unchanged in name. `job_output` on a
  subagent job renders the outcome, usage and the report itself (bounded; a
  large report names its file). The exit notice is the existing one, with the
  outcome in its text, so the model need not wait at all.
- **A script** never holds a call for a child's lifetime *(#1872 r1: SDK
  125 s, four active calls, sixteen connections, a retried start pays
  twice)*. It gets program-callable registrations of the same runtime:
  - `job_wait` for programs: level-triggered, returns when any listed job has
    ended or after at most 60 s, with every listed job's current state; ids
    validated as a whole, unknown or foreign ids refused *(#1872 r2)*;
    concurrent-safe; one wait in flight per program.
  - `job_output` and `job_stop` for programs, limited to jobs the program
    started.
- The report is stored at `sessions/<child>/report.json` after the child is
  reaped (the child creates its own session directory; the result file lives
  in a temporary directory). A failed store keeps the outcome and returns the
  report inline while this engine holds it *(#1872 r4)*.

### Owners

- **Model**: the child belongs to the session; it survives turns and context
  yields. A plain-text finish with running children gets the existing
  pending-jobs decision; an explicit `finish` passes.
- **Program**: when the script's program closes (exit, cancel, `job_stop` on
  the script's job), its unfinished children are stopped. Adoption into the
  background keeps the owner.
- **The gate**: unchanged; not a job, not addressable by these tools.
- The user's Cancel stops the turn, not the model's children: they are
  background jobs and the jobs panel stops them. *(Reverses #1872, which
  stopped them on Cancel; children here run for hours.)*

### Ids

Only the engine allocates once `subrun=true` is retired. Proposal: the
filesystem is the allocator. The engine claims `<parent>-sr-N` by creating
that session directory exclusively (`mkdir` fails if it exists), retrying with
the next ordinal on a collision, and passes it to the child with a flag that
lets a `--kind` run adopt the empty, engine-created directory. Two engine
processes on one session then cannot share a child, a restart loses nothing it
handed out, and no ledger or lock file is needed.

During the transition the hosted path still reserves blocks of 32 in memory,
so the case #1874 fixes (an engine that dies while a snippet holding unused
ordinals lives on) stays open until PR 5. A claim on an existing directory is
refused rather than shared, so the failure is a refused child, not two
children writing one transcript.

### Restart

A child is launched to cancel when its stdin closes, so it ends with the
engine. Its job record in the next generation reads `Interrupted`, its outcome
`OwnerLost`; its transcript is kept; it is not resumed. Surviving a restart is
later work.

### Desktop

- A subagent job renders as an agent, not a command: kind, label, live state,
  steps and tokens, a link to the child's transcript (the sidebar already folds
  `sr-N` sessions under their parent), and a stop control.
- A transcript card at the `subagent` call, updated by `JobChanged`.
- Workers later: branch, diff, integrate and discard.

### Workers (later in the stack)

- `workspace = Worktree { path, branch, base }`, provisioned by the engine
  through `agent_subtask` when a worker starts; the caller never runs
  `git worktree`.
- Outcome and change state stay separate; the change state (none, defective,
  committed, conflicted, integrated, discarded) is a second typed field.
- Integration targets the checkout that launched the worker, which may be a
  linked worktree. Overlap is repository-wide: admission takes a lock under
  the common git directory *(#1872 r3)*.
- In-place mode (one at a time, the launcher's edits refuse while it runs) as
  in #1872.

### Messaging (later in the stack)

`subagent_send(job_id, message)`, carried over from #1868–#1871: an inbox per
receiving session, read at the loop's steer points, receipts read off the
child's transcript, the sender is always the parent session.

## Stack

1. **Runtime and protocol.** `SubagentInfo` on `JobRecord`; the agent job body
   in `bgjobs` (spawn, held stdin, result file, graceful stop, per-job time
   limit); the claimed child session directory. No tool.
2. **The `subagent` tool for the model.** `explore` and `review`; admission,
   slots, no nesting; `job_output` and the exit notice render subagent jobs;
   prompt paragraph and a verified example.
3. **The script entrance.** `subagent` in the program registry; owner-bound
   program registrations of `job_wait` (bounded), `job_output`, `job_stop`;
   program close stops its children; `review.mbtx` moved onto it.
4. **Desktop.** Agent rows and the transcript card. Depends only on 1.
5. **Retire `subrun=true`.** Move `repo-map.mbtx` and `change-review.mbtx`;
   delete the hosted handoff, the spawn rule and the in-memory reservation.
6. **Messaging.** `subagent_send`.
7. **Workers: engine.** Worktree provisioning and the change state.
8. **Workers: integrate and discard**, for the model and scripts.
9. **Workers: desktop.** Branch, diff, integrate, discard.

Later: a per-child model, a spend limit, surviving an engine restart, reviews
started by the audited agent (see #1872 "Reviews").

## Integrated testing

Three layers, all offline, plus one live check.

1. **Package tests with fake children.** A script that speaks the workflow
   child contract (as `agent_subrun/runner_test.mbt` does): captured, no
   report, crash, hang, slow exit after stdin closes, a report that cannot be
   stored. They cover the job body, the record, stop and the reaper exemption.
2. **The real CLI against a scripted provider**, extending the harness in
   `tests/integration/turn_finish.mbtx` (a local HTTP server answering
   `/chat/completions` with scripted tool-call deltas, `--api-url` pointed at
   it). The engine forwards `--api-url` to its children, as the gate does, so
   the SAME server scripts both the parent and the real child binary,
   telling them apart by the request's system prompt. Scenarios:
   - the model starts two children, waits with `job_wait`, reads both with
     `job_output`, finishes; the child sessions exist with transcripts and
     `report.json`; `JobChanged` carries `SubagentInfo` from running to ended;
   - a child that never answers is stopped with `job_stop`; outcome `Stopped`;
   - a plain-text finish with a running child gets the pending-jobs decision;
   - an idle end queues the notice and wakes the `serve` loop;
   - a fifth start is refused `busy`.
3. **Scripts through the real PTC service.** A compiled snippet that fans out
   with a task group, waits with the bounded `job_wait`, reads and stops, run
   by `mbtx` against the scripted provider; plus `@builtin/review.mbtx` in
   `tests/integration/workflows` once it moves.
4. **Desktop.** The e2e suite with a session fixture containing subagent job
   records: the row, the card, opening the child transcript, stop.
5. **Live, by hand.** One `deepseek-v4-pro` session on a real repository task
   that delegates, checked in the desktop.
