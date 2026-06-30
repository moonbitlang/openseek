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

## Follow-up: Dedicated Desktop Package Tree

### Goal

Move desktop packaging code out of the desktop app/runtime package tree and
into a dedicated `desktop/package` package subtree, while extracting Windows PE
header patching into its own internal helper package.

### Accepted Design

- Keep everything inside the existing `openseek_desktop` MoonBit module; do not
  add a nested `desktop/package/moon.mod`.
- Move shared packaging helpers from `desktop/internal/packaging` to
  `desktop/package/internal/packaging`.
- Move MoonBit toolchain staging helpers from the shared packaging package to
  `desktop/package/internal/moonbit`.
- Add `desktop/package/internal/pe` for PE header constants and Windows GUI
  subsystem patching.
- Move platform main packages from `desktop/cmd/package_linux`,
  `desktop/cmd/package_macos`, and `desktop/cmd/package_windows` to
  `desktop/package/linux`, `desktop/package/macos`, and
  `desktop/package/windows`.
- Update README and CI commands to run `package/linux`, `package/macos`, and
  `package/windows`.

### Target Files And Surfaces

- `desktop/package/internal/packaging`: workspace discovery, package-time
  command execution, frontend/native/engine build helpers, and common file
  operations.
- `desktop/package/internal/moonbit`: package-time MoonBit toolchain target
  descriptors, archive download/extraction, validation, and seed staging.
- `desktop/package/internal/pe`: Windows PE subsystem patching.
- `desktop/package/linux`, `desktop/package/macos`, and
  `desktop/package/windows`: platform-specific `is-main` packaging entry
  points.
- `.github/workflows/ci.yml` and `desktop/README.md`: packaging command paths.

### API And Interface Diff

- Remove internal package APIs at `openseek_desktop/internal/packaging`.
- Add internal package APIs at:
  - `openseek_desktop/package/internal/packaging`
  - `openseek_desktop/package/internal/moonbit`
  - `openseek_desktop/package/internal/pe`
- Replace executable package paths:
  - `openseek_desktop/cmd/package_linux` ->
    `openseek_desktop/package/linux`
  - `openseek_desktop/cmd/package_macos` ->
    `openseek_desktop/package/macos`
  - `openseek_desktop/cmd/package_windows` ->
    `openseek_desktop/package/windows`
- Existing desktop app/runtime APIs remain unchanged.

### Open Questions

- None. The PE helper should expose only the cohesive operation needed by the
  Windows packager; PE offsets and binary-format constants should stay private.

### Next Implementation Step

Move packages into the new tree, extract `package/internal/moonbit` and
`package/internal/pe`, update package imports and command references, then
validate generated interfaces.

### Validation Plan

- Run `moon -C desktop check --target native`.
- Run `moon -C desktop info`.
- Run `moon -C desktop fmt`.
- Run `git diff --check`.
- Review `.mbti` diffs for expected package path changes and no desktop
  runtime API changes.
- Do not run full packaging commands unless explicitly requested, because they
  download external artifacts and require platform-specific tools.

## Follow-up: macOS CEF Helper Bundle

### Goal

Make the macOS `libcef` bundle launch CEF subprocesses from a canonical nested
helper app and keep Proton's native binaries compatible with the package's
declared minimum macOS version.

### Accepted Design

- Keep the full Proton runtime under `Contents/Resources/proton`, preserving its
  existing internal framework/resource layout and the host rpath pointing at
  `Resources/proton/lib`.
- Add a nested helper app at
  `Contents/Frameworks/OpenSeek Desktop Helper.app` containing a copy of
  `cef_process` at `Contents/MacOS/cef_process`.
- Give the helper app its own `Info.plist`, with bundle identifier derived from
  the main bundle id as
  `community.moonbit.proton.openseek-desktop.helper`.
- Repoint the helper executable's rpath to
  `@loader_path/../../../../Resources/proton/lib`, so its `@rpath/libproton.dylib`
  resolves to the bundled runtime.
