///|
const AppDirPath : String = "dist/SeekMoon.AppDir"

///|
const AppImagePath : String = "dist/SeekMoon-linux-x86_64.AppImage"

///|
const UsrBinPath : String = AppDirPath + "/usr/bin"

///|
const AppAssetDir : String = UsrBinPath + "/assets"

///|
const UsrResourcesPath : String = AppDirPath + "/usr/Resources"

///|
const ProtonRuntimePath : String = UsrResourcesPath + "/proton"

///|
const ProtonPackageManifestPath : String = UsrResourcesPath +
  "/proton-package.json"

///|
const RipgrepLicenseDir : String = AppDirPath + "/usr/share/licenses/ripgrep"

///|
/// Where a downloaded appimagetool is cached between runs. Lives outside the
/// AppDir so reset_bundle_dirs never deletes it.
const AppImageToolCache : String = "dist/tools/appimagetool"

///|
const AppImageToolUrl : String = "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"

///|
async fn build_outputs(
  ws : @packaging.Workspace,
  release~ : Bool,
) -> (@xterm_assets.Assets, @ripgrep_assets.Assets) {
  @packaging.ensure_cef_runtime(ws)
  @packaging.build_frontend_bundle(ws, release~)
  let terminal_assets = @xterm_assets.build(
    ws,
    @xterm_assets.linux_x64_target(),
  )
  let ripgrep_assets = @ripgrep_assets.build(
    ws,
    @ripgrep_assets.linux_x64_target(),
  )
  @packaging.build_native_host(ws, release~)
  @packaging.build_engine(ws, release~)
  (terminal_assets, ripgrep_assets)
}

///|
async fn reset_bundle_dirs(ws : @packaging.Workspace) -> Unit {
  @packaging.remove_path_if_exists(ws.at(AppDirPath))
  @packaging.remove_path_if_exists(ws.at(AppImagePath))
  @packaging.ensure_dir(ws.at(UsrBinPath))
  @packaging.ensure_dir(ws.at(AppAssetDir))
  @packaging.ensure_dir(ws.at(UsrResourcesPath))
  @packaging.ensure_dir(ws.at(RipgrepLicenseDir))
  @packaging.ensure_dir(ws.at("dist/tools"))
}

///|
async fn copy_bundle_files(
  ws : @packaging.Workspace,
  terminal_assets : @xterm_assets.Assets,
  ripgrep_assets : @ripgrep_assets.Assets,
  release~ : Bool,
) -> Unit {
  let native_binary = ws.native_binary(release~)
  let engine_binary = ws.engine_binary(release~)
  if !@asyncfs.exists(native_binary) {
    raise @packaging.PackageError("native binary not found: \{native_binary}")
  }
  if !@asyncfs.exists(engine_binary) {
    raise @packaging.PackageError(
      "openseek engine binary not found: \{engine_binary}",
    )
  }
  @packaging.copy_file(
    native_binary,
    ws.at(UsrBinPath + "/openseek-desktop-bin"),
  )
  @packaging.copy_file(engine_binary, ws.at(UsrBinPath + "/openseek"))
  @packaging.copy_file(ripgrep_assets.binary, ws.at(UsrBinPath + "/rg"))
  @packaging.copy_file(
    ripgrep_assets.license_mit,
    ws.at(RipgrepLicenseDir + "/LICENSE-MIT"),
  )
  @packaging.copy_file(
    ripgrep_assets.unlicense,
    ws.at(RipgrepLicenseDir + "/UNLICENSE"),
  )
  @packaging.copy_file(ws.at("index.html"), ws.at(AppAssetDir + "/index.html"))
  @packaging.copy_file(ws.app_stylesheet(), ws.at(AppAssetDir + "/app.css"))
  @packaging.copy_file(
    ws.at("frontend.js"),
    ws.at(AppAssetDir + "/frontend.js"),
  )
  @packaging.copy_file(ws.at("viewer.css"), ws.at(AppAssetDir + "/viewer.css"))
  // The verified terminal emulator assets generated during this packaging run
  // are loaded by index.html before frontend.js.
  @packaging.copy_file(
    terminal_assets.javascript,
    ws.at(AppAssetDir + "/xterm.js"),
  )
  @packaging.copy_file(
    terminal_assets.stylesheet,
    ws.at(AppAssetDir + "/xterm.css"),
  )
  // The codicon font is served at the site root (`/codicon.ttf`), so it sits
  // next to `viewer.css` rather than under `fonts/`.
  @packaging.copy_file(
    ws.at("codicon.ttf"),
    ws.at(AppAssetDir + "/codicon.ttf"),
  )
  @packaging.copy_tree(ws.mermaid_assets(), ws.at(AppAssetDir + "/mermaid"))
  @packaging.copy_tree(ws.at("fonts"), ws.at(AppAssetDir + "/fonts"))
  ws.stage_viz_assets(ws.at(AppAssetDir + "/viz"), release~)
  let target = @moonbit.moonbit_linux_x64_toolchain()
  @moonbit.stage_moonbit_toolchain_seed(
    ws,
    target,
    UsrBinPath + "/" + target.seed_relative_dir(),
  )
  // Ship Proton's immutable runtime without changing its `bin` and `Resources`
  // layout. AppRun points both CEF and its subprocess helper at this copy.
  @packaging.copy_tree(
    @packaging.proton_runtime_root().0,
    ws.at(ProtonRuntimePath),
  )
  @packaging.copy_file(
    @packaging.proton_helper_path(),
    ws.at(UsrBinPath + "/cef_process"),
  )
}

