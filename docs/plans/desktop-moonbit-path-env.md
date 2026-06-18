# Desktop MoonBit PATH Environment

## Goal

Make the packaged desktop engine and its agent tools resolve the bundled
`moon` command reliably. The failing symptom is a shell tool result of
`exit=127` with `sh: moon: command not found`, even though the desktop host
prepared a bundled MoonBit home and logged the bundled `bin` directory as the
PATH prefix.

## Accepted Design

- Keep MoonBit toolchain preparation in `desktop/internal/moonbit`.
- Keep engine-side PATH assembly in `desktop/internal/engine`.
- Do not set `MOON_HOME` for the agent engine; only expose bundled `moon`
  through PATH.
- Avoid duplicate `PATH` entries in the child process environment. Build the
  engine environment from `@sys.get_env_vars()`, override `PATH` and the
  OpenSeek-specific variables in that map, and spawn the engine with
  `inherit_env=false`.
- Keep the temporary desktop diagnostic logs until the bundled PATH behavior is
  confirmed.

## Target Files And Surfaces

- `desktop/internal/engine/engine.mbt`: construct a complete engine env map and
  spawn with no inherited duplicate environment.
- `desktop/internal/engine/moon.pkg`: add any needed core-env import.
- Existing diagnostic logging edits in `desktop/launch_log.mbt`,
  `desktop/internal/moonbit/*`, and `desktop/internal/engine/engine.mbt`.

## API And Interface Diff

- No public API change is intended.
- Generated `.mbti` files should remain unchanged.

## Open Questions

- None for this step. If shell still cannot find `moon`, the next check is an
  engine-side log of its actual process PATH.

## Next Implementation Step

Patch `start_serve_engine` so the environment passed to `@process.spawn` has a
single authoritative `PATH`, then rerun focused desktop engine and MoonBit
toolchain tests.

## Validation Plan

- Run `moon -C desktop check internal/engine`.
- Run `moon -C desktop test internal/engine`.
- Run `moon -C desktop test internal/moonbit`.
- Run `moon -C desktop info`.
- Run `moon -C desktop fmt`.
- Review `.mbti` diffs and commit if only expected changes remain.
