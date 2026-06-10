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
- [ ] **Steering a running task.** `Steer` while running is rejected ("press
  Tab to queue") because the engine cannot accept mid-turn input. Needs an
  engine-side protocol (e.g. a control channel on stdin) before the TUI can
  offer it.
- [ ] **Persistent engine per session.** The TUI spawns a fresh engine per
  prompt, so `moon_check --watch` restarts (and re-warms) every turn and its
  watcher state is lost between prompts. A long-lived engine process per
  session — with prompts delivered over a channel — would keep watchers warm
  and is also the prerequisite for steering.

## Engine / agent

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
- [ ] **Richer `--session-list`.** Bare ids are hard to recognize; include
  last-activity time and the first user prompt as a label.
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
- [ ] **Document the TUI session default.** The root README does not yet
  mention that every TUI launch converses in a durable session and how to
  resume one (`--session <id>` from the startup banner).
