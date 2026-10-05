# Plan: messages between agents (inbox files)

Date: 2026-10-05. Status: stage 0 is landing as a stack of pull requests —
the loop's input source and the kind hook, then the inbox and the child
wiring, then the parent's tools — and has not been used by a live model yet;
stages 1–3 are proposals. Revised after two rounds of external design
review; the findings of each and what was done about them are at the end.

## Problem

A parent agent delegates through `mbtx(subrun=true)`: one snippet runs a
`moonbitlang/workflow` workflow whose `wf.agent` calls are child processes
(`openseek run --kind <kind>`). After five seconds the snippet becomes a
background job. From then on the parent can only wait for the job or stop it.
It cannot see what a child is doing, cannot correct one that is off track, and
a child cannot ask it anything. Stopping the job costs every unfinished
child its report: the transcripts and the journal's already-resolved calls
survive, but an unfinished child returns nothing to the script.

Local session data (10 child sessions, August to early September 2026, so
before the run/subrun unification) shows 4 of 6 read-only children ending with
no terminal event after 470–883 s.

## What exists today

Every existing channel flows from the child outward, or belongs to a process
the engine does not own.

| Channel | Direction | Owner | Notes |
| --- | --- | --- | --- |
| child stdin | launcher → child | the process that spawned the child: for a hosted child, the `mbtx` snippet, not the engine | one request line, then EOF means cancel; the child contract reserves it |
| `result.json` | child → launcher | child | written once, at the end; removed after it is read |
| `sessions/<child>/openseek_session-<child>.jsonl` | child → anyone | child | the transcript; append-only |
| `<parent>-wf-<N>/events.jsonl` | workflow library → host | library | `agent_started {child, kind, label}`, `agent_finished {child, status, steps, tokens}`; at most 64 lines per run; best-effort (a failed write is swallowed) |
| `<parent>-wf-<N>/journal.jsonl` | workflow library → host | library | resolved calls, for replay |
| `serve` stdin `steer` command | controller → top-level session | desktop / TUI | folds input into a running turn |
| PTC listener | snippet → engine | engine | per-program capability; how `@tools.call` reaches host tools |

Inside the engine a running turn already takes new input: `AgentRuntime`
holds a lossless steer queue. The loop drains it at fixed points — before
every model request (`prepare_step`) and at every completion decision — and
the rule at those points is that input wins over a completion the model
decided on meanwhile. A queued `Prompt` becomes a durable `User` item,
carrying the sender's `submission_id`, and a user-role message.

Constraints that shape the design:

- A `--kind` run always starts a new session; a child session is never
  resumed.
- `SessionStore::exists` tests only the session DIRECTORY, and a `--kind` run
  refuses to start when it exists. So no sender may create it.
- Child ids are `<parent>-sr-N`. Standard hosted launches draw N from one
  per-session counter and a reserved block of 32 per snippet.

## Trust model

Cooperative, the same as the rest of the engine's delegation (see
`subtask-worker-subagents.md`): the rules below prevent accidents between
agents that are trying to follow them. They are NOT a security boundary.

- An `mbtx` snippet's own policy lets it write only its temp directory and
  its workflow run directory. But a snippet may run `moon run --target
  native`, and that program has the user's filesystem access. Anything that
  can write the session store can write an inbox.
- `from` in a message is what the sender says it is. Nothing authenticates
  it.
- `--session` on a delegated run is caller-supplied, so a snippet can launch
  a child outside its reserved block, and a parent recognises its children by
  the `<parent>-sr-N` name alone.

Authenticating senders and enforcing store isolation across subprocesses is
out of scope here. What the design does guarantee is narrower: the engine's
own tools address only the caller's family, a receiver presents only the
messages it knows how to frame honestly, and a reviewer has no ingress at all.

## Goals

1. A parent can watch its running children and post one of them a new
   instruction without stopping the job.
2. One mechanism and one record format, usable later for child → parent and
   sibling ↔ sibling without a format break.
3. No change to the `moonbitlang/workflow` child contract for stages 0–1.
4. A reviewer stays unreachable by the agent it audits.

Non-goals: messaging across machines or session stores; messages between
unrelated conversations; starting a turn in an idle top-level session;
delivery faster than the receiver's next model request.

## Design

### The inbox

One file per receiving session: `sessions/<id>/inbox.jsonl`
(`SessionStore::inbox_path`). One record per line:

