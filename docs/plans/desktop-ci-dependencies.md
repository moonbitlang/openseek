# Desktop CI Dependencies

## Goal

Keep the root CI checks focused on the root OpenSeek workspace while preserving
separate desktop packaging checks for the desktop app.

## Accepted Design

- The root `moon.work` should contain only the root workspace members and should
  not include `desktop` or `desktop/lepus` modules.
- The existing `desktop/moon.work` remains the desktop-local workspace for
  `desktop` and `desktop/lepus` modules.
- The root `check` job should keep using `moon test`; with desktop removed from
  root `moon.work`, it will not run desktop or Lepus submodule tests.

## Target Files And Surfaces

- `.github/workflows/ci.yml`
- `moon.work`
- `desktop/moon.work`

## API / Interface Diff

- No public MoonBit API changes are intended.
- Generated `.mbti` files should remain unchanged.

## Open Questions

- None.

## Next Implementation Step

Remove desktop-related members from root `moon.work` and restore the root CI
test command to `moon test`.

## Validation Plan

- Parse the GitHub Actions workflow YAML.
- Run `git diff --check`.
- Use `moon test --outline` to confirm root tests no longer include desktop or
  Lepus packages.
- Push and confirm the GitHub Actions checks on PR #167.