///|
/// The AppRun launcher resolves its own absolute directory and execs the host
/// binary; every resource lookup in the host derives from the executable's
/// path, and the engine is found on PATH next to it. Mirrors the macOS
/// launcher: it deliberately does not `cd` into the AppDir, since the host
/// keeps its runtime state in absolute per-user paths.
fn apprun_source() -> String {
  let source =
    #|#!/bin/sh
    #|set -eu
    #|
    #|APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
    #|PROTON_ROOT="$APP_DIR/usr/Resources/proton"
    #|CEF_LIBRARY="$PROTON_ROOT/bin/libcef.so"
    #|export PATH="$APP_DIR/usr/bin:$PATH"
    #|export PROTON_RUNTIME_ROOT="$PROTON_ROOT"
    #|export PROTON_HELPER_PATH="$APP_DIR/usr/bin/cef_process"
    #|export LD_LIBRARY_PATH="$PROTON_ROOT/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    #|export LD_PRELOAD="$CEF_LIBRARY${LD_PRELOAD:+:$LD_PRELOAD}"
    #|exec "$APP_DIR/usr/bin/openseek-desktop-bin" "$@"
    #|
  source
}

///|
fn desktop_entry_source() -> String {
  let source =
    #|[Desktop Entry]
    #|Type=Application
    #|Name=SeekMoon
    #|Exec=openseek-desktop-bin
    #|Icon=openseek-desktop
    #|Categories=Development;
    #|Terminal=false
    #|
  source
}

///|
fn executable_bundle_paths() -> Array[String] {
  [
    AppDirPath + "/AppRun",
    UsrBinPath + "/openseek-desktop-bin",
    UsrBinPath + "/openseek",
    UsrBinPath + "/rg",
    UsrBinPath + "/cef_process",
  ]
}

///|
async fn write_bundle_metadata(ws : @packaging.Workspace) -> Unit {
  ws.write_proton_package_manifest(
    ProtonPackageManifestPath,
    "linux-appimage",
    ["appimage"],
  )
  @packaging.write_text(ws.at(AppDirPath + "/AppRun"), apprun_source())
  @packaging.write_text(
    ws.at(AppDirPath + "/openseek-desktop.desktop"),
    desktop_entry_source(),
  )
  // Checked-in icon: the design-system mark on the accent squircle (full-bleed
  // variant; the macOS package carries the margined one).
  @packaging.copy_file(
    ws.at("backend/package/linux/appicon.svg"),
    ws.at(AppDirPath + "/openseek-desktop.svg"),
  )
  // appimagetool uses .DirIcon as the AppImage's embedded icon.
  @packaging.run_checked(
    "ln",
    ["-sf", "openseek-desktop.svg", AppDirPath + "/.DirIcon"],
    dir=ws.dir(),
  )
  @packaging.run_checked(
    "chmod",
    ["+x", ..executable_bundle_paths()],
    dir=ws.dir(),
  )
}