```json
{"v": 1, "id": "m1791234567890-3", "from": "<sender session id>", "kind": "instruction", "text": "..."}
```

- `v`: the record format, `1`.
- `id`: the sender's tag, unique among that sender's messages (clock plus a
  per-process counter). Two senders may share an id, so a message's identity
  everywhere is its RECEIPT, `<id>@<from>`.
- `from`: the sender's session id.
- `kind`: `instruction` is the only kind so far. `note`, `request` and a
  `reply_to` field are reserved for stage 2.
- `text`: at most 8,000 characters.

Rules (`agent_subrun/inbox`):

- `open(path)`: the RECEIVER creates the file and the directory it lives in.
  Its existence is the receiver's statement that it takes messages. A child
  opens it immediately BEFORE its first transcript record, so a session that
  has a transcript and no inbox is one that takes none, never one that has
  not got to it yet.
- `post(path, message)`: appends one record, only to an existing file.
  Returns `false`, writing nothing, when there is no inbox. Posts hold an
  exclusive lock on the inbox file, so senders never interleave. If the file
  does not end in a newline — a previous write died part-way — the post
  closes the tail off first, so the damage is confined to that one record.
- `read(path)`: takes a shared lock, splits the file into lines as BYTES,
  and decodes each whole line on its own. A final unterminated line is not a
  message yet. A whole line that is not a version-1 record of a known kind is
  counted in `unreadable` and not delivered: a reader that guessed at it
  could present someone's note as an instruction. This is also the
  forward-compatibility rule — an old receiver never misframes a newer kind;
  the message stays undelivered and visibly so.
- `Reader::take()`: messages not yet handed out, told apart by receipt,
  never by position. In-memory, which is sound because child sessions are
  never resumed.
- The file is append-only; nobody truncates or removes it.

### The receiver

`AgentRuntime` takes an optional `external_input` source ("what arrived from
outside the process since the last call"). The loop's one steer-drain helper
(`pending_steers`) calls `pull_external_input` first, so outside input is
seen at exactly the points user steering is, and nowhere else:

- before every model request, including the first;
- at a completion decision — a plain final answer or a control tool — where
  it converts the finish into a continue;
- around a checkpoint, by the existing steer rules.

The pull is an await at a point where the loop's session is current. It is
deliberately NOT inside the persistence callback: a failure or cancellation
there would leave durable state ahead of the loop's snapshot and the
terminal append would be rejected as stale.

A source that raises is dropped. Its failure is NOT queued as steering
input, because steering overrides a completion: a child that had just
submitted on its last step would be kept running by the notice and lose its
report to the step budget. The failure is held and reported as a runtime
notice at the next `prepare_step` only — when the turn is making another
request anyway. A turn that ends first never hears of it.

When the step budget runs out after an ordinary tool step, the loop does not
drain steers, so nothing is pulled: a waiting message stays in the inbox and
shows as never delivered, rather than being consumed into a queue that then
disappears. A COMPLETION decision on the final step is different: it does
drain, so an instruction waiting there is recorded and overrides the finish,
and the run then ends at its step limit with the instruction delivered, no
response after it, and the earlier report discarded. That is the existing
rule for user steering applied unchanged; the sender sees it in
`subagent_status`.

`agent_kind.execute_kind` passes `instructions` through as that source, with
one addition: when instructions with content arrive (blank input is dropped
by the loop and supersedes nothing), a report already captured by the submit
tool is DISCARDED. It answered the task as it was; the turn must
submit again, and a turn that then ends without submitting returns no report.

`openseek run --kind <kind>` supplies the source when
`Kind::takes_instructions()` and the run has a session — today, `explore`
only. It presents only messages whose `from` is the run's own launcher (the
parent its `<parent>-sr-N` id names) and whose text is not blank, framed:

> [New instruction from the agent that gave you this task, sent while you
> work. Follow it: it refines or redirects the task. Your report is still due
> through the same submit tool.]

and tagged with the message's receipt as the steer's `submission_id`, which
the loop records on the durable `User` item. A message from any other
sender, or with a blank body, is not presented and not acknowledged; it
shows as waiting. The framing has content of its own, so a blank body let
through would supersede a report with an instruction that says nothing.

Because an instruction can arrive after a submission, the scout's system
prompt, task text and submit tool all say that a new instruction supersedes
what was submitted and must be answered with a fresh submission. "Submit
exactly once" would leave a redirected scout unable to finish.