- Sign the helper executable inside-out before the main app. For ad-hoc builds,
  keep the CEF helper signing identifier as `cef_process`; for distribution
  builds, use the same identifier plus hardened runtime and timestamp.
- Pass `MACOSX_DEPLOYMENT_TARGET=12.0` to Proton runtime assembly as well as to
  the host and engine builds, so Proton artifacts built during setup inherit the
  package's deployment target.

### Target Files And Surfaces

- `desktop/package/macos/main.mbt`: package-time helper app layout, Info.plist,
  rpath patching, and signing orchestration.
- `desktop/package/macos/main_wbtest.mbt`: focused tests for derived helper
  paths/metadata if the implementation introduces testable pure helpers.
- No desktop runtime or Proton public API changes are expected.

### API And Interface Diff

- `openseek_desktop/package/macos` should not expose new public APIs in
  `pkg.generated.mbti`; new helpers should remain private to the package.
- Runtime-facing interfaces in `desktop/proton` and desktop host packages should
  remain unchanged.

### Open Questions

- Chromium 147's peer requirement validation is intentionally out of scope for
  this step. If ad-hoc builds still show a blank page after the helper app is
  present, resolve that separately through real Developer ID signing or a
  browser-side CEF command-line feature override in `libproton`.
- The current vendored/prebuilt `libproton.dylib` and `cef_process` still carry
  `LC_BUILD_VERSION` `minos 26.0` even when `MACOSX_DEPLOYMENT_TARGET=12.0` is
  forwarded into `cef setup`. Supporting macOS versions below 26 requires a
  rebuilt or replaced Proton runtime, or a separate approved Mach-O rewriting
  and signing plan.

### Next Implementation Step

Update the macOS packager to stage and sign the helper app, propagate the
deployment target into Proton runtime assembly, then validate the generated
bundle structure and Mach-O metadata.

### Validation Plan

- Run `moon -C desktop check --target native`.
- Run `moon -C desktop test package/macos`.
- Run `moon -C desktop info && moon -C desktop fmt`.
- Build the macOS bundle with `moon -C desktop run --target native package/macos`.
- Inspect the generated bundle's `Contents/Frameworks` tree, helper executable
  rpath, `LC_BUILD_VERSION`, and code signature verification.

## Follow-up: Clean Build Host Binary Path

### Goal

Make the packaging helpers consume the native host binary path produced by a
clean current MoonBit release build.

### Accepted Design

- Keep the native host package as `.` and keep the existing package command
  flow unchanged.
- Update the shared packaging helper's native host artifact path from the stale
  flat output path to the clean-build nested output path:
  `_build/native/release/build/openseek_desktop/openseek_desktop.exe`.
- Do not change runtime APIs, package public APIs, or platform-specific bundle
  layouts.

### Target Files And Surfaces

- `desktop/package/internal/packaging/packaging.mbt`: native host artifact path
  constant only.

### API And Interface Diff

- No intended `.mbti` or public API changes.

### Open Questions

- None. `moon -C desktop clean` followed by the macOS package command showed
  the clean build emits only the nested native host binary path.

### Next Implementation Step

Update the native host artifact path, rebuild the macOS package, and launch the
app to verify CEF uses the nested helper executable.

### Validation Plan

- Run `moon -C desktop run --target native package/macos`.
- Run `moon -C desktop info`.
- Run `moon -C desktop fmt`.
- Inspect the generated app bundle and launch it.

## Follow-up: macOS CEF Renderer Startup

### Goal

Make the macOS `libcef` runtime start a live renderer process so packaged
OpenSeek can actually render `proton://app/` and execute page JavaScript.

### Accepted Design

- Fix the vendored Lepus mac CEF implementation rather than the OpenSeek
  facade: a minimal C smoke app running inside the same `.app` bundle still
  produced a DevTools page target with no renderer and CDP `Runtime.enable`
  timed out.
- Align the mac CEF bootstrap with current CEF M142 C API requirements where
  needed, including runtime library loading from the bundle and helper process
  startup.
- Fix C API handler ownership on mac by adding references before returning
  handler pointers to CEF, matching the official C API examples.
