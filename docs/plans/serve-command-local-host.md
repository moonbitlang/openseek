# Serve Command Local Host

## Goal

Stop hand-building serve-mode engine stdin commands in the desktop host while
keeping the refactor scoped to `desktop/internal/host`.

## Accepted Design

- Add a private `EngineCommand` enum inside `desktop/internal/host`.
- Encode the existing serve wire shape from that enum:
  - prompt: `{ "command": "prompt", "text": ... }`
  - steer: `{ "command": "steer", "text": ... }`
  - cancel: `{ "command": "cancel" }`
- Keep this package-local for now. Do not extract a cross-module protocol package
  or change TUI / engine serve code in this step.
- Preserve current write error handling and run lifecycle behavior.

## Target Files And Surfaces

- `desktop/internal/host/engine_command.mbt`: private command type and encoder.
- `desktop/internal/host/engine_command_wbtest.mbt`: white-box tests for command
  encoding.
- `desktop/internal/host/ops.mbt`: replace three JSON literals with
  `EngineCommand` values.

## API And Interface Diff

- No public API change is intended.
- `desktop/internal/host/pkg.generated.mbti` should remain unchanged.

## Open Questions

- None for this step. Shared protocol extraction remains a later refactor.

## Next Implementation Step

Add the private command type, replace the prompt/cancel/steer writes, then run
targeted host tests and workspace checks.

## Validation Plan

- Run `moon -C desktop test internal/host`.
- Run `moon check --target native`.
- Run `moon info`.
- Run `moon fmt`.
- Review `.mbti` diffs and commit if only expected changes remain.
