# Plan: subagents as engine-owned background jobs

Date: 2026-10-18. Status: proposal, revised after three external architecture
review rounds (findings at the end); ready for PR 1. It replaces the draft in #1872
(branch `subagents-design`, four review rounds) and makes the allocator ledger
in #1874 unnecessary. Findings of those rounds that still apply are kept and
marked *(#1872 rN)*.

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
  outcome, usage, report, workspace) so a host can show it as an agent, and
  later as a worker with a worktree.
- **Simple.** One new tool to start a child. Waiting, reading and stopping
  use the job tools the model already knows.

## Today

- The model delegates only by writing a `moonbitlang/workflow` snippet and
  calling `mbtx(subrun=true)`. The SNIPPET spawns `openseek run --kind …`
  through `moonbitlang/workflow/hosted`; the engine reserves 32 child ordinals
  in memory beforehand (`agent_subrun/host`, `agent_subrun/injection.mbt`) and
  sees the children only through their transcripts. `@builtin/review.mbtx`
  also reads the standing goal and baseline from that handoff
  (`WORKFLOW_HOST.openseek.audit`, `share/workflow/review.mbtx:64`).
- `subrun` and PTC exclude each other (`agent_tool/mbtx/mbtx.mbt:200`).
- The one engine-launched child is the goal-met gate's reviewer, through
  `@agent_subrun.run_subrun` (`internal/openseek/execution/gate.mbt:102`), a
  blocking call that allocates from a process-local counter
  (`agent_subrun/runner.mbt:125`) and brackets the child with turn-scoped
  `SubrunStarted`/`SubrunFinished`. The desktop starts its progress probe for
  a child on `SubrunStarted` (`desktop/backend/engine/engine.mbt:1833`).
- The child is `openseek run --input-format json --cancel-on-stdin-eof --kind
  <k> --result-file <f> --session <parent>-sr-N`. It refuses a session whose
  directory exists (`run.mbt:354`, `SessionStore::exists` tests the
  directory, `agent_session/store/store.mbt:482`). The spawn contract writes
  the request inside its deadline because a child that does not read can
  block the write (`moonbitlang/workflow/spawn/contract.mbt:162`).
- Background jobs (`agent_tool/bgjobs`): one runtime per session; UUIDv7 ids;
  records under `sessions/<id>/jobs/<generation>`; session-scoped
  `JobChanged(kind, JobRecord)`; a finish sequence of cleanup → frozen data →
  terminal publication → notice → waiter release (`records.mbt:173`); no
  update after `Published` (`records.mbt:134`); a 30-minute reaper for every
  job (`bgjobs.mbt:37`), which also reaps an adopted `mbtx` script; a 20 M
  character output watchdog. A natural exit queues a lossless notice; between
  turns that notice is persisted and does NOT start a model turn
  (`internal/openseek/serve/loop.mbt:358`). The finish guard covers jobs
  created during the current turn only (`agent/job_wait.mbt:4`). One-shot
  `run` owns its jobs on the turn's task group (`run/turn.mbt:27`).
- `job_wait` is a loop control with no timeout; user input interrupts it. PTC
  rejects loop controls.
- PTC per program: 120 s per call (server), 125 s (SDK), four active calls,
  1,024 calls, 512 KiB retained trace, 64 K-character replies; sixteen
  connections per session. One registry serves every program
  (`agent_tool/ptc/server.mbt:558`); a program's job id is `None` until
  adoption (`server.mbt:285`, `:375`).
- Worker machinery is dormant: `agent_worker` (the kind, still runnable),
  `agent_subtask` (provision, capture, integrate, discard, a registry under
  the common git directory, `agent_subtask/registry.mbt:30`; no importer
  outside its own tests), the worker sandbox profile.

## Design

### Packages

- `agent_tool/bgjobs` stays generic. It gains an *execution policy* per job
  (time limit, graceful stop) and an optional typed subagent supplier beside
  its untyped `data`. It does not import anything about agents.
- The request and result codecs already live in the protocol
  (`@protocol.RunRequest`, `@protocol.parse_run_result`,
  `protocol/run_request.mbt`, `protocol/run_result.mbt`); the launcher uses
  them and the kinds' report parsers, not the workflow library's private
  codec. `agent_subrun` keeps the gate's blocking path.