- Add focused native debug logging for page load and scheme-handler callbacks
  so renderer startup and `proton://` resource handling are observable.
- Keep the Proton C ABI and MoonBit-facing APIs unchanged.
- After Lepus renderer startup is fixed, keep the macOS packager aligned with
  the runtime requirements: CEF-style plist metadata, hardened runtime
  entitlements, and inside-out signing of CEF framework libraries and helpers.

### Target Files And Surfaces

- `vendor/lepus/native/src/engine/cef_mac/proton_engine_cef_mac.m`: mac CEF
  runtime initialization, handler ownership, and diagnostics.
- `vendor/lepus/native/src/cef_process.c`: mac helper process bootstrap if CEF
  runtime loading needs helper-side setup.
- `vendor/lepus/native/CMakeLists.txt`: mac native linking/build inputs if the
  CEF wrapper library loader is required.
- `desktop/package/macos/main.mbt`: package-time signing/plist/entitlement
  follow-up after renderer startup is verified in Lepus.

### API And Interface Diff

- No intended changes to Proton's exported C ABI.
- No intended changes to desktop host/runtime MoonBit APIs or generated
  package interfaces.
- mac native build internals may gain private helper functions and CMake build
  inputs only.

### Open Questions

- Whether direct-linking the CEF framework is sufficient once handler ownership
  is fixed, or whether M142 requires the CEF wrapper library loader in both
  main and helper processes for this embedding shape.
- Whether browser creation must be deferred until CEF's browser process is
  fully initialized, instead of immediately after `cef_initialize`.

### Next Implementation Step

Patch Lepus mac native code with handler ownership fixes and instrumentation,
then iterate on mac CEF bootstrap/linking until a minimal bundle smoke can
evaluate JavaScript through CDP and shows a stable renderer process.

### Validation Plan

- Rebuild the Lepus/native mac runtime through the existing `cef setup` path.
- Rebuild the macOS package.
- Launch the generated `.app` directly, inspect stable CEF subprocesses, and
  verify CDP `Runtime.evaluate` returns page DOM/JS state for `proton://app/`.
- Run `moon -C desktop test proton/native --target native`.
- Run `moon -C desktop info && moon -C desktop fmt`.

## Follow-up: macOS CEF Helper Executable Names

### Goal

Make the macOS packaged app launch CEF renderer subprocesses by matching
Chromium's helper bundle naming convention.

### Accepted Design

- Keep the full Proton runtime under `Contents/Resources/proton`.
- Generate the CEF macOS helper app family under `Contents/Frameworks`:
  - `OpenSeek Desktop Helper.app`
  - `OpenSeek Desktop Helper (Alerts).app`
  - `OpenSeek Desktop Helper (GPU).app`
  - `OpenSeek Desktop Helper (Plugin).app`
  - `OpenSeek Desktop Helper (Renderer).app`
- Copy the same built `cef_process` Mach-O into each helper app, but name the
  destination executable after the helper app bundle, e.g.
  `OpenSeek Desktop Helper (Renderer).app/Contents/MacOS/OpenSeek Desktop Helper (Renderer)`.
- Set each helper app's `CFBundleExecutable`, `CFBundleName`,
  `CFBundleDisplayName`, and bundle identifier to match the helper variant.
- Patch every helper executable's rpath to
  `@loader_path/../../../../Resources/proton/lib`.
- Keep the runtime-facing helper path pointed at the base helper executable:
  `Contents/Frameworks/OpenSeek Desktop Helper.app/Contents/MacOS/OpenSeek Desktop Helper`.
- Prefer the base helper in macOS helper discovery so adding helper variants
  cannot accidentally pass the renderer, GPU, plugin, or alerts helper as
  `browser_subprocess_path`.

### Target Files And Surfaces

- `desktop/package/macos/main.mbt`: helper bundle generation, metadata, rpath
  patching, and signing traversal.
- `desktop/package/macos/main_wbtest.mbt`: helper metadata/unit coverage.
- `desktop/proton/facade_macos_layout.mbt`: package-runtime helper discovery,
  limited to preferring the base helper executable when multiple helpers exist.

