# Desktop Package Argparse

## Goal

Replace hand-written package argument parsing in the desktop platform packagers
with `moonbitlang/core/argparse`, while keeping the platform package artifact
definitions intact and leaving Linux unchanged because it currently accepts no
package arguments.

## Accepted Design

- Import `moonbitlang/core/argparse` in `desktop/package/macos` and
  `desktop/package/windows`.
- For macOS, describe `--sign <identity>` and `--notarize <profile>` with an
  argparse `Command`, then convert parsed matches into the existing private
  signing config. Let argparse enforce value presence and the `--notarize`
  requires `--sign` relationship.
- For Windows, remove the package mode flags. The Windows packager should
  always build the app bundle, portable zip, and NSIS installer.
- Keep a zero-argument argparse `Command` for Windows so `-h`/`--help` and
  unknown argument handling use the standard CLI parser surface.
- Let argparse own `argv[0]` trimming, built-in `-h`/`--help`, unknown
  argument handling, missing-value errors where options exist, and contextual
  help rendering.
- Do not add argument parsing to the Linux packager in this refactor.

## Target Files And Surfaces

- `desktop/package/macos/main.mbt`
- `desktop/package/macos/moon.pkg`
- `desktop/package/windows/main.mbt`
- `desktop/package/windows/moon.pkg`
- Focused white-box tests in the macOS and Windows package directories.

## API And Interface Diff

- No public package API is intended to change. The platform package
  `pkg.generated.mbti` files should remain empty.
- macOS CLI behavior intentionally moves to the standard
  `moonbitlang/core/argparse` error and help text for parse failures and help
  requests.
- Windows CLI behavior intentionally removes `--zip`, `--installer`, `--all`,
  and their bare mode aliases. A no-argument run now always produces all
  Windows package outputs.

## Open Questions

- None. Existing external scripts depending on exact legacy error text or the
  old Windows mode flags are out of scope; the accepted Windows behavior is
  always building all outputs.

## Next Implementation Step

Replace the macOS hand-written parser helper with a package-local argparse
command builder and config conversion code, then remove the Windows package mode
state machine and parse a zero-argument command before building all outputs.

## Validation Plan

- Run `moon -C desktop test package/macos --target native`.
- Run `moon -C desktop test package/windows --target native`.
- Run `moon -C desktop check package/linux package/macos package/windows --target native`.
- Run `moon -C desktop info package/macos package/windows --target native`.
- Run `moon -C desktop fmt package/macos package/windows`.
- Review `.mbti` diffs and confirm no public API surface was added.