- A new `agent_subagent` package is the launcher: admission, the claim, the
  child's command line, request delivery, result validation, the record.
  It depends on `bgjobs` and `agent_subrun`, never the reverse (`agent_subrun`
  already depends on `agent_tool → bgjobs`).

### The record

`JobRecord` gains one optional, typed part; `None` for every other job.

```
SubagentInfo {
  kind : String                  // "explore" | "review" (later "worker")
  label : String
  session : String               // "<parent>-sr-N"
  owner : SubagentOwner          // Model | Program(ProgramId)
  launch : SubagentLaunch        // Direct | Script(ProgramId, call index)
  outcome : SubagentOutcome?     // None while live
  usage : SubagentUsage          // Known{..} | Unavailable(reason)
  report : SubagentReport?       // None until ended
  workspace : SubagentWorkspace  // InPlace now; Worktree{subtask} later
}
SubagentOutcome = Captured | NoReport | MaxSteps | ContextYield | TimedOut
                | Stopped | Failed(String)
SubagentUsage   = Known { steps, prompt_tokens, completion_tokens, cost_usd?,
                          source : Result | Transcript, unaccounted : String? }
                | Unavailable(String)
SubagentReport  = Stored(path) | Absent | StoreFailed(String)
```

- The job's state (`Running`, `Stopping`, `Exited`, `Stopped`) stays the
  process fact; `outcome` is what the child achieved *(#1872 r3)*.
- `report` is separate from `outcome`: a captured report whose store failed
  is still `Captured`.
- **Live progress is read from the child's transcript by whoever shows it**,
  not pushed through the record: the desktop's existing probe
  (`@subrun.follow_progress`) is started by `JobChanged(Started)` carrying a
  `SubagentInfo` instead of by `SubrunStarted`, is owned by the session's
  engine connection, and is stopped on the terminal `JobChanged` or when the
  engine goes away; `job_output` on a live child counts steps from the
  transcript on demand. The record carries final usage.
- **Correlation.** A script launch is `Script(ProgramId, call index)`: both
  exist from the first call, before any adoption, and the program trace
  records the same pair; the script's job id, once it has one, is an
  optional association on the program, not part of the key. A direct launch
  is found by the job id in the `subagent` tool result, which the transcript
  stores under the model's tool-call id. A tool executor does not see that id
  today, and the plan does not thread it through: if the engine dies between
  launching and returning the result, the child appears as a row with no
  card.
- The launcher emits no `SubrunStarted`/`SubrunFinished` (turn-scoped; a
  child outlives its turn) *(#1872 r3)*. The gate keeps its brackets.
- Additive in the session log and the protocol; an old reader ignores it.

### Allocation: claiming the child's session directory

Every producer of `<parent>-sr-N` with a durable session uses one claim:

1. Pick N from the process's ONE ordinal counter, the same one hosted
   reservations draw from (`agent_subrun/runner.mbt:282`), floored at one
   past the highest existing `<parent>-sr-*` directory. Taking N advances the
   counter, so a later hosted block starts after every claim and a claim
   starts after every block: coexistence holds in both directions.
2. Create `<parent>-sr-N` exclusively. Only "already exists" advances N and
   retries; any other failure refuses the launch as `unavailable`. From a
   successful create on, N is consumed whatever happens next.
3. Write a claim file inside it, `claim.json`, holding the SHA-256 of a
   random token, synced. The token itself is never on disk, so a snippet
   that can read the session store cannot accept someone else's claim. (It
   travels on the child's command line, which a same-user process can still
   read: the trust model stays cooperative.)
4. Pass the child `--claim <token>`. A `--kind` run given `--claim` accepts
   an existing session directory only if it holds exactly that claim file and
   no transcript, and renames the file away (the rename is the single-use
   acceptance), removes it and syncs the directory before its first record. Without
   `--claim` the existing refusal stands. This is a single-use handoff, not a
   general "accept an existing directory".
5. A directory with a claim file and no transcript is a child that never
   started; it is never reused (the ordinal stays taken).

A taken ordinal refreshes the floor from the store's listing, so a sibling
that launched many children since the session started costs one rescan, not
a refusal. A claim that fails launches nothing: no child id, no brackets.

The gate's reviewer uses the same claim in PR 1; its `--no-session` path is
unchanged. Two engine processes on one session cannot share a child, a
restart loses nothing it handed out, and no ledger or lock is needed.

**Coexistence with the hosted path.** In one engine process claims and
hosted blocks share the counter, so they do not collide. Across processes, or
after a restart while a snippet holding an unused block lives on, a hosted
child can still race a claim; that is today's exposure, not a new one, and
it ends when the hosted path is retired. To keep that window short, the
script entrance and the retirement land together (PR 3).

### Running a child as a job

The child is a process, so it fits the job runtime through the shell
execution (supplied stdin, independent stdout/stderr draining), with an
agent-specific policy:

- **Admission and ownership.** `subagent` runs in two parts.
  1. With no suspension: refuse if the owner is closed, over quota, or four
     subagents are live; otherwise take a slot and add a *pending* entry to
     the launcher's registry under its owner. From here the owner's close
     finds it. A refusal here takes no slot and no ordinal.
  2. With suspensions: claim the directory, spawn the child, register the
     job. After every suspension the entry rechecks its owner. If the owner
     closed, or any step failed, the entry rolls back what exists (stops a
     spawned child, releases the slot, removes the entry) and the call
     returns `stopped` or the failure. A claimed ordinal stays consumed; its
     directory remains as a stale claim.
  Closing an owner marks it closed with no suspension, then stops every live
  child and joins every pending entry, so nothing it accepted outlives it.
- **Request delivery** is owned background work with a 10 s bound: write the
  one request line, keep the pipe open. A failed or timed-out write records
  the termination cause `delivery_failed` and stops the child.
- **Graceful termination.** The managed child cancels on stdin EOF and then
  writes its result (`internal/openseek/run/run.mbt:147`, `:192`); it has no
  signal handling of its own. So the child is spawned with a CUSTOM process
  cancellation handler instead of the shell path's `hard_cancel`
  (`agent_tool/shell_exec/execution.mbt:125`): close the stdin writer the
  launcher owns, wait 10 s with no signal, then force-terminate. (The async
  library's `graceful_cancel` sends SIGTERM first and never closes stdin, so
  it would cut the flush short.) Every way a child is ended uses it:
  `job_stop`, a program close, session shutdown, the task group's
  cancellation.
- **Time limit.** Subagent jobs are not reaped at 30 minutes. A child is
  bounded by its step budget, its context ceiling and an optional per-start
  wall deadline (none by default). The 20 M output watchdog stays.
- **Termination cause.** Whatever ends a child first records exactly one
  cause: `stop` (job stop, owner close or shutdown), `delivery_failed`,
  `capture_failed` (the log could not be written), `output_limit`,
  `deadline`, or none for a natural exit.
- **Outcome precedence,** decided in the job's cleanup hook before the
  terminal record:
  1. a result file whose report passes the kind's validation and matches the
     request's id → `Captured`, whatever the cause (a report written during
     the grace still counts);
  2. cause `delivery_failed`, `capture_failed` or `output_limit` →
     `Failed` with that reason;
  3. cause `deadline` → `TimedOut`;
  4. cause `stop` → `Stopped`;
  5. the result file's own failure (`NoReport`, `MaxSteps`, `ContextYield`,
     `Failed`);
  6. otherwise `Failed` with the exit status.
