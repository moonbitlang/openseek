# agent_subrun

The substrate for subagents in DEDICATED CHILD PROCESSES. A sub-run spawns
the engine's own binary as a parent-managed run of a preset —
`openseek run --input-format json --cancel-on-stdin-eof --kind <kind>
--result-file <path>` — writes one JSON request line on stdin (holding the
pipe open — closing it is the graceful-cancel signal), and reads the child's
result file when it ends: how the run went, its report, and what it cost.
The child's stdout is text for humans and is not read. Parent and child are
the same binary, so the report's derived `to_json`/`from_json` codecs cannot
drift: the process boundary still carries a typed channel.

Layers:

- `run_subrun` (parent side): the ENGINE's layer over the shared contract
  implementation — the spawn/deadline/teardown machinery and the result-file
  transport itself live in `moonbitlang/workflow/spawn` (`contract_run`,
  transport 2 of its child contract), and this wrapper adds subrun ids,
  lifecycle brackets, child sessions, and typed report re-checking. The
  wall deadline closes stdin and grants a grace window before terminating;
  a completed result written in the grace still counts. External
  cancellation re-raises — never folded into a terminal. Crash isolation is
  structural: a dead child is a `Failed` result, not a dead engine. A parent
  with no durable session launches its children with `--no-session`.
- `report_line` (child side of the legacy `openseek subrun` mode): the
  distinguished final stdout line that mode writes — `{"subrun_report": ...}`.
  What a child RUNS to produce its report is not here: the bounded turn
  itself (`execute_kind`, `capture_tool`) lives in `agent_kind`, which never
  spawns and never knows it is in a child.

Known limits: a hard-killed child can orphan its own tool subprocesses (the
upstream group-kill gap) — the stdin-EOF grace path is the mitigation; a
child's cost is known only from its result, so a cancelled sub-run's is not;
Windows support is deferred with background jobs.
