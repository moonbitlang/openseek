# Desktop Host Package Split

## Goal

Separate the desktop host's responsibilities so the lepus extension adapter,
engine runtime, serve protocol, and bundled MoonBit toolchain do not all live in
one `desktop/internal/host` package.

## Accepted Design

- `desktop/internal/extension` owns the lepus app-command extension surface:
  extension id, namespace, frontend IPC payload/reply types, event emission, skill
  ops, session op wrappers, frontend asset lookup, runtime dir lookup, and stale
  framework config cleanup.
- `desktop/internal/protocol` owns the `openseek --serve` JSONL protocol helpers:
  prompt/steer/cancel commands and stream-event helpers needed by the engine.
- `desktop/internal/engine` owns all engine execution behavior: engine executable
  discovery, native/WSL host selection, run config, persistent serve-engine
  lifecycle, one-shot engine stdout helpers, session root resolution, and
  per-session workspace directories.
- `desktop/internal/moonbit` owns bundled MoonBit toolchain discovery,
  preparation, bundle stamps, and command paths.
- `desktop/internal/engine` decides how the prepared MoonBit toolchain is exposed
  to the native engine. The current engine tools spawn `moon` by name, so native
  engine runs prepend the prepared `bin` directory to `PATH`. They do not set
  `MOON_HOME`, because that redirects MoonBit registry/cache lookup into the
  runtime toolchain payload and breaks projects that depend on registry packages.
- Remove `desktop/internal/host`, `desktop/internal/appdirs`, and
  `desktop/internal/sessiondirs` after their contents move. Do not keep
  compatibility shims because current callers are desktop-internal.

## Target Files And Surfaces

- Move `desktop/internal/host/extension.mbt`, `protocol.mbt`, and
  `skills_ops.mbt` into `desktop/internal/extension`.
- Move `desktop/internal/host/engine.mbt`, `ops.mbt`, `config.mbt`, `wsl.mbt`,
  and related tests into `desktop/internal/engine`.
- Move `desktop/internal/host/engine_command.mbt` and its tests into
  `desktop/internal/protocol`.
- Move `desktop/internal/host/moonbit_toolchain.mbt` plus MoonBit-specific
  helpers from `desktop/internal/appdirs/toolchain.mbt` into
  `desktop/internal/moonbit`.
- Move session root/workspace logic from `desktop/internal/sessiondirs` into
  `desktop/internal/engine`.
- Move app startup helpers from `desktop/internal/appdirs` into
  `desktop/internal/extension`, except for `engine_command`, which moves to
  `desktop/internal/engine`.
- Update `desktop/main.mbt`, `desktop/launch_log.mbt`, and package imports.

## API And Interface Diff

- `openseek_desktop/internal/host` is removed.
- `openseek_desktop/internal/appdirs` is removed.
- `openseek_desktop/internal/sessiondirs` is removed.
- `openseek_desktop/internal/extension` exposes the extension surface and app
  startup helpers used by `desktop/main.mbt`.
- `openseek_desktop/internal/engine` exposes only the engine manager and runtime
  operations required by `extension`.
- `openseek_desktop/internal/protocol` exposes only the serve protocol command
  and event helpers required by `engine`.
- `openseek_desktop/internal/moonbit` exposes only the toolchain preparation
  helper required by `engine`.

## Follow-up: Native Engine MoonBit Environment

- Goal: keep bundled `moon` available to the native engine without isolating its
  package registry.
- Accepted design: `moonbit` only prepares a bundled MoonBit home. `engine`
  prepends `moon_home/bin` to `PATH` for native runs and must not set
  `MOON_HOME`.
- Target surface: `desktop/internal/engine/engine.mbt` private environment
  setup. No public `.mbti` change is expected.
- Validation plan: `moon -C desktop test internal/engine`, `moon -C desktop
  info`, and `moon -C desktop fmt`.

## Follow-up: Bundled MoonBit Preparation Errors

- Goal: make bundled MoonBit preparation failures recoverable by the engine
  startup path.
- Accepted design: `prepare_bundled_home` raises a regular `Failure` for missing
  seeds or failed payload preparation instead of aborting the process. Do not add
  a public MoonBit-toolchain error type unless callers need to pattern-match it.
- Target surface: `desktop/internal/moonbit/moonbit_toolchain.mbt` and a focused
  moonbit package test. No public `.mbti` change is expected.
- Validation plan: `moon -C desktop test internal/moonbit`, `moon -C desktop
  test internal/engine`, `moon -C desktop info`, and `moon -C desktop fmt`.

## Open Questions

- None. The session directory logic is intentionally folded into `engine`.

## Next Implementation Step

Create the new packages, move the existing cohesive files into them, then adjust
visibility/imports until the generated `.mbti` files show only intentional
cross-package APIs.

## Validation Plan

- `moon -C desktop test internal/protocol`
- `moon -C desktop test internal/engine`
- `moon -C desktop test internal/extension`
- `moon -C desktop info`
- `moon -C desktop fmt`
- Review `.mbti` and `git diff` before committing.
