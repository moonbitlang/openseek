# Desktop Review: Serve Pump Follow-ups

## Goal

Address the new active #56 review threads on the desktop persistent serve
bridge:

- Make serve engine workspace selection immune to inherited `OPENSEEK_DIR`.
- Keep trailing `steer_applied` / `steer_dropped` events on the run they
  originally settled.
- Do not mark the frontend bridge ready until the host pump has actually
  started.

## Accepted Design

- Pass `--dir .` in every serve engine command. The host already sets the
  native process cwd, and WSL uses `wsl.exe --cd`, so `.` means the host-chosen
  workspace while also overriding inherited `OPENSEEK_DIR`.
- Add a private `settling_run` field to `ServeEngine`. Terminal events record
  the completed run there; trailing steer settle events use it until the next
  non-steer event proves a new turn has started.
- Emit an internal `openseek.connected` event after `run_engine_pump` flips
  `pump_running`. The frontend wires events first, starts the long-lived
  `connect` call, and dispatches `BridgeReady` only from this event.

## Target Files And Surfaces

- `desktop/internal/host/engine.mbt`
- `desktop/internal/host/wsl.mbt`
- `desktop/internal/host/engine_wbtest.mbt`
- `desktop/internal/host/wsl.mbt` tests
- `desktop/frontend/bridge.mbt`

## API / Interface Diff

No public package API change is intended. The only new wire signal is an
internal desktop host event, `openseek.connected`, consumed by the bundled
frontend.

## Open Questions

None. The changes are deliberately private to the desktop host/frontend bridge.

## Next Implementation Step

Patch the host state machine and bridge event wiring, then add focused
white-box tests for command arguments and run-id selection.

## Validation Plan

- `moon -C desktop test internal/host`
- `moon -C desktop test --target js frontend`
- `moon -C desktop check`
- `moon -C desktop fmt`
- `moon -C desktop info`