### Delivery states

Read off the receiver's transcript by receipt — sender and id, not position.
The transcript records model RESPONSES, not requests, and the states say no
more than that evidence supports:

- **waiting**: no transcript item carries the receipt. If the receiver has
  ended: **never delivered**.
- **delivered**: a `User` item carries the receipt, and no model response is
  recorded after it. A request carrying it may be in flight. If the receiver
  has ended: **delivered, with no response recorded after it** — whether the
  model received it is unconfirmed (it may have been cut off mid-request).
- **seen**: a `User` item carries the receipt and a model response follows
  it, so a request carried it.

None of these claims the receiver obeyed. There is no separate cursor or ack
file that could disagree with the transcript.

### The sender (parent side)

Two tools in the main agent's registry, present wherever it can delegate
(`serve`; `run` with a durable session). Both work from the session store
alone and talk to no process, so they behave the same for a child a snippet
launched and for one the engine launched.

- `subagent_status(id?)`: without an id, one line per child of this
  conversation — state, steps, seconds since last activity, how its
  instructions stand, start of the task. With an id, that child's last 8
  transcript events and every instruction not yet seen. Unreadable transcript
  or inbox lines are reported, and the state is then stated as possibly out
  of date. Concurrency-safe.
- `subagent_send(id, message)`: queues one instruction and says delivery is
  not confirmed. Refused for an id that is not `sr-N`; for a child with no
  transcript; for one whose transcript ends in a terminal; for one with no
  inbox; for a message over 8,000 characters; and when 8 instructions are
  already waiting untaken.

The end-of-turn check is a snapshot. A child can end between that check and
the post; the instruction is then queued and shows as never delivered.

### Reviewers

A `review` child never opens an inbox and is given no source, whether the
model asked for the review or the engine's goal-met gate launched it. Every
later ingress (child → parent replies, sibling messages) keeps the same
exclusion. This is separation of communication, not full independence: a
reviewer still reads a worktree the audited agent can change.

## Stages

**Stage 0 — parent → explore child (implemented).**
`AgentRuntime.external_input` and the loop pull; `agent_subrun/inbox`;
`execute_kind`'s `instructions` with capture invalidation;
`SessionStore::inbox_path`; `agent_tool/subagent`; wiring in
`execution/tools.mbt`, `run/turn.mbt`, `serve/loop.mbt`.

