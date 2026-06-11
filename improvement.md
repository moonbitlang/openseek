# Improvement Checklist

Observations collected while working on streaming, sessions, and documentation
(June 2026). Each item is small enough to land as its own PR; none blocks
current functionality. Check items off as they land, and add new ones at the
bottom of the matching section.

## TUI

- [x] **Collapse the triple redraw per message.** `refresh_ui` calls
  `set_status`, `set_activity`, and `set_queued_inputs`, each of which queues
  its own full-frame redraw — three repaints per message-loop iteration.
  During delta bursts this triples render work. Add a single
  "set view state + one redraw" command on `Ui`. *(Done: `Ui::set_live_view`
  replaces the three setters; one command, one redraw per loop turn.)*
- [x] **Keep reasoning visible after the turn.** Thinking-mode reasoning only
  ever exists as the transient `Thinking …` tail and is discarded once
  content starts. Surface it as a dimmed/collapsible transcript item so a
  user can review *why* the model did something. *(Done: the engine emits
  `reasoning_message` after streaming; the TUI commits a `✻` thought aside
  above the answer. Resume does not replay thoughts — sessions do not store
  reasoning for no-tool turns; see the auto-compaction/session items.)*
- [x] **Measure the activity label instead of reserving 13 columns.**
  `ActivityPreviewReservedColumns` hardcodes indent + widest label + slack;
  computing it from the actual label keeps the preview honest if labels
  change. *(Done: `streaming_activity_line` measures the label's display
  width; only the renderer indent + slack remain a constant.)*
- [x] **`--continue` resumes the most recent session.** *(Done:
  `SessionStore::latest` picks the most recently active session by event-log
  mtime; `openseek-tui --continue` resumes it, errors when combined with
  `--session`, and starts fresh on an empty store.)*
- [ ] **Session switching inside the TUI.** A way to list and switch sessions
  without restarting. Generated ids (`tui-YYYYMMDD-HHMMSS-mmm`) are only
  discoverable via the startup banner or `openseek --session-list` today.