- **Notices.** A natural end queues the existing notice, with the outcome in
  its text. A requested stop fires none (it is already visible). Shutdown
  fires none.
- **Report.** After the child is reaped, a captured report is written to
  `sessions/<child>/report.json` (sibling, then rename) *(#1872 r4)*. The
  engine keeps the report in memory too, so a failed store still serves
  reads from this engine.
  - *The model* gets text from `job_output`, bounded at 48,000 characters;
    beyond that it says the text is truncated and names the file.
  - *A script* gets the report as JSON in `data`. `job_output` for programs
    takes an optional `offset` and returns `{report_chunk, offset, total,
    complete}`: the report's serialized JSON split so that each ENCODED
    reply, envelope included, stays under 60,000 characters, measured the
    way PTC measures it (`agent_tool/ptc/server.mbt:603`). A script
    concatenates the chunks and parses the result; a report that fits in
    one reply comes back with `complete: true` and the parsed `report` too.
    A partial report is never presented as a complete one. This is how
    `review.mbtx` keeps reading structured findings and `repo-map.mbtx` its
    citations.
- **Slots.** Four live subagents per session, counted at admission and
  released when the job is `Published` *(#1872 r4)*.

### Starting: the `subagent` tool

`subagent(kind, input, label?, max_steps?)`.

- `kind`: `explore` or `review` in the first stack. `input` is exactly what
  `run --kind <kind>` takes; the launcher never fills or rewrites it. A
  review started this way is **advisory**: it is not the goal-met gate, whose
  criteria, channel and allowance stay its own.
- **The standing goal for scripts.** `@builtin/review.mbtx` combines the
  standing goal, the caller's audit focus and an explicit baseline override
  itself (`share/workflow/review.mbtx:86`); today it reads the goal and
  baseline from the hosted handoff. A read-only program tool,
  `audit_context`, returns the same `{goal, sha?, dirty?}` object the handoff
  carried (`WORKFLOW_HOST.openseek.audit`), or nothing without a standing
  goal. The builtin swaps its source and keeps its logic, so every review
  mode (goal, goal plus focus, focus alone, explicit `--sha`/`--dirty`, and
  `{base: ...}`) behaves as before. The model does not get this tool; it
  already sees its goal.
- `max_steps` is clamped to the kind's ceiling. A child does not get this
  tool (no nesting).
- Refusals (see the two-part admission above): `busy` with four live
  subagents (retry after one ends; costs nothing), `quota` past 32 starts
  for a program, `unavailable` with no durable session. These come from the
  no-suspension part and take no slot and no ordinal. A claim that fails in
  the suspending part is also `unavailable`; if the directory was created,
  its ordinal is consumed.
- Returns at once. The model reads `content`: the job id, the child session,
  and how to wait, read and stop. A script reads `data`: `{job_id, session}`
  *(#1872 r3)*. Concurrent-safe.

### Waiting, reading, stopping

- **The model**: `job_wait`, `job_output`, `job_stop`, unchanged in name;
  `job_output` gets a subagent branch (outcome, usage, report) instead of a
  log window.
- **A script** never holds a call for a child's lifetime *(#1872 r1)*:
  - a program registration of `job_wait`: level-triggered; returns when any
    listed job has ended or after at most 60 s, with every listed job's
    state; the id list validated as a whole; foreign or unknown ids refused
    *(#1872 r2)*; concurrent-safe; one wait in flight per program;
  - program registrations of `job_output` and `job_stop`, limited to the
    program's own subagents.
  Waits and reads count against the program's 1,024 calls and 512 KiB trace;
  the taught example waits on all its children in one call and reads each
  report once.

### Owners

- **ProgramId** is host-created at `Service::register`, before the script
  runs, and stays the same through adoption; the script's job id is attached
  to it when it has one. Authorization is bound to it, never to arguments or
  the bearer token. PTC dispatch becomes per program: each program gets its
  own instances of the owner-bound tools. A dropped connection is not a
  close.
- **Model-owned** children belong to the session; they survive turns,
  context yields and the user's Cancel (Cancel stops the turn; the jobs
  panel or `job_stop` stops a child). The finish guard keeps its current
  scope (jobs created in this turn). In one-shot `run` the session ends when
  the run does, so its children are stopped then.
- **Program-owned** children are stopped when the program closes (exit,
  cancel, `job_stop` on the script). A program that owns a live subagent is
  not reaped at 30 minutes. When its last child is `Published` (ended and
  collectible), a 5-minute collection allowance starts; starting another
  child cancels that allowance, and the next "last child published" starts
  a fresh one. When the allowance runs out, or at 30 minutes for a script
  that never had a child, the script is reaped as today.
- **The gate**: not a job and not addressable by these tools; it only shares
  the claim.

### Restart

A child cancels when its stdin closes, so it ends with the engine. Its job
record stays in the old generation. The desktop already derives
`Interrupted` for an old generation from its `owner.lock`
(`desktop/backend/engine/jobs.mbt:117`); a record with a `SubagentInfo` and
no outcome is shown as "ended with the engine". The new engine's
`job_output` does not read old generations; that stays desktop-only until a
later stack.

### Desktop

- A subagent job renders as an agent: kind, label, live state and progress,
  a link to the child's transcript (the sidebar already folds `sr-N` under the
  parent), and stop.
- A transcript card at the launch, correlated as above.
- Keep the idle reaper's rule that an engine with live jobs stays alive
  (`desktop/backend/engine/idle.mbt:84`).

### Workers (later in the stack)

- The worktree is provisioned by the engine through `agent_subtask`; the
  caller never runs `git worktree`. `workspace = Worktree { subtask }`, the
  identity of the entry in the `agent_subtask` registry.
- **That registry is the authoritative worker state** (launching checkout,
  branch, base, commit, scope defects, conflict, cleanup), because
  integration and discard happen after the job is `Published` and a job
  record takes no later updates. Its changes are published by a separate
  `WorkerChanged` event keyed by the job id.
- Outcome and change state stay separate *(#1872 r3)*; integration targets
  the launching checkout; worker admission takes a lock under the common git
  directory; PR 6 makes association, recovery and cleanup durable before any
  worker can be started.
- In-place mode as in #1872.

### Messaging (later, independent of the core stack)

`subagent_send(job_id, message)`, carried over from #1868–#1871.

## Stack

1. **Claims, runtime, protocol.** The claim (with `--claim`) for every
   durable child, the gate included, on the shared counter; the execution
   policy in `bgjobs` and the cancellation-handler seam in `shell_exec`;
   `SubagentInfo` in the protocol; the
   `agent_subagent` launcher with no tool in front of it, tested directly
   with fake children; `--claim` consumption tested through the real CLI;
   existing shell and adoption behavior kept covered.
2. **The model tool.** `subagent` for `explore` and `review`; `job_output`'s
   subagent branch; the notice text; prompt paragraph and verified example.
3. **The script entrance and retirement**, reviewed as two commits, merged
   together: (a) `ProgramId`, per-program dispatch, `subagent`, the program
   registrations of the job tools (chunked report reads), `audit_context`,
   the program reaper rule; (b)
   `review.mbtx`, `repo-map.mbtx` and `change-review.mbtx` onto it, and the
   hosted handoff, spawn rule and in-memory reservation deleted.
4. **Desktop.** Agent rows and progress (needs 1), then the launch card
   (needs 2 and 3).
5. **Messaging.** `subagent_send`.
6. **Workers: engine.** Durable worktree association, recovery, cleanup,
   `WorkerChanged`.
7. **Workers: start, integrate, discard** for the model and scripts.
8. **Workers: desktop.** Branch, diff, integrate, discard.

Later: a per-child model, a spend limit, surviving an engine restart, reading
old generations from model tools.

## As built

- PR 1 (#2071) and PR 2 (#2072): as planned.
- PR 3: one commit, not two, because the retirement touched the same files
  as the script entrance. `SubagentLaunch::Script.call` counts the script's
  subagent starts; the desktop correlates a script's child through the job id
  its trace records. The engine stops emitting `WorkflowStarted`, but the
  protocol event and the desktop's workflow view stay, because existing
  session logs contain them. The `subrun` argument is removed outright, with
  no compatibility path: a script delegates through `@tools.call`. The bundled workflows' offline tests run against a
  fake host that speaks the PTC protocol.
- PR 6: the launcher is the worker controller. `start(slice=…)` forks the
  worktree once the child's session is claimed, naming the registry entry by
  the parent session and the child's `sr-N`, so the entry alone says which
  worker it belongs to. The worker's geometry is added to its input, it runs
  in the worktree, and its changes are captured from git when its job ends,
  so the terminal record carries the worktree's state. `worktree(session,
  action)` integrates, continues or aborts an integration, or discards;
  `worktrees()` lists the session's worktrees and recovers any whose worker
  this engine never ran (captures it, or removes it if the engine died while
  forking). Changes after the job ended are `WorkerChanged`, keyed by the
  worker's session rather than its job id, because job ids do not survive an
  engine restart. The registry entry keeps the capture's defects, so an
  unmergeable worktree still says why after a restart. Admission stays the
  registry's in-process mutex; one engine per repository is still assumed.
- PR 7: `worker` is a kind of `subagent` that takes a `worktree` argument
  (`{name, allowed_paths}`); a kind says whether it changes code, and only
  such a kind takes one. At most 4 workers are live at once, within the
  session's subagent cap: each builds and tests in its own worktree.
  A first version also gave the model a `worktree` tool to integrate,
  continue, abort or discard after the job ended. It was replaced, after
  two live runs and an owner review ("too tied to git"), by a hand-off:
  - When the worker ends the engine captures its change (scope checked
    from git, committed on its branch with the pinned base as parent),
    retrying a few times when git itself fails, then releases the entry
    (`handed_off`, persisted before it is reported): its paths and name are
    free again. A committed slice keeps only its branch; an unmergeable or
    uncaptured one keeps its files at its path for inspection; one with no
    changes is removed.
  - The main agent takes the change with plain git through mbtx: `git diff
    <base> <commit>`, then `git cherry-pick <commit>` (or `git merge`, both
    now admitted by the mbtx policy), then `git branch -D <branch>`.
    `job_output` and the end notice give the commit, branch and base.
  - Each worktree has its own directory, `.worktrees/<name>--<nonce>`, so a
    released slice's kept files survive a new slice of the same name.
  - What an earlier engine of the session left is handed over when a worker
    next starts, and reported in that start's response (`data.recovered`
    for a script), since its job is not the new engine's to read.
  - Gone with the tool: the launcher's worktree/worktrees/changes API, the
    `WorkerChanged` event, and the post-job worktree states.
  `tests/integration/workers.mbtx` runs the real CLI and a real worker child
  against a scripted provider in a temporary repository, through the main
  agent's cherry-pick.
- PR 8: the desktop shows a worker's worktree in the jobs panel's details:
  name and branch, what it held when it was handed over (a commit ready to
  take, nothing changed, not mergeable and why, not captured and why), and
  its path, with a button to copy it. The job record's state is final, since
  the engine tracks the worktree no further after the hand-off, so no live
  overlay or extra command is needed.

## Integrated testing

All offline except the last.

1. **Package tests with fake children** (a script that speaks the child
   contract, as `agent_subrun/runner_test.mbt` does): captured; no report;
   a malformed, mismatched or oversized report; crash; a child that never
   reads stdin; slow exit after stdin closes; stop racing a natural end;
   report store failure; output capture failure; job-metadata persistence
   failure; the reaper exemption; every termination cause against the
   precedence list; task-group cancellation with a child that writes its
   report only after stdin EOF, which must still be `Captured`; admission (cancellation or owner close at each suspension, spawn
   failure, slot recovery); the claim (concurrent claims in one process, a
   claim then a hosted block and a hosted block then a claim, a create
   interrupted before the claim file, a stale claim never reused).
2. **The real child consuming a claim**, through the CLI: the right token
   accepted once; a wrong token, a second use of the same token, and an
   existing transcript refused.
3. **Two processes, one session.** Two engines claiming for the same parent
   at once; the gate and the launcher claiming at once.
4. **The real CLI against a scripted provider**, extending
   `tests/integration/turn_finish.mbtx`: a durable session (not
   `--no-session`), test credentials inherited by children, and one local
   server that scripts both the parent and the real child binary, which
   receive its URL through the forwarded `--api-url`. Requests are routed by
   a unique task marker in each child's input (not by system prompt, which
   two children of one kind share), each with its own step sequence; the
   children's submit tools are scripted; non-streaming auxiliary requests
   get the fixed answer. Scenarios that cross turns run under `serve`.
   Scenarios:
   - two explore children: start, `job_wait`, `job_output`, finish; child
     sessions with transcripts and `report.json`; `JobChanged` from live to
     ended with `SubagentInfo`;
   - `job_stop` on a child that never answers; Cancel and a context yield
     leave a model-owned child running;
   - a plain-text finish with a live child gets the pending-jobs decision;
   - an end between turns persists the notice and starts no turn;
   - a fifth start refused `busy`; a launch whose response is dropped;
   - a report larger than one reply: truncated text for the model.
5. **Scripts through the real PTC service**, in the same harness: a compiled
   snippet fanning out with a task group; children ending unevenly, with the
   script removing ended ids before it waits again; the bounded wait;
   `job_stop` and `job_output` getting through while a wait is held; foreign
   ids refused; program close stopping its children; close during admission
   and during adoption; a launch from a foreground script that ends before
   adoption, still correlated; chunked report reads at the encoded-reply
   boundary; a shortened reaper: collection allowance expiry, and another
   launch during the allowance; and the three migrated builtins, each with
   its current semantics (review's goal, focus and baseline modes, the
   blocker exit; repo-map's citations; change-review).
6. **Engine to desktop.** The desktop backend driving a real engine with the
   scripted provider, and the frontend consuming its events: progress
   discovery from `JobChanged`, the row and the card, opening the child
   transcript, the idle reaper keeping an engine with a live child, and
   after an engine restart the historical-job reader showing "ended with the
   engine". Static fixtures and backend events alone cannot cover these.
7. **Live, by hand.** One `deepseek-v4-pro` session on a real repository task
   that delegates, watched in the desktop.

## Review rounds

**Round 1** (2026-10-18, Codex, xhigh, on ad81a6154): reuse of the job
runtime is sound and simpler than #1872; ready after fixes. Each is
addressed above:

| Required | Where |
| --- | --- |
| P1: the gate must use the same allocator; a single-use handoff, not a bypass; the transition is not atomic | Allocation |
| P1: a foreground program has no job id; ownership needs a host-created identity and per-program dispatch | Owners |
| P1: an adopted script is reaped at 30 minutes and would kill its children | Owners (program reaper rule) |
| P1: one admission and finalization contract: request delivery, stop vs natural end, deadline, shutdown, slots | Running a child as a job |
| P2: correlation, report vs outcome, live progress, unavailable usage | The record |
| P2: worker state after `Published` needs an authoritative store | Workers |
| P2: restart wording; turn boundaries; PTC bounds | Restart; Owners; Waiting |
| P2: `review.mbtx` loses its standing goal without the handoff | Starting |
| P2: missing race and end-to-end scenarios | Integrated testing |
| Stack: claims in PR 1; script entrance with retirement; card after 2/3 | Stack |

Optional, adopted: a shared leaf for contract parsing; `bgjobs` does not
import `agent_subrun`; messaging independent of the core stack; reviews by
the launcher advisory from the start.

**Round 2** (2026-10-18, Codex, xhigh, on 88b747fac): the hours-long script
rule, worker state, restart, turn boundaries and PTC budgets resolved; PR 1
"not too big". Ready after five fixes, each addressed above:

| Required | Where |
| --- | --- |
| P1: a later hosted block could include an earlier claim; coexistence must hold both ways | Allocation (one counter) |
| P1: ownership before suspensions, close joining admissions, rollback; a failed claim file consumes an ordinal; termination causes in the precedence; graceful cancel must reach the process handler | Running a child as a job |
| P2: correlation before adoption, and for a dropped direct result | The record (correlation) |
| P2: a 48 K rendering does not bound an encoded reply; scripts need the structured report | Running a child as a job (report) |
| P2: filling a review's goal breaks `{base}` and the builtin's merge rules | Starting (`audit_context`) |
| Tests: allocator orderings, claim consumption, termination causes, collection allowance, pre-adoption correlation, builtins' semantics, frontend consumption | Integrated testing |

**Round 3** (2026-10-18, Codex, xhigh, on 15b921577): allocation,
correlation, reports and the review migration resolved. One P1: the async
library's `graceful_cancel` signals first and never closes stdin, so it
would cut the child's flush short; replaced by a custom handler (Running a
child as a job). Left to the PRs that build them: offset units, Unicode-safe
chunk boundaries, invalid offsets and behavior near PTC budgets (PR 3); a
truncated report whose store failed must not name a missing file (PR 2).