### API And Interface Diff

- No public MoonBit API changes are intended.
- Generated `.mbti` files should not expose new package APIs.

### Open Questions

- Developer ID distribution signing still needs end-to-end validation with a
  real signing identity and notarization profile.

### Next Implementation Step

Update the macOS packager and helper discovery, then rebuild the bundle and
verify a packaged app produces `Helper (Renderer)` subprocesses and can execute
JavaScript through CDP.

### Validation Plan

- Run `moon -C desktop test package/macos --target native`.
- Run `moon -C desktop test lepus/proton --target native`.
- Run `moon -C desktop info && moon -C desktop fmt`.
- Run `moon -C desktop run --target native package/macos`.
- Inspect helper bundle names, `CFBundleExecutable`, rpaths, and signatures.
- Launch the generated app and verify CDP `Runtime.evaluate` on `proton://app/`.

## Follow-up: macOS Menu And Quit Handling

### Goal

Install the macOS application menu at a CEF-safe point and make Quit close the
CEF browser through the same path as the window close button, so the MoonBit
runtime loop can observe `window_closed` and destroy the runtime cleanly.

### Accepted Design

- Keep only one Proton/Lepus implementation in this workspace:
  `desktop/lepus` becomes the Lepus submodule and `vendor/lepus` plus the
  tracked `desktop/proton` copy are removed.
- Move the existing OpenSeek-specific Proton facade/prebuilt changes into the
  `desktop/lepus` submodule branch
  `haoxiang/openseek-desktop-proton`, then push that branch to the submodule
  remote.
- Update `desktop/moon.work` to use `./lepus/proton`, preserving the
  `justjavac/proton` module identity without duplicating source.
- Do not install the menu from OpenSeek `desktop/main.mbt` before Proton creates
  its AppKit application object.
- In the Lepus mac runtime, install the default macOS app menu after
  `[ProtonApplication sharedApplication]`, `setActivationPolicy`, and
  `finishLaunching`, while no window has been shown and no event pump has
  started.
- In the Lepus mac runtime, override `terminate:` on `ProtonApplication` so
  app-menu Quit/Cmd+Q requests close all live CEF windows instead of letting
  AppKit hard-terminate the process.
- Keep Quit on the existing close lifecycle: CEF `close_browser`, then
  `on_before_close`, then `window_closed`, then MoonBit runtime teardown.

### Target Files And Surfaces

- `.gitmodules`: remove `vendor/lepus` and add `desktop/lepus`.
- `desktop/moon.work`: replace `./proton` with `./lepus/proton`.
- `desktop/lepus` submodule: branch
  `haoxiang/openseek-desktop-proton`, containing Proton facade/prebuilt changes
  and Lepus native mac menu/quit handling.
- Main repository index: remove tracked Proton source files and record only the
  `desktop/lepus` submodule pointer.

### API And Interface Diff

- No intended public MoonBit API changes.
- No intended Proton C ABI changes.
- Main repository dependency graph changes from vendored files to a submodule
  pointer at `desktop/lepus` plus the `./lepus/proton` workspace member.

### Open Questions

- None for this migration. Future generic Proton app-lifecycle customization is
  intentionally out of scope.

### Next Implementation Step

Convert `desktop/lepus` to the Lepus submodule on
`haoxiang/openseek-desktop-proton`, patch Lepus native mac menu/quit handling
inside that submodule, rebuild/sync mac prebuilt artifacts, then rebuild and
launch the package to verify menu Quit and Cmd+Q exit through `window_closed`.

### Validation Plan

- Run `moon -C desktop check --target native`.
- Run `moon -C desktop test lepus/proton --target native`.
- Run `moon -C desktop info && moon -C desktop fmt`.
- Rebuild Lepus darwin-arm64 prebuilt artifacts inside the `desktop/lepus`
  submodule.
- Run `moon -C desktop run --target native package/macos`.
- Launch the generated app, verify `Cmd+Q`/Quit exits the process, and confirm
  no stale OpenSeek processes remain.

