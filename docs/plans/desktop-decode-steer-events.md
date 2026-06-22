# Desktop Decode Steer Events

## Goal

Make `decode_event` the single host-side decoder for known engine JSONL events,
including serve-mode steer acknowledgments.

## Accepted Design

- Extend `AgentEvent` with `SteerApplied(String)` and `SteerDropped(String)`.
- Decode `"steer_applied"` and `"steer_dropped"` from their `"content"` field.
- Have the engine run-id tracker consume decoded events instead of re-parsing
  raw JSON through protocol helpers.
- Keep steer acknowledgments non-terminal and still forward their original raw
  event to the webview with the selected run id.
- Remove protocol-level raw JSON helpers that only duplicated event decoding.

## Target Files And Surfaces

- `desktop/internal/event/event.mbt`: add steer acknowledgment variants.
- `desktop/internal/event/decode.mbt`: decode the two known events.
- `desktop/internal/event/decode_test.mbt`: cover the new decoder cases.
- `desktop/internal/engine/engine.mbt`: compute run ids from decoded events.
- `desktop/internal/engine/engine_wbtest.mbt`: update tracker tests to use
  decoded events.
- `desktop/internal/protocol/engine_command.mbt`: remove obsolete event helper
  functions.
- Generated interfaces:
  - `desktop/internal/event/pkg.generated.mbti`
  - `desktop/internal/protocol/pkg.generated.mbti`

## API And Interface Diff

- `desktop/internal/event` public API adds:
  - `AgentEvent::SteerApplied(String)`
  - `AgentEvent::SteerDropped(String)`
- `desktop/internal/protocol` public API removes:
  - `is_steer_settle_event(Json) -> Bool`
  - `stream_event_content(Json) -> String`

## Open Questions

- None for this step.

## Next Implementation Step

Update the event enum and decoder, switch the run-id tracker to decoded events,
then remove the now-unused raw protocol helpers.

## Validation Plan

- Run `moon check`.
- Run targeted tests for `desktop/internal/event` and `desktop/internal/engine`.
- Run `moon info && moon fmt`.
- Run `moon test`.
- Review generated `.mbti` diffs for only the expected API changes.
