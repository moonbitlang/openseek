# Desktop Context-Yield Handling

## Goal

Handle the agent's `context_yield` protocol in the desktop host and frontend so
a context-bounded turn always closes, remains distinct from task success, and
shows the automatic checkpoint consistently with a reloaded durable session.

## Accepted Design

- Treat automatic compaction and context yield as related but distinct events:
  `auto_compaction_finished` carries the checkpoint summary, while
  `context_yield` terminates a turn whose work may still be incomplete.
- Decode `context_yield` in the desktop host and close the active run with a
  distinct `context_yield` wire status. This must drive the same engine-phase
  cleanup as every other run terminal, including a compaction already queued
  behind the turn.
- Decode `auto_compaction_finished` only in the frontend event layer and append
  its summary with the existing `Summary` item and folded "Context compacted"
  card. Do not reuse or mutate the manual `CompactionPhase`: automatic
  compaction happens inside an open turn, while manual compaction is an idle
  lifecycle.
- Decode `context_yield` in the frontend as its own engine event. Preserve the
  engine's continuation guidance as an informational assistant item, then let
  the host's finished notification settle the run with a warning outcome named
  "Context limit reached". The normal answer-deduplication path keeps the raw
  event and finished notification from rendering twice.
- Keep `auto_compaction_started` invisible. The open run already communicates
  activity, and presenting it as manual compaction would create a false
  between-turn state.
- If checkpoint generation fails, no Summary card is appended; the
  `context_yield` guidance explains the uncompacted yield and the run still
  closes.
- Keep Rabbita `update` pure: event handlers return a new model and commands,
  introduce no effect calls or mutable UI collections, and receive idempotence
  coverage for the new messages.
- Reuse the existing transcript kinds and views. Add no CSS, no new
  `ItemKind`, and no trivial transition helpers.

## Target Files And Surfaces

- `desktop/internal/event/event.mbt`, `decode.mbt`, and `decode_test.mbt`:
  represent and decode the host-side `ContextYield` terminal.
- `desktop/internal/engine/api.mbt`, `engine.mbt`, and `engine_wbtest.mbt`:
  emit the distinct run status, close the serve-engine run, and cover terminal
  classification.
- `desktop/frontend/transcript/engine_event.mbt` and
  `engine_event_wbtest.mbt`: normalize `auto_compaction_finished` and
  `context_yield` for Rabbita update handling.
- `desktop/frontend/update.mbt` and `update_wbtest.mbt`: append the existing
  Summary card and continuation guidance, preserve pure/idempotent transitions,
  and route the in-run events by run id.
- `desktop/frontend/model.mbt`: parse, label, and style the private
  context-yield run outcome as a warning rather than success.
- `desktop/frontend/transcript/sessions_wbtest.mbt`: pin live/reload parity for
  a durable Summary followed by the context-yield terminal.
- Generated `pkg.generated.mbti` files for packages whose public event enums
  gain constructors.

## API And Interface Diff

- `desktop/internal/event.AgentEvent` gains `ContextYield(String)`.
- `desktop/frontend/transcript.EngineEvent` gains
  `AutoCompactionFinished(String)` and `ContextYield(String)`.
- The host's private `RunStatus` and frontend's private `RunOutcome` each gain a
  context-yield case; their only external representation is the existing
  `status` string field with the new value `"context_yield"`.
- `ItemKind`, `CompactionPhase`, bridge payload shapes, and CSS remain
  unchanged.
- Generated interfaces should change only for the two public event enums above.

## Open Questions

- None. A future dedicated neutral transcript notice is intentionally out of
  scope; the engine guidance and warning outcome use existing UI surfaces.

## Next Implementation Step

Add the host event decoder and terminal status mapping, then wire the two raw
events through the frontend's normalized event enum and pure update branches.

## Validation Plan

- Add focused host and frontend decoder tests.
- Add Rabbita update tests that apply the new messages twice to the same input
  model and compare every modified plain-data field or state shape.
- Add an end-to-end update-state test for
  `auto_compaction_finished -> context_yield -> finished`, including run
  closure, warning outcome, one Summary item, one guidance item, and no manual
  compaction phase change.
- Add a durable-session transcript test proving the reloaded Summary and
  guidance match the live transcript.
- Run `moon -C desktop check --target native --deny-warn` and
  `moon -C desktop check --target js --deny-warn`.
- Run focused package tests, then `moon -C desktop test --release`.
- Run `moon -C desktop fmt` and default-target `moon -C desktop info`, review
  generated interface diffs, and re-run the checks affected by formatting.
