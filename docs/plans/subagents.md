# Plan: subagents the engine owns

Date: 2026-10-05. Status: proposal, not implemented. It supersedes a first
attempt (pull requests #1868–#1871, closed) that added messaging on top of
children the `mbtx` snippet spawns; the parts of that work which still apply
are carried into this plan and named where they appear. Two rounds of
external design review shaped it; their findings are at the end.

## Where this is going

Subagents are meant to be routine: the main agent hands work to children so
that its own context stays free for the task. That needs the engine to own
every child — start it, know its state, stop it, account for it, talk to
it — and it needs launching to be one call, from the model or from a script.

## Problem

A child a MODEL asks for is spawned by its `mbtx` snippet, not by the engine.
(The engine does launch one child itself already: the goal-met gate's
reviewer, through `run_subrun`.)

1. The main agent calls `mbtx(subrun=true)`; the engine runs the snippet.
2. `wf.agent(...)` in the snippet goes to `moonbitlang/workflow/hosted`,
   which spawns `openseek run --kind <kind> ...` as the SNIPPET's child
   process, writes the request on its stdin, and reads its result file.
3. The engine is outside that loop. Before the snippet starts it reserves a
   block of 32 child ordinals in memory and hands the snippet a command-line
   template (`WORKFLOW_HOST`). Afterwards it learns what happened from
   `events.jsonl`, which the library writes best-effort.

Consequences:

- The engine cannot stop one child, see what it is doing, or tell it
  anything. The launching agent can only wait for the whole job or stop it.
- The engine does not know a child's lifecycle; it can only infer it from a
  transcript and a best-effort, script-writable file.
- A child's identity is whatever `--session` the snippet passed.
- The snippet's sandbox must admit spawning the engine binary.
- `ptc` and `subrun` exclude each other, so one script cannot both delegate
  and call `edit`/`write`.
- Launching one scout means writing a twenty-five-line program.
- A child that does not finish returns nothing. Local session data (10
  child sessions, August to early September 2026) shows 4 of 6 read-only
  children ending with no terminal event after 470–883 s.

## History that constrains this

- `edae09156` (#1318) removed a model-facing `explore` tool: dogfood (13
  desktop sessions, ~1,600 tool results) used neither it nor the workflow
  path, and the two launched the same child through two parent-side paths.
  `e2372cf28` removed the model-facing `subtask` tool for the same reason.
  That is evidence against duplicate launch MECHANISMS. It is not evidence
  about direct tools as such: neither path was used.
- Programmatic tool calls (`4324f034b`) came later: a host tool marked
  `program_callable` is reachable from a script through
  `@tools.call(name, arguments)`.

So one engine-side launcher, exposed both to the model and to scripts, is a
single mechanism with two entrances — which was not possible when those
tools were removed.

## Goals

1. One launcher, in the engine. The model calls it directly; a script calls
   it through the host-tool channel. Same tools, same semantics.
2. The engine owns each child: assigns its id durably, knows its lifecycle,
   can stop it, and records what it cost — none of which depends on what a
   caller does with the result.
3. Every call is short. Nothing is held open for a child's lifetime.
4. The launching agent can see what a child is doing and send it a new
   instruction while it runs.
5. One script can delegate and call other host tools.
6. Existing workflows keep working while they migrate.

Non-goals of the first stack: write-capable workers (the next stack, see
Workers); `review` through this launcher (see Reviews); a per-child model
choice; a session spend limit; child → parent messages; a child launching
children; reattaching to a child after an engine restart; live per-child
lanes in the desktop; anything across machines.

## Trust model

Cooperative, like the rest of the engine's delegation: the rules prevent
accidents between agents that are trying to follow them. They are not a
security boundary.

- A snippet's own policy confines its writes, but it may run
  `moon run --target native`, and that program has the user's filesystem
  access. Anything that can write the session store can write any file in
  it.
- The sender named in a message is what the sender says it is.

What the design does guarantee: the engine assigns child ids and holds the
record of who owns each child; its tools let a caller reach only children it
may reach; and a reviewer has no ingress at all.

## Design

### The tools

Launching returns at once with the child's id. Waiting, collecting and
stopping are separate short calls.

| Tool | Arguments | Returns |
| --- | --- | --- |
| `subagent_start` | `kind`, `input`, `label?`, `max_steps?` | an envelope with the new `id`, or a typed refusal |
| `subagent_wait` | `ids` (1–32) | one envelope per id, once ANY of them has ended |
| `subagent_result` | `id` | that child's envelope with its report |
| `subagent_stop` | `id` | the child's envelope, now ended as `stopped` |
| `subagent_status` | `id?` | envelopes for every child the caller may see, or one child's recent transcript |
| `subagent_send` | `id`, `message` | queues one instruction in the child's inbox |

Why not one blocking call per child:

- A host call from a script has a 120 s deadline on the server and a
  separate 125 s one in the script SDK. A blocking call would need both
  changed, and a script that caught the timeout and retried would pay for a
  second child while the first kept running.
- A held call keeps a connection. The service admits four active calls per
  program and sixteen connections in all.
- With the id in hand at once, a caller can watch, redirect or stop its own
  child.

`kind` is `"explore"` in the first stack; anything else is refused. `input`
is exactly what `run --kind explore` takes: `{"query", "hints"?}`.
`max_steps`, when given, is clamped at admission to the kind's ceiling. A
`schema` argument is refused, never ignored. `label` is cut to 72
characters.

### The envelope

Every answer about a child is the same small object:

```json
{"id": "sr-7", "kind": "explore", "label": "scout:callers",
 "state": "ended", "outcome": "captured",
 "steps": 41, "prompt_tokens": 180000, "completion_tokens": 2340,
 "usage_source": "result"}
```

- `state`: `starting`, `running`, `ended`. There is no other state; a
  stopped child is `ended` with outcome `stopped`.
- `outcome`, present only when ended: `captured`, `no_report`, `max_steps`,
  `context_yield`, `timed_out`, `failed`, `stopped`, `owner_lost`.
- `owner`: `"model"`, or the job id of the script that started it once that
  script has one.
- `recorded: false` appears when the ledger write for this fact failed (see
  The ledger).

`subagent_result` adds `report` for a `captured` child when the whole reply,
serialized, is at most 48,000 characters; otherwise `report_file` names the
file that holds it. The engine writes every captured report to
`sessions/<child>/report.json`, beside the transcript and kept as long as
the session is, so the reference is always valid and identity, outcome and
usage can never be lost to an oversized report.

Every result's `content` is one line; the data rides once, in `data`. A
caller should collect each result once: a script's retained call trace is
512 KiB, and when it is exhausted the service refuses further calls. The
children are unaffected and are stopped when the script closes.

Refusals from `subagent_start` are results a caller can branch on, with
`refused`: `"busy"` (four children already running; retry after one ends;
costs no quota), `"quota"`, `"kind"`, `"input"`, `"schema"`,
`"unavailable"` (the ledger could not be written, or another engine process
owns this session's subagents). A refusal starts no attempt and returns no
id.

### Owners

Every child has exactly one owner, fixed when it starts:

- **the model** — a direct call. The child lives until it ends, is stopped,
  or the session ends.
- **a program** — a script's `@tools.call`. When that program closes (it
  exits, is cancelled, or its job is stopped), its children that have not
  ended are stopped.
- **the gate** — the goal-met reviewer, launched as today. It is not started
  through these tools and is not in the launcher's registry in the first
  stack; its id is simply not one any of these tools accepts.

Who may address whom:

- The model's direct calls may address any child of the session.
- A script may address only children its own program started. Any other id
  is refused, as an unknown id is.
- A whole `subagent_wait` is refused if any id in it is unknown or not the
  caller's; ids are never silently dropped.

A script learns its identity from the host, never from its own arguments.
The host-call service builds each program its own instances of the
owner-aware tools, each closed over a host-created owner context (a stable
identity, a closed flag, and the job id once the program has one). Direct
executors are untouched and the executor shape stays `(Json) -> ToolAction`.
Nothing about the caller rides in script-controlled arguments.

Quota is per owner: 32 starts for a program, counted when a start is
admitted, never refunded. The model's direct calls are not subject to it;
they are bounded by the in-flight cap and by being one call each.

### Admission and close

`subagent_start` does, in order:

1. With no suspension: refuse if the owner is closed, over quota, or four
   children are already running; otherwise add a registry entry in state
   `starting`, owned by this owner. From here a close finds the entry.
2. Allocate the child id durably (see The ledger). If that fails, remove the
   entry and refuse `unavailable`. If the owner closed meanwhile, record the
   child as ended `stopped` — never launched, no usage — and return that.
3. Spawn the launcher task for the child and return the envelope.

Closing an owner: mark it closed with no suspension, cancel every one of its
children that has not ended, then join them. Joining is idempotent. A
`subagent_start` still between steps 1 and 3 is covered by step 2's recheck.

A script adopted into the background keeps its program and therefore its
owner; adoption only fills in the job id. Session shutdown closes every
owner and joins every launcher task before the ledger is closed.

A dropped connection is not a close: an admitted call keeps running. A
caller that loses the reply to a start must look with `subagent_status`
before starting again, and the taught example does.

Cancelling the model's TURN does not stop a background script or its
children — background jobs outlive a turn today — and does not stop the
model's own children either. `job_stop` and `subagent_stop` do.

### In flight

Four children run at once per session, counting the model's and every
script's together; the gate's reviewer is outside that count. A fifth start
is refused `busy`. There is no queue in the first stack. Each child has a
wall deadline of 600 s, the hosted default today, enforced by the runner.

### Waiting

`subagent_wait(ids)` is level-triggered:

1. Validate the whole id set first (1–32 ids, all known, all the caller's).
2. If any listed child has already ended, return immediately.
3. Otherwise check and subscribe with no suspension between the two, and
   re-check after every wake-up.

It returns the current envelope of every listed child. A caller removes
ended ids before waiting again; waiting on an ended id returns at once, so a
loop that does not would spin through its call budget.

From a script the wait is bounded at 60 s, after which it returns the
children's actual states. Sixty seconds leaves room for admission delay
inside the SDK's 125 s. To keep the channel usable while waits are pending,
a program may have ONE wait in flight (a second is refused `busy`), and at
most eight waits are held across the session; a ninth returns the current
states at once. One wait can cover all of a program's children, so nothing
is lost by the limit.

From the model the wait pauses the turn the way `job_wait` does: until a
listed child ends or user input arrives, with no timeout. A child's end also
queues a notice for the model, so it need not wait at all.

Cancelling a wait removes the waiter. It never touches the children.

### Stopping

`subagent_stop(id)` cancels the launcher's task for that child and joins it.
The child process is terminated with no grace period — the spawn contract
gives one only at its wall deadline — so its transcript may end without a
terminal. The registry and the ledger record `stopped`.

Stopping a child that has just ended returns its real outcome. To ask a
child for what it has before stopping it, send it an instruction and wait.

The launcher is the single publisher of a child's terminal outcome.
`run_subrun` today allocates its own id and reports `cancelled` when it
unwinds; it gains a way to run with an id allocated earlier and to leave the
terminal to its caller.

### The ledger

One append-only file per parent session, written by the engine only:
`sessions/<parent>/subagents.jsonl`. It is the authoritative ALLOCATOR of
child ordinals and the record of each child's lifecycle; it is not a second
copy of anything.

- **One engine process owns a session's subagents at a time.** The owner
  holds an exclusive lock for its lifetime. A second engine process on the
  same session cannot take it: its `subagent_start` is refused
  `unavailable`, and its `mbtx(subrun=true)` is refused the same way.
  Liveness is the lock, never a guess from a process id or a generation.
- **Allocation is durable before an id leaves the engine.** An `allocated`
  record (`first`, `count`, `owner`) is appended and synced first: `count`
  1 for a start, 32 for a hosted workflow's block, 1 for the gate's
  reviewer. The next ordinal is one past the highest recorded allocation or
  existing child session, whichever is greater. Today the counter lives in
  memory and a restart recovers only from child sessions that exist, so a
  surviving script holding an unused block can collide with a new child.
- **Lifecycle.** `started` when the process is spawned; `ended` with the
  outcome and usage when the launcher reaps it.
- **Writes fail loudly.** A failed or unconfirmed allocation write returns
  no id. A failed `started` or `ended` write does not undo the fact; the
  envelope carries `recorded: false` and history will later read
  `owner_lost` for that child.
- **Torn tails.** Appends take the file's lock and close off an
  unterminated tail before writing, so damage stays in one record; a reader
  splits lines as bytes, decodes each on its own, and counts what it cannot
  read. Allocation takes the maximum over every readable record.

After a restart, a child with no `ended` record is `owner_lost`: the engine
that owned it is gone (the lock is free). It was sent end-of-input and
should have stopped; nothing confirms that. Its transcript says how far it
got. It cannot be waited on, stopped or collected, and it is not relaunched.
This is fail-on-owner-loss on purpose: a ledger makes history truthful; it
does not make an old process controllable.

### Accounting

The engine records a child's spend in the `ended` record whatever the
caller does with the result.

- `usage_source: "result"`: the child's own account, from its result file.
- `usage_source: "transcript"`: there was no result (stopped, timed out,
  crashed). The engine sums the usage recorded on the child's non-replay
  assistant events and counts steps the same way. It is a lower bound when
  the child died mid-response or a transcript line is unreadable, and
  `unaccounted` says which.
- `usage_source: "none"`: nothing could be read; the counters are absent,
  not zero.

All three count recorded agent responses. A child's own context-checkpoint
request is not in them; that is a stated gap, shared with the engine's own
accounting. Child tokens are never added to the parent's context-window
usage.

### Seeing a child

`subagent_status` reads the registry: an engine-launched child is
`starting`, `running` or `ended` as a fact. With an id it adds the child's
last few transcript events and where each instruction sent to it stands.
Children from earlier engine processes come from the ledger. Children a
hosted workflow spawned are shown from their transcripts alone, as "no end
recorded, last activity N s ago" when they have no terminal; the first
attempt's reader of the workflow's `events.jsonl` is not carried over.

When a script-owned child starts, the model gets one bounded notice naming
its id, label and job. A model-owned child's end queues a notice; a
script-owned child's end does not, beyond its job's own completion notice.

The desktop already lists a child's session under its parent in the
sidebar, and shows a script's host calls and their results under its job.
Live per-child lanes for children that outlive a turn are deferred: lanes
are turn-scoped today, and promising visibility from transient events alone
would be wrong. The engine therefore emits no new subrun brackets for
launcher children in the first stack.

### Talking to a child

Carried over from the first attempt, where it was reviewed and tested.

- **An inbox per receiving session**, `sessions/<id>/inbox.jsonl`, one
  versioned record per line (`v`, `id`, `from`, `kind`, `text`). The
  receiver creates it, just before its first transcript record; a sender
  only appends to an existing one, under a lock. A session that takes no
  messages never creates one. Unknown versions and kinds are counted and
  never delivered.
- **The turn loop takes outside input at its steer points.** `AgentRuntime`
  gets an optional source; the loop's one steer-drain helper pulls it first,
  so an instruction is seen exactly where user steering is — before every
  model request and at every completion decision, where it wins over a
  finish. A source that fails is dropped and reported at the next request
  only, never as a steer, so it cannot keep a finished turn running.
- **A report captured before an instruction arrives is discarded**; the
  scout's prompts allow a replacement submission.
- **Delivery is read off the child's transcript by receipt** (`<id>@<from>`):
  waiting, delivered (recorded, no model response after it), seen (a
  response followed). None claims the child obeyed.
- `subagent_send` refuses a child that has ended, one the caller may not
  address, a blank or over-long message, and a child with eight
  instructions still waiting.

The inbox stays even though the engine now holds the child's stdin: it
survives a sender's restart, and the child's stdin treats everything after
the request line as noise and end-of-input as cancel.

### Reaching the tools

**Scripts.** All six tools are in the program registry, so a script calls
them with `@tools.call`. The contract — names, arguments, the envelope, the
refusals, "collect once", "look before retrying a start" — is taught where
script packages are taught, with a verified example under `share/examples/`.
The bundled one-liner is
`mbtx(filename="@builtin/scout.mbtx", args=["question", ...])`: one scout
per question, wait, print each report or the outcome that replaced it.

**The model.** The same six tools are in the model's tool list, as the last
step of the stack. They are non-blocking for the model exactly as they are
for a script, so the turn is never held for a child's lifetime.

The acceptance check for the teaching is a compiled script run through the
real host-call service against contract-speaking fake children, covering a
refusal, a wait that times out, a stop, and a file-backed report. Compiling
an example proves the example, not that a model will write one; a small
prompted trial with the shipped text is the check for that, and is
recommended before wider use.

### Workers (the next stack)

A child that can edit. Most of it exists and has been dormant since the
`subtask` tool was removed: `agent_worker` (the kind), `agent_subtask`
(provision, capture, integrate), the write scope and the worker sandbox
profile.

- `subagent_start(kind="worker", input={"task", "allowed_paths", "name"})`.
  The engine provisions a git worktree on a new branch; the worker may
  write only under its allowed paths (file tools everywhere, plus a kernel
  sandbox on macOS) and cannot commit.
- When it ends, the engine validates that every change is in scope and
  commits it. The envelope gains `changes`: branch, commit, diff summary.
- `subagent_integrate(id)` merges that exact commit into the main checkout;
  a conflict stops and hands the files to the caller, with continue and
  abort. `subagent_discard(id)` drops it.
- Overlapping `allowed_paths` between live workers are refused at start.

The tools and envelope above are shaped so that this adds a kind, one
envelope field and two tools, and changes none.

### Reviews

Not through these tools yet. The gate keeps launching its reviewer exactly
as today. A review started by the audited agent raises questions this plan
should not settle in passing: the caller picks the criteria, can stop and
retry attempts, and chooses which report to show. When it is taken up, such
reviews are advisory by name, and the gate keeps its own criteria, result
channel and allowance.

### `wf.agent` on these tools (later)

An adapter can make `moonbitlang/workflow`'s `Workflow` run on these tools,
and it belongs with the script SDK, not in the library. Its contracts are
NOT settled here: the library's outcome type has no `stopped` or
`owner_lost`, only `Skipped` escapes its default retry, and a plain script
has no host-granted place for a journal. It needs a library change and an
SDK release, and is a separate stack. Until then the hosted spawn path
stays, sharing the ledger's allocator so ids cannot collide.

## Risks

- More parts than one blocking call: a registry, a ledger, six tools, a
  change to how the host-call service builds a program's tools.
- Two launch paths until the adapter lands. The prompt must teach one.
- A stopped child gets no grace and writes no terminal.
- A child cut off at its deadline still returns no report.
- Whether a model uses any of this is unproven: 3 of 47 recent local
  sessions delegated at all.

## Stack

1. **The allocator.** Durable, locked allocation of child ordinals in the
   ledger; one engine process per session; used by `run_subrun` (the gate),
   hosted reservations and, later, the launcher. Tests: restart with an
   unused block, two engine processes, a torn tail.
2. **Owner-bound host tools.** The service builds a program's owner-aware
   tools over a host-created owner; program close closes the owner;
   per-owner quota; typed refusals. Tests against the real service: close
   during admission, a dropped connection.
3. **The launcher for `explore`.** Registry, start / wait / result / stop,
   the in-flight cap, lifecycle and accounting records, `report.json`,
   session shutdown, the `run_subrun` seam. Tests with a fake child.
4. **Scripts.** Program registration, `subagent_status` from the registry
   and ledger, the taught contract, the acceptance script, the verified
   example, `@builtin/scout.mbtx`.
5. **Messaging.** The loop's input source, the inbox, the scout reading its
   launcher's instructions, `subagent_send` and delivery states.
6. **The model.** The six tools in the model's list, the turn-level wait,
   end notices, the prompt.

Then: workers. Later: the workflow adapter, reviews, a per-child model
choice, a spend limit, live lanes, a start queue.

## Review rounds

**Round 1** (one blocking `subagent` call): not ready. The script SDK has
its own 125 s deadline; held calls can exhaust the service's connections; a
retry pays twice; cancellation, restart and accounting were underspecified;
a script-launched review is not an independent audit. It suggested immediate
launch with bounded waiting, which this plan adopts.

**Round 2** (start now, ask later): the direction is sound; proceed with a
reduced first slice once four contracts are fixed. Each is addressed above:

| Required | Where |
| --- | --- |
| Ids and hosted blocks must be durable before they leave the engine; two engine processes on one session; torn and failed writes | The ledger |
| A concrete admission and close protocol; identity without script-controlled arguments; adoption; shutdown; one terminal publisher; disconnect is not close | Owners; Admission and close; Stopping |
| A wait is still a held call: bound it so control calls are never starved | Waiting |
| "Any has ended" must be level-triggered and fully validated; the envelope has no `stopped` state | Waiting; The envelope |

Scope it asked to cut from the first slice, and which is cut: the start
queue, gate integration with the registry, and live lanes. It asked that
owner close, session cleanup, durable allocation, explicit persistence
errors, bounded control availability, report validation and engine-owned
accounting NOT be cut; none is.
