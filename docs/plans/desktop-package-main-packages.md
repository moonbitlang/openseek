# Desktop Package Main Packages

## Goal

Move the three desktop packaging scripts out of standalone `.mbtx` files and
into regular MoonBit main packages, while extracting the common build and file
operation logic shared by the Windows, macOS, and Linux packaging flows.

## Accepted Design

- Replace the standalone `desktop/package_linux.mbtx`,
  `desktop/package_macos.mbtx`, and `desktop/package_windows.mbtx` entry points
  with three `is-main` packages under `desktop/cmd/package_linux`,
  `desktop/cmd/package_macos`, and `desktop/cmd/package_windows`.
- Add `desktop/internal/packaging` as the shared helper package for workspace
  discovery, command execution, frontend/native/engine build steps, Lepus
  codegen staging, and simple file/directory operations.
- Keep platform-specific packaging behavior in each platform main package:
  AppImage metadata and appimagetool on Linux, signing/notarization on macOS,
  and WebView2/WSL/MoonBit toolchain/NSIS handling on Windows.
- Preserve current distribution behavior. In particular, only the Windows
  package stages the bundled MoonBit toolchain; Linux and macOS continue to
  package only the host, engine, and frontend assets.
- Keep the runtime bundled-toolchain lookup unchanged in this refactor.

## Target Files And Surfaces

- `desktop/internal/packaging/`: new internal shared package.
- `desktop/cmd/package_linux/`: new Linux packaging main package.
- `desktop/cmd/package_macos/`: new macOS packaging main package.
- `desktop/cmd/package_windows/`: new Windows packaging main package.
- `desktop/package_linux.mbtx`, `desktop/package_macos.mbtx`,
  `desktop/package_windows.mbtx`: removed or replaced by the new main package
  entry points.
- `.github/workflows/ci.yml`: update packaging commands to `moon run` the new
  main packages.
- `desktop/README.md`: update user-facing packaging commands.

## API And Interface Diff

- New internal package API:
  `openseek_desktop/internal/packaging`.
- New executable package entry points:
  `openseek_desktop/cmd/package_linux`,
  `openseek_desktop/cmd/package_macos`, and
  `openseek_desktop/cmd/package_windows`.
- Existing desktop host/runtime APIs should remain unchanged.
- Generated interfaces should only grow for the new internal packaging package
  and new main packages; existing package interfaces should not expose new
  public runtime behavior.

## Open Questions

- None for the structural refactor. Cross-platform bundled MoonBit toolchain
  support is intentionally out of scope for this change.

## Next Implementation Step

Create `desktop/internal/packaging`, move shared helpers into it, then add the
three platform-specific main package directories and update references from the
old `.mbtx` entry points.

## Validation Plan

- Run `moon -C desktop check --target native`.
- Run `moon -C desktop test`.
- Run `moon -C desktop info && moon -C desktop fmt`.
- Review generated `.mbti` diffs and confirm existing runtime interfaces did
  not change unexpectedly.
- Do not run full packaging commands unless explicitly requested, because they
  may download external artifacts and require platform-specific tools.
