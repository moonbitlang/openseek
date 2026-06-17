///|
const AppDirPath : String = "dist/OpenSeek-Desktop.AppDir"

///|
const AppImagePath : String = "dist/OpenSeek-Desktop-linux-x86_64.AppImage"

///|
const UsrBinPath : String = AppDirPath + "/usr/bin"

///|
const AppAssetDir : String = UsrBinPath + "/assets"

///|
/// Where a downloaded appimagetool is cached between runs. Lives outside the
/// AppDir so reset_bundle_dirs never deletes it.
const AppImageToolCache : String = "dist/tools/appimagetool"

///|
const AppImageToolUrl : String = "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"

///|
async fn build_outputs(ws : @packaging.Workspace) -> Unit {
  @packaging.ensure_codegen_tool(ws, @packaging.posix_codegen_tool())
  @packaging.build_frontend_bundle(ws)
  @packaging.build_native_host(ws)
  @packaging.build_engine(ws)
}

///|
async fn reset_bundle_dirs(ws : @packaging.Workspace) -> Unit {
  @packaging.remove_path_if_exists(ws.at(AppDirPath))
  @packaging.remove_path_if_exists(ws.at(AppImagePath))
  @packaging.ensure_dir(ws.at(UsrBinPath))
  @packaging.ensure_dir(ws.at(AppAssetDir))
  @packaging.ensure_dir(ws.at("dist/tools"))
}

///|
async fn copy_bundle_files(ws : @packaging.Workspace) -> Unit {
  if !@asyncfs.exists(ws.at(@packaging.native_binary())) {
    raise @packaging.PackageError(
      "native binary not found: \{ws.at(@packaging.native_binary())}",
    )
  }
  if !@asyncfs.exists(ws.repo_at(@packaging.engine_binary())) {
    raise @packaging.PackageError(
      "openseek engine binary not found: \{ws.repo_at(@packaging.engine_binary())}",
    )
  }
  @packaging.copy_file(
    ws.at(@packaging.native_binary()),
    ws.at(UsrBinPath + "/openseek-desktop-bin"),
  )
  @packaging.copy_file(
    ws.repo_at(@packaging.engine_binary()),
    ws.at(UsrBinPath + "/openseek"),
  )
  @packaging.copy_file(ws.at("index.html"), ws.at(AppAssetDir + "/index.html"))
  @packaging.copy_file(
    ws.at("frontend.js"),
    ws.at(AppAssetDir + "/frontend.js"),
  )
  let target = @packaging.moonbit_linux_x64_toolchain()
  @packaging.stage_moonbit_toolchain_seed(
    ws,
    target,
    UsrBinPath + "/" + target.seed_relative_dir(),
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
    #|export PATH="$APP_DIR/usr/bin:$PATH"
    #|exec "$APP_DIR/usr/bin/openseek-desktop-bin" "$@"
    #|
  source
}

///|
fn desktop_entry_source() -> String {
  let source =
    #|[Desktop Entry]
    #|Type=Application
    #|Name=OpenSeek Desktop
    #|Exec=openseek-desktop-bin
    #|Icon=openseek-desktop
    #|Categories=Development;
    #|Terminal=false
    #|
  source
}

///|
fn icon_source() -> String {
  let source =
    #|<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
    #|  <rect width="256" height="256" rx="48" fill="#1a1b26"/>
    #|  <circle cx="128" cy="128" r="64" fill="none" stroke="#7aa2f7" stroke-width="16"/>
    #|  <circle cx="128" cy="128" r="20" fill="#7aa2f7"/>
    #|</svg>
    #|
  source
}

///|
async fn write_bundle_metadata(ws : @packaging.Workspace) -> Unit {
  @packaging.write_text(ws.at(AppDirPath + "/AppRun"), apprun_source())
  @packaging.write_text(
    ws.at(AppDirPath + "/openseek-desktop.desktop"),
    desktop_entry_source(),
  )
  @packaging.write_text(
    ws.at(AppDirPath + "/openseek-desktop.svg"),
    icon_source(),
  )
  // appimagetool uses .DirIcon as the AppImage's embedded icon.
  @packaging.run_checked(
    "ln",
    ["-sf", "openseek-desktop.svg", AppDirPath + "/.DirIcon"],
    dir=ws.dir(),
  )
  @packaging.run_checked(
    "chmod",
    [
      "+x",
      AppDirPath + "/AppRun",
      UsrBinPath + "/openseek-desktop-bin",
      UsrBinPath + "/openseek",
    ],
    dir=ws.dir(),
  )
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
  let ws = @packaging.locate_workspace()
  build_outputs(ws)
  println("built openseek engine: \{ws.repo_at(@packaging.engine_binary())}")
  reset_bundle_dirs(ws)
  copy_bundle_files(ws)
  write_bundle_metadata(ws)
  let tool = ensure_appimagetool(ws)
  build_appimage(ws, tool)
  println("generated \{ws.at(AppImagePath)}")
}
