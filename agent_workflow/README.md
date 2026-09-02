# agent_workflow

The openseek adapter for the engine-neutral
[`bobzhang/workflow`](../workflow/README.mbt.md) library. The dependency
points ENGINE → FRAMEWORK: the workflow module never learns openseek
exists; this package hands it a `Runner`.

## The contract is the interface

Agents run as child processes speaking the subrun contract — one JSON
input line on stdin, JSONL protocol events plus a final
`{"subrun_report": ...}` line on stdout, stdin EOF as graceful cancel.
`openseek subrun <kind>` already speaks it (it is the engine's own
subagent channel); ANY binary that speaks it plugs in unchanged — the
tests here drive everything with scripted `sh` children, and a shim
around a foreign engine (a Rust CLI, say) is ~100 lines of framing
translation.

- `subrun_runner(exe~, ..)` — read-only kinds (`explore`, `review`,
  `echo`): canonical `LaunchSpec` construction (with a `map_launch` transform seam), per-kind wall deadlines, the
  `extra_env` credential overlay (keys never ride argv), and a lossless
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
inspectable via `slices()`, but never masquerade as completion.

Replay identity is the LOGICAL slice — `{name, task, allowed_paths,
context?}` — while physical worktree paths stay out of the journal. On
resume, a journalled `Committed` outcome is served only after
re-validation against the live registry (same name, branch, commit,
still `Committed`); anything stale runs live instead of lying.

Lifecycle: `integrate_slice` merges the one ACTIVE slice with that name
(names are reusable across generations; ambiguity is refused rather than
guessed), `discard_slice` abandons it, `slices()` lists every generation.

## Known limits

- No adapter-level `continue` for truncated slices yet. A cancelled
  child leaves its entry `Running`, which only discard can clear
  (provisioning's resume path accepts `Committed`/`Captured`, not
  `Running`); a truncated-but-captured slice can be continued through
  the engine's `subtask continue`.
- Provision refusals and non-mergeable captures both surface as
  `AgentFailure::Failed(reason)` — a typed split is future work.
- One writing workflow process per journal path, and one engine per
  repository for the subtask registry (it has no cross-process locking).
- A worker waiting for a worker slot already holds one of the workflow's
  `max_concurrent` slots and has been counted as launched: saturating
  `max_workers` can head-of-line block scouts sharing the workflow.
- `@agent_subtask`'s mutators trust registry-loaded entries; treat that
  package's surface as controller-grade, not sandbox-grade.