///|
test "Linux AppRun follows the Proton 0.2 runtime layout" {
  let expected =
    #|#!/bin/sh
    #|set -eu
    #|
    #|APP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
    #|PROTON_ROOT="$APP_DIR/usr/Resources/proton"
    #|CEF_LIBRARY="$PROTON_ROOT/bin/libcef.so"
    #|export PATH="$APP_DIR/usr/bin:$PATH"
    #|export PROTON_RUNTIME_ROOT="$PROTON_ROOT"
    #|export PROTON_HELPER_PATH="$APP_DIR/usr/bin/cef_process"
    #|export LD_LIBRARY_PATH="$PROTON_ROOT/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    #|export LD_PRELOAD="$CEF_LIBRARY${LD_PRELOAD:+:$LD_PRELOAD}"
    #|exec "$APP_DIR/usr/bin/openseek-desktop-bin" "$@"
    #|
  assert_eq(apprun_source(), expected)
  assert_eq(executable_bundle_paths(), [
    "dist/SeekMoon.AppDir/AppRun", "dist/SeekMoon.AppDir/usr/bin/openseek-desktop-bin",
    "dist/SeekMoon.AppDir/usr/bin/openseek", "dist/SeekMoon.AppDir/usr/bin/rg", "dist/SeekMoon.AppDir/usr/bin/cef_process",
  ])
}

///|
/// Resolve an appimagetool to run: a previously downloaded copy, then one on
/// PATH, then a fresh download of the official release.
async fn ensure_appimagetool(ws : @packaging.Workspace) -> String {
  if @asyncfs.exists(ws.at(AppImageToolCache)) {
    return AppImageToolCache
  }
  let probe = @process.run(
    "sh",
    ["-c", "command -v appimagetool >/dev/null 2>&1"],
    inherit_env=true,
    cwd=ws.dir().view(),
  )
  if probe == 0 {
    return "appimagetool"
  }
  @packaging.run_checked(
    "curl",
    ["-fL", "-o", AppImageToolCache, AppImageToolUrl],
    dir=ws.dir(),
  )
  @packaging.run_checked("chmod", ["+x", AppImageToolCache], dir=ws.dir())
  AppImageToolCache
}

///|
/// APPIMAGE_EXTRACT_AND_RUN lets the appimagetool AppImage run without FUSE;
/// ARCH pins the output architecture because the vendored webview lib is
/// x64-only.
async fn build_appimage(ws : @packaging.Workspace, tool : String) -> Unit {
  @packaging.run_checked(
    "env",
    [
      "APPIMAGE_EXTRACT_AND_RUN=1",
      "ARCH=x86_64",
      tool,
      AppDirPath,
      AppImagePath,
    ],
    dir=ws.dir(),
  )
}

///|
async fn main {
  let matches = @argparse.Command(
    "backend/package/linux",
    about="Build the Linux AppImage.",
    flags=[
      FlagArg(
        "release",
        about="Build optimized release artifacts instead of debug artifacts.",
      ),
    ],
  ).parse()
  let release = matches.flags.get("release").unwrap_or(false)
  let ws = @packaging.locate_workspace()
  let (terminal_assets, ripgrep_assets) = build_outputs(ws, release~)
  println("built openseek engine: \{ws.engine_binary(release~)}")
  reset_bundle_dirs(ws)
  copy_bundle_files(ws, terminal_assets, ripgrep_assets, release~)
  write_bundle_metadata(ws)
  let tool = ensure_appimagetool(ws)
  build_appimage(ws, tool)
  println("generated \{ws.at(AppImagePath)}")
}
