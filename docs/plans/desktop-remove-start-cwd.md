# Desktop Remove Start CWD

## Goal

Remove the stale desktop start-payload working-directory input. The desktop UI
must not let a user choose or type the agent cwd; the host derives a stable
workspace from the durable session id and reports that path back for display.

## Accepted Design

- Remove `cwd` from the host `StartPayload` wire type.
- Keep `StartedPayload.cwd` because it is host-to-frontend display state.
- Simplify `resolved_run_cwd` so it only derives from the session workspace and
  falls back to the user's home directory.
- Remove `@home.expand` because no desktop caller should expand user-provided
  cwd text anymore.
- Keep WSL cwd handling for host-derived workspaces only.

## Target Files And Surfaces

- `desktop/internal/host/protocol.mbt`
- `desktop/internal/host/config.mbt`
- `desktop/internal/home/home.mbt`
- generated interfaces for touched packages
- focused tests under `desktop/internal/host` / `desktop/internal/home`

## API And Interface Diff

- `openseek` start IPC no longer accepts a `cwd` field.
- `openseek` started IPC still emits `cwd`.
- `openseek_desktop/internal/home.expand` is removed from the package
  interface.

## Open Questions

- Validation is currently blocked by an adjacent, pre-existing `@home.dir()`
  API migration in the working tree. `desktop/internal/skillmarket/library.mbt`,
  `desktop/internal/userdirs/documents.mbt`, and the restored
  `desktop/internal/home/home_wbtest.mbt` still use the old `String` helper
  shape while `@home.dir()` now returns `@path.Path?`.

## Next Implementation Step

Either finish that separate `@home.dir()` migration with explicit approval, or
temporarily put those local changes aside, then rerun validation and generate
interfaces.

## Validation Plan

- Run `moon -C desktop check --target native`.
- Run targeted tests for `desktop/internal/host` and `desktop/internal/home`.
- Run `moon -C desktop info && moon -C desktop fmt`.
- Review diffs and commit only this cleanup, excluding unrelated local debug
  edits.