Tested: inbox (ordering, torn multi-byte tail then a further post, unknown
version and kind); the loop source (delivered in the next request once; a
report captured before an instruction is not returned; a fresh submission
is; a failing source ends neither the turn nor the run); the tools against a
real temp store (waiting → delivered → seen → never delivered, refusals,
the waiting cap, id shapes, another conversation's child); and a real-binary
run against a mock model server.

**Stage 1 — make it usable.**

1. Ids. Put the reserved child range in the `mbtx(subrun=true)` launch
   result. Have `subagent_status` read the run's `events.jsonl` for label,
   job, launched-but-not-yet-recorded children, and the library's end status.
   The sidecar is best-effort and script-writable, so it refines the display
   and never decides who is a child; where it and the transcript disagree or
   it is missing, the state is "unknown", not "working".
2. Bounded, deduplicated lifecycle notices to the parent (child started,
   child ended), in the manner of the background-job completion notice.
3. Mark both tools `program_callable` so a snippet can
   `@tools.call("subagent_send", ...)`.
4. Prompt: a short paragraph in the Orchestration section.
5. A live run with a real model.

**Stage 2 — child → parent.**
A child tool posts a `request` or `note` record to the PARENT's inbox; the
parent answers with `subagent_send` carrying `reply_to`. Polling at the
parent's steer points is not enough here: a parent blocked in `job_wait` on
the very job whose child is asking would never look, and the child would
never finish. Stage 2 therefore needs a wake path into the parent's runtime
(`queue_steer(Notice(..), wake=true)`): either a watcher on the parent's
inbox, or the existing PTC listener extended with a narrowly scoped child
capability — the stronger candidate, since it is already session-owned and
independent of the agent loop. A message to an IDLE parent does not start a
turn; it is queued durably and surfaced to the controller.

**Stage 3 — siblings.**
Children of one parent may message each other, with peer-specific framing
(information from a peer, not an instruction from the launcher) and loop
limits. A roster in the task text is discovery, not authorization. Intended
for write-capable workers, which have no product entry point today.

## Known gaps

- Delivery waits for the receiver's next model request. A child inside one
  long tool call does not see a message until that call returns; an
  intervention that cannot wait needs cancellation, not a message.
- A child that ran out of steps, or was killed, never takes what is waiting.
  The sender learns this from `subagent_status`; nothing retries.
- A child killed without a terminal looks "working" until stage 1 reads the
  sidecar, and even then only best-effort.
- `subagent_status` parses each child's whole transcript on every call
  (200–380 KB observed per child).
- Posting is not idempotent by id. No sender retries today.
- Lock acquisition has no timeout. A writer holds the inbox lock for one
  small append, so this matters only if a sender is suspended mid-post; the
  receiver's pull then waits until it is cancelled.
- `subagent_status` accepts `sr-007` for `sr-7`, and does not surface a
  transcript's half-written final line.
- Windows is untested.

## Decisions (were open questions)

1. **Inbox location:** the receiver's session directory. The receiving
   session owns delivery and history; one job holds many children; the
   engine's own sub-runs have no workflow directory. A script that needs to
   post gets a mediated capability (`@tools.call`), not write access.
2. **Acknowledgement:** by message id on the transcript item; no separate
   cursor.
3. **Polling or watcher:** the loop's steer points for stage 0; a wake path
   for stage 2.
4. **Idle parent:** a message does not start a turn.
5. **Tool names:** `subagent_status` / `subagent_send`, separate from the
   `job_*` family — jobs own execution, wait and stop; sessions identify
   recipients. Status will show which job a child belongs to. If messaging
   becomes symmetric, the neutral name is `agent_send`.
6. **Notices:** push bounded lifecycle notices; poll for detail.
7. **Reviewers:** excluded on every ingress, the goal-met gate included.

## Round 1 review: findings and resolutions

| Finding | Resolution |
| --- | --- |
| "Family only" is not sandbox-enforced; `from` and child membership are unauthenticated | Stated plainly as a cooperative policy (Trust model). Not enforced. |
| A redirected submission could still return the earlier report | Capture is discarded when instructions arrive; test added. |
| Polling inside `append_item` could leave durable state ahead of terminal cleanup | Pull moved to the loop's steer-drain point; a failing source is dropped with a notice. |
| "Read" could mean persisted but never in a model request | Three states by message id: waiting, delivered, seen. |
| The tool-append hook was not a universal input boundary | Same fix: every steer-drain point, including the first request and completion decisions. Nothing is consumed when the step budget runs out after an ordinary tool step; a completion decision on the final step still pulls (see The receiver). |
| Torn or interleaved appends could poison later messages; UTF-8 decoded before the tail was cut | Locked appends, tail closed off before a post, byte-level line split, per-line decode, `unreadable` count. |
| Readiness and terminal checks described as definitive | Inbox opened before the first record; send says "queued, not confirmed"; unreadable transcript lines reported. |
| Envelope: `Array[String]` discards identity | Versioned record with `id`, `from`, `kind`; reader returns messages; unknown kinds are never delivered. |

## Round 2 review: findings and resolutions

Verdict: the architecture is sound and the work can be split into pull
requests, with these four corrections required first.

| Finding | Resolution |
| --- | --- |
| A source failure was queued as a notice, which overrides a finish: a child submitting on its last step could lose its report | The failure is held and reported only at the next `prepare_step`. Regression test asserts the turn's terminal is `Finished`; a negative control confirmed the test fails with the old behaviour. |
| Blank external input discarded a valid capture | Only input with content supersedes a report; test added. |
| Receipts matched by id alone, so another sender's message with the same id read as delivered | Identity is the receipt `<id>@<from>` on both sides; tests added. |
| "Delivered, but it ended before another step" overstated the evidence | Reworded: no response recorded after it; model receipt unconfirmed. |
| Document: "nothing is pulled" at step exhaustion was too broad | Narrowed: a completion decision on the final step still pulls. |

## Round 3 review (the stage 0 commits)

The loop input source and the parent's tools were approved as they stood.
Two changes were required in the child wiring, both made:

| Finding | Resolution |
| --- | --- |
| The scout's prompts still said to submit exactly once, so a redirected scout could not comply | System prompt, task text and tool description now allow a replacement submission after a new instruction. |
| A blank message body was framed into a non-blank instruction, which could discard a report on the final step | Blank bodies are dropped before framing; test added, and checked against the real binary. |
