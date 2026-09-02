# bobzhang/workflow

Engine-agnostic multi-agent workflow orchestration with journaled
replay/resume — a MoonBit take on the workflow-as-code model: a workflow
is an ordinary async program, the "graph" unfolds as it runs, and
durability comes from replaying a journal of typed outcomes rather than
from a static DAG.

The core package never spawns anything. Its one seam is `Runner`: a
single async function from `AgentCall` to `AgentOutcome`. Engines plug
in from the outside — through the `spawn` sub-package's child-contract
implementation for out-of-process engines, or any in-process function;
tests plug in fakes, which is why everything below runs hermetically.

## The failure model

Everything else follows from three decisions:

- **Failure is data, in a typed channel.** An agent that produced no
  usable report raises `WorkflowError::AgentFailed` with a typed
  `AgentFailure` cause; `try_agent` folds it into a `Result` for fan-out
  sites. Forgetting to choose a failure policy is a compile error, never
  a silent `null`.
- **Cost is never lost.** `AgentOutcome` carries the attempt's spend on
  BOTH arms — a timed-out child's tokens land in `tokens_spent()` just
  like a success's. `attempt=None` means no launch was ever tried.
- **Cancellation is not failure.** Engine bugs and cancellation `raise`
  through and cancel the task group; the launch allowance only counts
  agents that actually launched — a call cancelled while queued costs
  nothing.

## A workflow, end to end

One phase fans three verifiers out over a finding, a quorum policy
requires at least 2 of the 3 CALLS to succeed (agreement between the
returned verdicts is then the script's own judgment, as the filter below
shows), and every launch is capped by the shared semaphore:

```mbt check
///|
async fn verdict_runner(call : @workflow.AgentCall) -> @workflow.AgentOutcome {
  @async.pause()
  let verdict : Json = if call.input is { "query": String(q), .. } &&
    q.contains("lens=repro") {
    { "confirmed": false }
  } else {
    { "confirmed": true }
  }
  Finished(value=verdict, attempt={
    attempt_id: "sr-\{call.label}",
    steps_used: 3,
    prompt_tokens: 70,
    completion_tokens: 30,
  })
}

///|
async test "fan out three lenses, gate on a 2-of-3 quorum" {
  let wf = @workflow.Workflow(
    runner=@workflow.Runner(verdict_runner),
    max_concurrent=4,
    max_calls=16,
  )
  wf.phase("Verify")
  let results = @workflow.fan_out(["correctness", "security", "repro"], lens => {
    wf.try_agent(
      kind="judge",
      "Judge the finding through lens=\{lens}: real?",
      label="verify:\{lens}",
    )
  })
  let confirmed = @workflow.quorum(results, need=2)
    .filter(v => v is { "confirmed": True, .. })
    .length()
  assert_eq(confirmed, 2)
  assert_eq(wf.calls_made(), 3)
  assert_eq(wf.tokens_spent(), 300)
}
```

`fan_out` gives every item its own `Result` slot — one lost verifier
never poisons its siblings, and the tokens they spent stay spent. When
later work is worthless without ALL of a stage, use `parallel_all`
instead: the first failure cancels every sibling still in flight. The
policies are one identifier each: `all_ok`, `collect_ok(min_ok~)`,
`quorum(need~)`.

Multi-stage pipelines are just function composition inside the fan-out —
stages need no barrier between them, so composing them per-item IS the
pipeline:

```mbt check
///|
async test "find then verify, with no barrier between the stages" {
  let wf = @workflow.Workflow(runner=@workflow.Runner(verdict_runner))
  let verified = @workflow.fan_out(["pkg/a", "pkg/b"], target => {
    let finding = wf.try_agent("Find the worst bug in \{target}", kind="judge")
    match finding {
      // Each finding proceeds to verification the moment ITS finder
      // returns — b's finder may still be running while a verifies.
      Ok(_) =>
        wf.try_agent(
          "Adversarially verify the finding in \{target}",
          kind="judge",
        )
      Err(error) => Err(error)
    }
  })
  assert_eq(@workflow.all_ok(verified).length(), 2)
}
```

## Replay: crash, resume, and pay only for new work

Every live outcome is appended to the `Journal` — the call's WORK
identity (kind, input, max_steps — never the display label) plus the
lossless outcome. Re-running the same program against the same journal
replays successes for free, keeps a human's `Skipped` refusal standing,
and re-attempts other failures — getting past those is what resume is
for:

```mbt check
///|
async test "the second generation replays instead of re-paying" {
  let journal = @workflow.Journal::in_memory()
  let wf1 = @workflow.Workflow(
    runner=@workflow.Runner(verdict_runner),
    journal~,
  )
  let first = wf1.agent(
    "Judge the finding through lens=security: real?",
    kind="judge",
  )
  assert_eq(wf1.tokens_spent(), 100)

  // Same program, next generation: served from the journal — no launch,
  // no slot, no fresh spend.
  let wf2 = @workflow.Workflow(
    runner=@workflow.Runner(verdict_runner),
    journal=@workflow.Journal::in_memory(prior=journal.recorded()),
  )
  assert_eq(
    wf2.agent("Judge the finding through lens=security: real?", kind="judge"),
    first,
  )
  assert_eq(wf2.calls_made(), 0)
  assert_eq(wf2.calls_replayed(), 1)
  assert_eq(wf2.tokens_spent(), 0)
}
```

File-backed journals (`@workflow.Journal::load(path)`) are append-only JSONL,
accumulated across generations. A torn final line — the signature of
crashing mid-append — is dropped AND repaired on disk; corruption
anywhere else raises `JournalCorrupted`. Identical concurrent calls are
intentional samples (three identical verifiers) and consume entries as a
multiset.

## Observability

`@workflow.Workflow(on_event=...)` narrates the run: `PhaseStarted`, `Log`, and an
`AgentStarted`/`AgentFinished` bracket that balances on EVERY path —
success, typed failure, cancellation (`Interrupted`), and infrastructure
error (`Errored`) — plus `AgentReplayed` for journal hits. Purely
observational: no control flow rides on events.

## Plugging in an engine

Any process that speaks the CHILD CONTRACT is already an engine: one
JSON line on stdin — the VERSIONED request envelope
`{"workflow_contract": 1, id, kind, max_steps?, input}`, with the pipe
held open (EOF is graceful cancel) — JSONL events on stdout
(`usage`/`agent_step` are accounted exactly), and one final
`{"subrun_report": ...}` line. The `spawn` sub-package is the contract's
one implementation:

```moonbit nocheck
///|
let runner = @spawn.contract_runner(launch=_ => {
  command: "my-engine",
  args: [],
  cwd: None,
  extra_env: None,
  deadline_ms: None,
})
```

For an engine whose reports are pure values, that is the whole adapter —
a shim around a Rust CLI needs only to translate framing, and gets
journal replay, budgets, and cancellation for free. An engine whose
reports name stateful resources should also pass `validate_replay`.

For in-process engines (and tests), implement one async function and
wrap it:

```moonbit nocheck
///|
let runner = @workflow.Runner(call => {
  // spawn something, await it, and account honestly:
  Finished(value=report_json, attempt={
    subrun_id,
    steps_used,
    prompt_tokens,
    completion_tokens,
  })
})
```

openseek's production adapter (`agent_workflow` in the openseek module)
maps `explore`/`review`/`echo` kinds onto `openseek subrun` child
processes and adds write-capable `worker` slices — confined git
worktrees whose outcomes are captured from git evidence, replayed by
their LOGICAL identity, and re-validated against the live registry at
replay time (a stale outcome runs live instead of lying). The dependency points engine → framework: this
module never learns openseek exists.
