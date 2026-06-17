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
  support was intentionally out of scope for the first package split, and is
  now tracked in the follow-up checkpoint below.

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

## Follow-up: Cross-platform Bundled MoonBit Toolchain

### Goal

Distribute a bundled MoonBit toolchain on Windows, Linux, and macOS while
keeping signed/read-only application bundles immutable at runtime.

### Accepted Design

- Move the Windows-only MoonBit toolchain download and staging logic from
  `desktop/cmd/package_windows` into shared helpers in
  `desktop/internal/packaging`.
- Treat the packaged toolchain as a read-only seed. Package commands download
  and extract the platform-specific MoonBit binary archive plus matching core
  archive, but do not run `moon bundle` inside the packaged app directory.
- At runtime, copy the bundled seed into the per-user runtime directory and run
  `moon bundle --all` plus `moon bundle --target wasm-gc` only in that writable
  copy. The runtime then passes that writable directory as `MOON_HOME` to the
  engine.
- Keep platform differences in small descriptors: archive format, CDN target
  name, bundled seed relative path, executable suffix, and PATH separator.
- Preserve `OPENSEEK_DISABLE_BUNDLED_MOON` and `OPENSEEK_MOON_HOME` override
  behavior.

### Target Files And Surfaces

- `desktop/internal/packaging`: shared package-time toolchain descriptors,
  download, extraction, version validation, and staging helpers.
- `desktop/cmd/package_windows`, `desktop/cmd/package_linux`, and
  `desktop/cmd/package_macos`: call shared toolchain staging with their
  platform descriptor.
- `desktop/internal/appdirs`: bundled seed lookup, writable toolchain location,
  executable names, and PATH separator helpers.
- `desktop/internal/host`: initialize the writable copy from the bundled seed
  and run `moon bundle` there.
- `desktop/README.md`: document that all platform packages ship a MoonBit
  toolchain seed and initialize it under the per-user runtime directory.

### API And Interface Diff

- `openseek_desktop/internal/packaging` gains public internal-package helpers
  for MoonBit toolchain platform descriptors and staging.
- `openseek_desktop/internal/appdirs` gains internal-package helpers for
  bundled seed lookup and per-user writable toolchain paths.
- Existing external desktop host behavior remains unchanged except that Linux
  and macOS packages can now use the bundled MoonBit toolchain like Windows.

### Open Questions

- None for this implementation. The current macOS package remains arm64 and the
  current Linux package remains x86_64.

### Next Implementation Step

Add shared packaging helpers, update the three package commands, then switch
runtime initialization from bundle-in-place to seed-copy-then-initialize in the
per-user runtime directory.

### Validation Plan

- Run `moon -C desktop check --target native`.
- Run `moon -C desktop info`.
- Run `moon -C desktop fmt`.
- Review `.mbti` diffs for expected internal package API growth.
- Do not run full packaging commands unless explicitly requested, because they
  download large toolchain archives and require platform-specific tools.
