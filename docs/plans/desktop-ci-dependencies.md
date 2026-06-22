# Desktop CI Dependencies

## Goal

Fix the remaining CI failures on PR #167 after the desktop submodule and NSIS
setup fixes.

## Accepted Design

- In the root `check` job, install the Lepus codegen CLI after `desktop/lepus`
  is checked out and before root `moon` commands run.
- In `cmd/openseek`, keep executable-bit preservation for non-Windows targets
  and make the chmod step a no-op on Windows, where `moonbitlang/async/fs` does
  not expose `chmod`.

## Target Files And Surfaces

- `.github/workflows/ci.yml`
- `cmd/openseek/concurrent.mbt`

## API / Interface Diff

- No public MoonBit API changes are intended.
- Generated `.mbti` files should remain unchanged.

## Open Questions

- None.

## Next Implementation Step

Patch the workflow dependency setup and add a private target-conditional chmod
helper in `cmd/openseek`.

## Validation Plan

- Parse the GitHub Actions workflow YAML.
- Run `git diff --check`.
- Run focused MoonBit checks for the affected package where locally practical.
- Push and confirm the GitHub Actions checks on PR #167.
