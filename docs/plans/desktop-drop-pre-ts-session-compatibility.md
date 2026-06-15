# Desktop Drop Pre-ts Session Compatibility

## Goal

Remove the desktop PR's compatibility layer for event logs written before
`SessionEvent` had a `ts` field.

## Accepted Design

- Keep the current `ts` field for newly written session events.
- Stop accepting session event JSON objects that omit `ts`.
- Remove the store workaround that fingerprints stored event-log bytes after a
  tolerant pre-`ts` decode.
- Keep the existing desktop behavior for session-load failures: the host returns
  a `session load failed: ...` error and the frontend displays it as an error
  bubble in the active or targeted conversation.

## Target Files And Surfaces

- `agent_session/json.mbt`
- `agent_session/types.mbt`
- `agent_session/pkg.generated.mbti`
- `agent_session/session_test.mbt`
- `agent_session/store/store.mbt`
- `agent_session/store/store_test.mbt`

## API And Interface Diff

- `SessionEvent` uses the derived `FromJson` implementation again.
- Loading old event logs without `ts` is no longer supported.

## Open Questions

- None.

## Next Implementation Step

Restore the affected `agent_session` files to `origin/main` and run the
session package checks.

## Validation Plan

- Run `moon test agent_session`.
- Run `moon test agent_session/store`.
- Run `moon check agent_session`.
- Run `moon check agent_session/store`.
- Run `moon fmt && moon info`.
