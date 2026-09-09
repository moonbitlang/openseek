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
- `report_line` (child side): the distinguished final stdout line a child
  writes — `{"subrun_report": ...}` — which the parent's contract runner
  extracts. What the child RUNS to produce that report is not here: the
  bounded turn itself (`execute_kind`, `capture_tool`) lives in
  `agent_kind`, which never spawns and never knows it is in a child.
- `SubrunBudget`: a reusable per-turn CALL allowance for direct consumers.
  The CLI's model-initiated delegation uses hosted workflows and their
  reserved child blocks instead; the automatic goal-met gate has its own allowance.
Known limits: a hard-killed child can orphan its own tool subprocesses (the
upstream group-kill gap) — the stdin-EOF grace path is the mitigation;
Windows support is deferred with background jobs.
