# Desktop Review: Stale Update Replies

## Goal

Address the remaining PR #56 review follow-ups after the serve pump fixes:

- Make the desktop serve engine's working directory override explicit at the
  process environment boundary.
- Drop stale session-load failures after the user has abandoned that load.
- Avoid duplicate undelivered-steer notices after a run-end sweep already
  surfaced the pending steer.

## Accepted Design

- Set `OPENSEEK_DIR` to `"."` in the serve engine spawn environment, matching
  the existing `--serve --dir .` command arguments.
- Include `OPENSEEK_DIR/u` in the WSL passthrough list so WSL-hosted serve
  engines see the same explicit override.
- In frontend update handling, only surface `Failed(session=...)` without an
  existing conversation when `loading_session` still equals that session.
  Otherwise the failure belongs to an abandoned load and is dropped.
- For `SteerUndelivered`, settle the pending steer first and append the dropped
  notice only if a pending entry was actually removed.

## Target Files And Surfaces

- `desktop/internal/host/engine.mbt`: serve spawn environment.
- `desktop/internal/host/wsl.mbt`: WSL environment passthrough list.
- `desktop/frontend/update.mbt`: stale failure and undelivered steer handling.
- `desktop/frontend/update_wbtest.mbt`: regression coverage.

## API / Interface Diff

No public MoonBit API change is intended. `moon info` should not introduce
frontend or host interface churn beyond generated metadata that already matches
the current source.

## Open Questions

None.

## Next Implementation Step

Apply the minimal logic changes above, then add regression tests for abandoned
load failures and late undelivered-steer replies after a run-end sweep.

## Validation Plan

- `moon -C desktop test --target js frontend`
- `moon -C desktop check`
- `moon -C desktop fmt`
- `moon -C desktop info`

`moon -C desktop test internal/host` currently reaches a local native link
failure for WebKit in this workspace; use `moon -C desktop check` for host type
coverage unless that local dependency issue is fixed.
