# agent_workflow

The openseek adapter for the engine-neutral
[`moonbitlang/workflow`](https://github.com/moonbitlang/workflow) library. The dependency
points ENGINE → FRAMEWORK: the workflow module never learns openseek
exists; this package hands it a `Runner`.

## The contract is the interface

Agents run as child processes speaking the workflow child contract — one
versioned request envelope on stdin (`{"workflow_contract": 1, id, kind,
max_steps?, input}`, the pipe held open: EOF is graceful cancel), JSONL
protocol events plus a final `{"subrun_report": ...}` line on stdout.
`openseek subrun <kind>` speaks it natively (it is the engine's own
subagent channel); ANY binary that speaks it plugs in unchanged. The
contract in full — and what this engine reads from the envelope versus
argv — is documented in the library's
[docs/child-contract.md](https://github.com/moonbitlang/workflow/blob/main/docs/child-contract.md). The
tests — and the block below, which compiles and runs with this package's
test suite — drive everything with scripted `sh` children:

```mbt check
///|
async test "drive a scripted engine through the adapter" {
  // Probe spawnability with the LOW-LEVEL process API so only a
  // genuinely spawn-hostile sandbox skips.
  let can_spawn = (@process.run("sh", ["-c", "exit 0"]) catch { _ => -1 }) == 0
  guard can_spawn else {
    println("skipped: cannot spawn sh")
    return
  }
  // Any process speaking the contract is an engine — here `sh` reports a
  // canned answer after one accounted usage event.
  let script =
    #|read line
    #|printf '{"event":"usage","usage":{"prompt_tokens":7,"completion_tokens":3,"total_tokens":10,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":7}}\n'
    #|printf '{"subrun_report": {"answer": 42}}\n'
  let wf = @workflow.Workflow(
    runner=@agent_workflow.subrun_runner(
      exe="unused",
      deadline_ms=10_000,
      // The seam receives the CANONICAL launch spec (exe, subrun argv,
      // cwd, deadline) and may transform it — here: redirect to sh.
      map_launch=(spec, _) => { ..spec, command: "sh", args: ["-c", script], },
    ),
  )
  assert_eq(wf.agent(prompt="what is the answer?", kind="echo"), {
    "answer": 42,
  })
  assert_eq(wf.tokens_spent(), 10)
}
```

- `subrun_runner(exe~, ..)` — read-only kinds (`explore`, `review`,
  `echo`): canonical `LaunchSpec` construction (with the `map_launch`
  transform seam), per-kind wall deadlines, the `extra_env` credential
  overlay (keys never ride argv), and a lossless
  `SubrunTerminal → AgentOutcome` mapping so even a timed-out child's
  spend reaches the budget and the journal.
- `openseek_runner(exe~, workspace_root~, ..)` — everything above plus
  write-capable `worker` slices, capped at `max_workers` (default 4,
  matching the engine).

## Worker slices

`worker(wf, name~, task~, allowed_paths~)` runs ONE confined slice:
provision a git worktree limited to disjoint `allowed_paths`, run the
child inside it, then capture the outcome from GIT EVIDENCE — never from
the child's claims. Success requires BOTH a completed child (`Captured`
terminal with a contract-valid report) AND a mergeable capture
(`Committed`, or a clean `NoChanges` the report did not disclaim). A
truncated child's mergeable edits are salvaged onto the branch and stay
inspectable via `slices()`, but never masquerade as completion:

```moonbit nocheck
///|
let wf = @workflow.Workflow(
  runner=@agent_workflow.openseek_runner(exe~, workspace_root~),
  journal=@workflow.Journal::load(".openseek/workflow.jsonl"),
)
let outcome = @agent_workflow.worker(
  wf,
  name="rename-api",
  task="rename Foo to Bar across lib/",
  allowed_paths=["lib/"],
)
guard outcome is { "state": "Committed", .. } else { ... }
let _ = @agent_workflow.integrate_slice(workspace_root~, name="rename-api")
```

Replay identity is the LOGICAL slice — `{name, task, allowed_paths,
context?}` — while physical worktree paths stay out of the journal. On
resume, a journalled `Committed` outcome is served only after
re-validation against the live registry (same name, branch, commit,
still `Committed`, in THIS worktree — a typed `ReplayDecision`);
anything stale runs live instead of lying.

Lifecycle: `integrate_slice` merges the one ACTIVE slice with that name
(names are reusable across generations; ambiguity is refused rather than
guessed), `discard_slice` abandons it, `slices()` lists every generation.

## Known limits

- No adapter-level `continue` for truncated slices yet. An EXTERNALLY
  cancelled child (the workflow torn down mid-slice) re-raises before
  git capture and leaves its entry `Running`, which only discard can
  clear (provisioning's resume path accepts `Committed`/`Captured`,
  not `Running`). A child cancelled by the wall DEADLINE is different:
  it reaches capture as `TimedOut`, so mergeable edits are salvaged and
  the slice can be continued through the engine's `subtask continue`.
- Provision refusals and non-mergeable captures both surface as
  `AgentFailure::Failed(reason)` — a typed split is future work.
- One writing workflow process per journal path, and one engine per
  repository for the subtask registry (it has no cross-process locking).
- A worker waiting for a worker slot already holds one of the workflow's
  `max_concurrent` slots and has been counted as launched: saturating
  `max_workers` can head-of-line block scouts sharing the workflow.
- `@agent_subtask`'s mutators trust registry-loaded entries; treat that
  package's surface as controller-grade, not sandbox-grade.