- [x] **Steering a running task.** `Steer` while running is rejected ("press
  Tab to queue") because the engine cannot accept mid-turn input. Needs an
  engine-side protocol (e.g. a control channel on stdin) before the TUI can
  offer it. *(Done: Enter while running steers — the text rides the serve
  protocol's lossless channel, lands at the turn's next step boundary, wins
  over model-initiated completion, and is echoed into the transcript at the
  position the model actually saw it.)*
- [x] **Persistent engine per session.** The TUI spawns a fresh engine per
  prompt, so `moon_check --watch` restarts (and re-warms) every turn and its
  watcher state is lost between prompts. A long-lived engine process per
  session — with prompts delivered over a channel — would keep watchers warm
  and is also the prerequisite for steering. *(Done: one `--serve` engine per
  TUI session — JSONL commands on stdin, shared runtime and tool registry
  across turns, Ctrl-C cancel → kill escalation, respawn on death from the
  durable session.)*

## Engine / agent

Findings from a real 156-step session log (seek-toml, 2026-06-11: "Write a
toml parser in MoonBit with high quality tests" — succeeded, but the log
shows where steps and tokens went to waste):

- [x] **One watcher per directory, not per option set.** The `moon_check`
  registry keys watchers by the full option set, so toggling `deny_warn`
  stacked three concurrent watchers on one cwd. They competed for moon's
  build lock with each other and with the model's own `moon test` runs,
  produced stale results, and the model ended up running `pkill -9 -f
  "moon check"` mid-task to recover. Same cwd + new options should replace
  (stop) the old watcher. *(Done: the registry keys by cwd; a running
  watcher is reused when the incoming command matches and stopped+replaced
  (`watcher=replaced`) when the options changed, with the tool description
  telling the model so.)*
- [x] **Stop resending historical `reasoning_content`.** The request encoder
  sends stored reasoning back on every historical assistant message — 11%
  of a 141K-token final context was old reasoning the model never needs
  again (DeepSeek's own docs say not to pass it back). Drop it when
  projecting session history to API messages. *(Done: the wire encoder
  never emits `reasoning_content` — the right chokepoint, since the 11%
  accrued within a single 156-step turn via the agent's incremental
  pushes, not only across turns. Sessions still store reasoning for the
  TUI transcript and the visualizer.)*
- [ ] **Deduplicate watcher notices.** 61 `[moon_check update]` runtime
  notices (11% of final context) were appended, mostly identical
  re-reports from the duplicate watchers. Coalesce per watcher: a new
  notice should supersede the previous one when nothing changed.
- [ ] **First-class API-lookup tool (or document the probe recipe).** The
  model spent ~25 steps probing stdlib APIs: repeated `moon ide doc`
  queries that returned "No results found" (7KB of failed lookups in one
  result), 8 consecutive failed one-liner compile experiments against
  `@strconv`, and one `moon ide` OCaml assertion crash. Better query
  ergonomics (or a documented snippet-eval recipe) converts that tail of
  failures into one or two steps.
- [ ] **Encourage batching independent tool calls.** 154 of 156 steps made
  exactly one tool call; the model proved it can batch (it opened with two
  parallel reads). A system-prompt nudge for batching independent
  reads/checks would cut round trips — at ~7s a step, real minutes.
- [x] **Timestamps on session events.** `events.jsonl` lines carry no
  timestamps, so per-step latency and where wall-clock went cannot be
  reconstructed from the log (this analysis had to infer duration from
  file mtimes). One `ts` field per event line fixes it and feeds the viz.
  *(Done: the store stamps every appended event with `ts` (unix ms,
  required field — no external users, so old logs are simply re-created;
  in-memory appends without a clock carry the 0 sentinel).)*

- [x] **Expose thinking controls.** `run_with_runtime` hardcodes
  `thinking=Enabled, reasoning_effort=Max`; make them engine flags
  (`--thinking`, `--reasoning-effort`) and TUI pass-throughs. *(Done:
  `OPENSEEK_THINKING` / `OPENSEEK_REASONING_EFFORT` env-backed flags on both
  binaries, threaded through `@agent.run*` as optional params with the old
  hardcoded values as defaults.)*
- [ ] **Auto-compaction.** Compaction exists only as the manual
  `--session-compact-*` flow. Long-lived sessions (now the TUI default)
  grow without bound; trigger summarization when the projected context
  passes a threshold.
- [x] **Richer `--session-list`.** Bare ids are hard to recognize; include
  last-activity time and the first user prompt as a label. *(Done:
  `SessionStore::listings` returns id + last-activity + first prompt, newest
  first with unreadable sessions kept visible for cleanup; the CLI prints
  tab-separated rows, so `| cut -f1` recovers the old bare-id output.)*
- [ ] **Stale `session.lock` recovery.** Verify what happens when an engine
  crashes while holding the lock, and document (or implement) the recovery
  path.
- [ ] **Flush the JSONL queue on hard crash.** The stdout drain trades
  crash-tail durability for purity (no C stub): lines queued but unwritten
  when the process aborts are lost. A panic hook that drains synchronously
  would close the gap.
- [ ] **Cheapen the engine probe.** `engine_launchable` spawns
  `<engine> --help` on every TUI launch; cache the result per engine path
  (mtime-keyed) or accept the first spawn failing fast instead.

## DeepSeek client

- [ ] **Unify `chat` and `chat_stream`.** They share request encoding but
  duplicate response and error handling. Implementing `chat` as
  streaming-with-no-callbacks leaves one wire path to maintain.
- [ ] **Retry transient HTTP failures.** Both entry points are single-shot;
  a bounded retry with backoff on connect/5xx errors would remove the most
  common spurious turn failures.

## Testing / CI

- [ ] **More CI platforms.** CI is a single `check (nightly)` job; the TUI's
  pty handling and the engine's stdio behavior are platform-sensitive
  (macOS pty quirks surfaced during verification). Add macOS, then Windows.
- [x] **Make the live cram lifecycle test extension-proof.** It asserts an
  exact event-name set and broke when `*_delta` events were added (now
  filtered). Assert the stable lifecycle subset is *present* instead of
  asserting the full set. *(Done: the example whitelists the lifecycle
  events, so new payload event kinds cannot break it.)*
- [ ] **Checked-in TUI integration harness.** The pty driver used to verify
  streaming and session memory lives outside the repo. Pair a small pty
  driver with a recorded-stream replay engine (the TUI already accepts
  `--engine <replayer>`) for deterministic offline TUI tests.
- [ ] **Run `moon fmt --check` before push.** Two consecutive PRs hit
  CI-only formatting failures; a pre-push hook or documented `moon` alias
  would catch them locally.

## Docs / prompts

- [ ] **Doc-exemplary prompt examples.** `prompt/moon.pkg` opts the system
  prompt out of `missing_doc` because its example code blocks are
  model-facing text. Consider documenting those examples *as a prompt
  change* (with an eval run) so the model also learns the doc convention.
- [x] **Document the TUI session default.** The root README does not yet
  mention that every TUI launch converses in a durable session and how to
  resume one (`--session <id>` from the startup banner). *(Done: the README
  gains a Terminal UI section covering default sessions, `--continue`,
  `--session`, and the enriched `--session-list`, plus a `cmd/tui` row in
  the packages table.)*