## Follow-up: Proton HTML Asset Resource Handler

### Goal

Load bundled desktop HTML from the secure `proton://app/` origin while allowing
the same origin to serve sibling static assets such as `viewer.css`, without
falling back to blocked `file://` subresources or compile-time HTML rewriting.

### Accepted Design

- Add an optional HTML asset directory to the Proton facade app configuration.
- Keep `Window::load_html(html, base_url)` working as-is for existing callers.
- Add `Window::load_html_with_assets(html, base_url, asset_dir)` for callers
  that want the `proton://app/` scheme handler to serve both the main HTML
  document and files under a safe asset root.
- Extend the native C ABI with
  `proton_window_load_html_with_assets(window, html, base_url, asset_root)`;
  keep `proton_window_load_html(...)` as a compatibility wrapper.
- Update macOS, Linux, and Windows CEF scheme handlers so the exact base URL
  returns the supplied HTML and same-origin asset URLs resolve under the
  configured asset root, rejecting traversal and paths outside that root.
- Keep OpenSeek's current `frontend.js` inlining for the first fix and use the
  resource handler to serve `viewer.css`. Removing the JS inliner can be a
  separate cleanup once the handler path is validated.

### Target Files And Surfaces

- `desktop/lepus/proton/facade_types.mbt`: store the optional HTML asset dir.
- `desktop/lepus/proton/facade_builders.mbt`: add
  `pub fn App::asset_dir(self : App, path : String) -> App`.
- `desktop/lepus/proton/facade_runtime.mbt` and
  `desktop/lepus/proton/facade_entry.mbt`: pass the asset dir into HTML loading.
- `desktop/lepus/proton/native/native.mbt`,
  `desktop/lepus/proton/native/ffi.mbt`, and generated `.mbti` files: expose the
  native wrapper while preserving the old method.
- `desktop/lepus/native/src/proton.c` and native headers/prebuilt artifacts:
  add the C ABI entry point.
- `desktop/lepus/native/src/engine/cef_mac/proton_engine_cef_mac.m`,
  `desktop/lepus/native/src/engine/cef_linux/proton_engine_cef_linux.c`, and
  `desktop/lepus/native/src/engine/cef_win/proton_engine_cef_win.c`: serve
  same-origin HTML assets through the `proton` scheme.
- `desktop/main.mbt` and/or `desktop/internal/extension/bundle.mbt`: configure
  OpenSeek's asset directory from the packaged `assets/index.html` location.

### API And Interface Diff

- Proton facade app API gains:
  `pub fn App::asset_dir(App, String) -> App`.
- Proton native MoonBit API gains:
  `pub fn Window::load_html_with_assets(Window, String, String, String) -> Result[Unit, NativeError]`.
- Proton C ABI gains:
  `PROTON_API int32_t proton_window_load_html_with_assets(proton_window_id_t window, const char *html, const char *base_url, const char *asset_root);`.
- Existing `App`, `Window::load_html`, and `proton_window_load_html` callers
  remain source-compatible.

### Open Questions

- None for the first implementation. Future cleanup can remove the
  `frontend.js` inliner after the resource handler has shipped.

### Next Implementation Step

Patch the Lepus submodule and OpenSeek asset-dir configuration, regenerate
MoonBit interfaces, rebuild native prebuilts, package macOS, and launch the app
to verify `proton://app/viewer.css` is served with CSS rules.

### Validation Plan

- Run `ctest --test-dir native/build-engine --output-on-failure` in
  `desktop/lepus`.
- Run `node native/scripts/verify_link_config.mjs native/dist` in
  `desktop/lepus`.
- Run `moon -C desktop check --target native`.
- Run `moon -C desktop test lepus/proton --target native`.
- Run `moon -C desktop info && moon -C desktop fmt`.
- Run `moon -C desktop run --target native package/macos`.
- Launch the generated app and verify through CDP that
  `proton://app/viewer.css` has nonzero `cssRules.length`,
  `window.__MoonBit__.openseek` exists, and Quit still exits cleanly.
