# FsX Toolchain File Helpers

## Goal

Use the new `desktop/internal/fsx` package for the bundled MoonBit toolchain
runtime copy path, while keeping executable bits intact when files are copied.

## Accepted Design

- Keep the initial migration focused on `desktop/internal/host`.
- Make `@fsx.copy_file` preserve whether the source file is executable.
- Replace local host helpers with the matching `fsx` APIs where the behavior is
  equivalent or stricter in the intended way.
- Do not broaden package-side packaging helpers in this change; they use a
  different String-path surface and can be evaluated separately.

## Target Files And Surfaces

- `desktop/internal/fsx/exists.mbt`
- `desktop/internal/host/moonbit_toolchain.mbt`
- `desktop/internal/fsx/pkg.generated.mbti`

## API And Interface Diff

- `@fsx.copy_file` keeps the same public signature but now preserves source
  executable permission on copied files.
- No new public `host` API is expected.

## Open Questions

- None for this step. A later cleanup can decide whether `@fsx.exists` should
  change from a thin `@fs.exists` wrapper to an ENOENT-only helper.

## Next Implementation Step

Update `@fsx.copy_file`, then replace the duplicated read/remove/copy/mkdir
logic in `desktop/internal/host/moonbit_toolchain.mbt`.

## Validation Plan

- Run `moon -C desktop check --target native`.
- Run `moon -C desktop info`.
- Run `moon -C desktop fmt`.
- Review generated interface diffs and final git diff before committing.
