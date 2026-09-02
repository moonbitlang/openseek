# agent_subrun

The substrate for subagents in DEDICATED CHILD PROCESSES. A sub-run spawns
the engine's own binary as `openseek subrun <kind>`, writes one JSON input
line on stdin (holding the pipe open — closing it is the graceful-cancel
signal), drains the child's standard JSONL event stream for exact cost
accounting, and captures the final `{"subrun_report": ...}` line. Parent and
child are the same binary, so the report's derived `to_json`/`from_json`
codecs cannot drift: the process boundary still carries a typed channel.

Layers:

- `run_subrun` (parent side): the ENGINE's layer over the shared contract
  implementation — the spawn/drain/deadline/teardown machinery itself
  lives in `moonbitlang/workflow/spawn` (`contract_run`), and this wrapper
  adds subrun ids, lifecycle brackets, child sessions, and typed report
  re-checking. The wall deadline closes stdin and grants a grace window
  before terminating; a report arriving in the grace still counts.
  External cancellation re-raises — never folded into a terminal. Crash
  isolation is structural:
  a dead child is a `Failed` result, not a dead engine.
- `execute_kind` (child side): one bounded turn with a restricted toolset
  and a `capture_tool` submit channel — run by the `subrun` child mode, by
  the standalone review CLI (already its own process), and by unit tests
  (the full capture/retry/ceiling-salvage lifecycle needs no spawning).
- `SubrunBudget`: the per-turn CALL allowance shared by model-initiated
  subrun tools — a runaway backstop, reserved before launch; every granted
  child runs at its kind's full step ceiling (engine-initiated subruns
  like the goal-met gate bypass it).
- `capture_tool`: parse/validate, reject-with-retry, capture +
  `Control(Finish)`, `control=true` so the loop's ceiling salvage honors a
  pending submission.

Known limits: a hard-killed child can orphan its own tool subprocesses (the
upstream group-kill gap) — the stdin-EOF grace path is the mitigation;
Windows support is deferred with background jobs.
