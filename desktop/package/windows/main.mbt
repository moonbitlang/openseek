///|
const WslEngineBinary : String = "_build/wsl_engine/native/release/build/bobzhang/openseek/cmd/openseek/openseek.exe"

///|
/// Bundle name of the Linux engine. The desktop host looks for this file
/// beside `openseek.exe` when a WSL-mode run does not name an engine.
const BundledWslEngineName : String = "openseek-linux"

///|
const BundleDir : String = "dist/windows-x64/OpenSeek Desktop"

///|
const ZipPath : String = "dist/OpenSeek Desktop-windows-x64.zip"

///|
const InstallerScript : String = "installer/openseek-desktop.nsi"

///|
const InstallerPath : String = "dist/OpenSeek-Desktop-Setup.exe"

///|
const LocalMakensis : String = "dist/tools/nsis-3.12/makensis.exe"

///|
const ProgramFilesX86Makensis : String = "C:/Program Files (x86)/NSIS/makensis.exe"

///|
const ProgramFilesMakensis : String = "C:/Program Files/NSIS/makensis.exe"

///|
const AppAssetDir : String = BundleDir + "/assets"

///|
fn package_command() -> @argparse.Command {
  Command(
    "package/windows",
    about="Build the Windows app bundle, portable zip, and NSIS installer.",
  )
}

///|
async fn run_powershell(ws : @packaging.Workspace, script : String) -> Unit {
  @packaging.run_checked(
    "powershell",
    [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-Command",
      "$ErrorActionPreference = 'Stop'; " + script,
    ],
    dir=ws.dir(),
  )
}

///|
/// The script run inside WSL's `sh`: moon installs to `~/.moon/bin`, which a
/// non-login shell does not have on PATH, and a command launched from the
/// `desktop` directory must climb to the repo root first.
fn wsl_moon_script(ws : @packaging.Workspace, command : String) -> String {
  let prefix = if ws.invoked_from_repo_root() { "" } else { "cd .. && " }
  "PATH=\"$HOME/.moon/bin:$PATH\"; " + prefix + command
}

///|
/// Build the Linux engine inside WSL so WSL-mode runs work out of the box.
/// Best-effort: a packaging machine without WSL, moon, or a C toolchain inside
/// it skips the binary with a loud notice instead of failing the package.
async fn build_wsl_engine(ws : @packaging.Workspace) -> Bool {
  let probe = @process.run(
    "wsl.exe",
    ["-e", "sh", "-lc", wsl_moon_script(ws, "command -v moon")],
    inherit_env=true,
  ) catch {
    _ => 1
  }
  if probe != 0 {
    println(
      "note: WSL with moon is not available; skipping the bundled Linux engine",
    )
    return false
  }
  let build = wsl_moon_script(
    ws,
    "moon build \{@packaging.engine_package()} --target native --release --target-dir _build/wsl_engine",
  )
  println("$ wsl.exe -e sh -lc '\{build}'")
  let code = @process.run(
    "wsl.exe",
    ["-e", "sh", "-lc", build],
    inherit_env=true,
  ) catch {
    _ => 1
  }
  if code != 0 || !@asyncfs.exists(ws.repo_at(WslEngineBinary)) {
    println(
      "warning: the WSL Linux engine build failed; the bundle will not include \{BundledWslEngineName}.",
    )
    println(
      "         Install a C toolchain inside WSL (e.g. sudo apt-get install -y gcc) to bundle it.",
    )
    return false
  }
  true
}

///|
/// Build everything the bundle needs; returns whether the optional WSL Linux
/// engine was built and should be staged. CEF replaces WebView2, so no
/// WebView2 SDK headers are fetched.
async fn build_outputs(ws : @packaging.Workspace) -> Bool {
  // Assemble the CEF runtime first so the native host links against it.
  let _ = @packaging.assemble_cef_runtime(ws, @packaging.windows_proton_cli())
  @packaging.build_frontend_bundle(ws)
  @packaging.build_native_host(ws, extra_args=["--warn-list", "-20"])
  @packaging.build_engine(ws)
  build_wsl_engine(ws)
}

///|
async fn reset_bundle_dirs(ws : @packaging.Workspace) -> Unit {
  @packaging.remove_path_if_exists(ws.at(BundleDir))
  @packaging.remove_path_if_exists(ws.at(ZipPath))
  @packaging.remove_path_if_exists(ws.at(InstallerPath))
  @packaging.ensure_dir(ws.at(AppAssetDir))
}

///|
async fn copy_bundle_files(
  ws : @packaging.Workspace,
  with_wsl_engine~ : Bool,
) -> Unit {
  let native_binary = ws.native_binary()
  let engine_binary = ws.engine_binary()
  let bundled_engine = BundleDir + "/openseek.exe"
  if !@asyncfs.exists(native_binary) {
    raise @packaging.PackageError("native binary not found: \{native_binary}")
  }
  if !@asyncfs.exists(engine_binary) {
    raise @packaging.PackageError(
      "openseek engine binary not found: \{engine_binary}",
    )
  }
  if !@asyncfs.exists(ws.at("frontend.js")) {
    raise @packaging.PackageError(
      "frontend bundle not found: \{ws.at("frontend.js")}",
    )
  }
  @packaging.copy_file(
    native_binary,
    ws.at(BundleDir + "/openseek-desktop.exe"),
  )
  @packaging.copy_file(engine_binary, ws.at(bundled_engine))
  @pe.set_windows_gui_subsystem(ws.at(bundled_engine))
  // Only a binary built this run is staged; a stale leftover from an earlier
  // packaging would silently ship outdated engine code.
  if with_wsl_engine {
    @packaging.copy_file(
      ws.repo_at(WslEngineBinary),
      ws.at(BundleDir + "/" + BundledWslEngineName),
    )
  }
  @packaging.copy_file(ws.at("index.html"), ws.at(AppAssetDir + "/index.html"))
  @packaging.copy_file(
    ws.at("frontend.js"),
    ws.at(AppAssetDir + "/frontend.js"),
  )
  let target = @moonbit.moonbit_windows_x64_toolchain()
  @moonbit.stage_moonbit_toolchain_seed(
    ws,
    target,
    BundleDir + "/" + target.seed_relative_dir(),
  )
  // Best-effort: ship the assembled CEF runtime (proton.dll, libcef.dll,
  // cef_process.exe, resources). The Windows DLL search expects these beside
  // the executable; the exact layout needs validation on Windows.
  @packaging.copy_tree(
    @packaging.proton_runtime_dist(ws),
    ws.at(BundleDir + "/proton"),
  )
}

///|
async fn zip_bundle(ws : @packaging.Workspace) -> Unit {
  run_powershell(
    ws,
    "Compress-Archive -LiteralPath '\{BundleDir}' -DestinationPath '\{ZipPath}' -Force",
  )
}

///|
async fn ensure_makensis(ws : @packaging.Workspace) -> Unit {
  if @asyncfs.exists(ws.at(LocalMakensis)) {
    return
  }
  if @asyncfs.exists(ProgramFilesX86Makensis) {
    return
  }
  if @asyncfs.exists(ProgramFilesMakensis) {
    return
  }
  let code = @process.run("makensis.exe", ["/VERSION"], inherit_env=true) catch {
    _ => 1
  }
  if code != 0 {
    let message = "makensis.exe not found. Install NSIS on PATH or extract portable NSIS to \{ws.at(LocalMakensis)}."
    println(message)
    raise @packaging.PackageError(message)
  }
}

///|
fn makensis_command(ws : @packaging.Workspace) -> String {
  if @fs.path_exists(ws.at(LocalMakensis)) {
    LocalMakensis
  } else if @fs.path_exists(ProgramFilesX86Makensis) {
    ProgramFilesX86Makensis
  } else if @fs.path_exists(ProgramFilesMakensis) {
    ProgramFilesMakensis
  } else {
    "makensis.exe"
  }
}

///|
async fn build_installer(ws : @packaging.Workspace) -> Unit {
  if !@asyncfs.exists(ws.at(BundleDir + "/openseek-desktop.exe")) {
    raise @packaging.PackageError(
      "Windows app bundle not found: \{ws.at(BundleDir)}",
    )
  }
  // `ws.at(...)` is already absolute, so makensis receives unambiguous paths
  // regardless of the cwd it runs in.
  @packaging.run_checked(
    makensis_command(ws),
    [
      "/DSOURCE_DIR=\{ws.at(BundleDir)}",
      "/DOUTPUT_DIR=\{ws.at("dist")}",
      ws.at(InstallerScript),
    ],
    dir=ws.dir(),
  )
}

///|
async fn main {
  ignore(package_command().parse())
  let ws = @packaging.locate_workspace()
  ensure_makensis(ws)
  let with_wsl_engine = build_outputs(ws)
  println("built openseek engine: \{ws.engine_binary()}")
  if with_wsl_engine {
    println("built WSL Linux engine: \{ws.repo_at(WslEngineBinary)}")
  }
  reset_bundle_dirs(ws)
  copy_bundle_files(ws, with_wsl_engine~)
  zip_bundle(ws)
  println("generated \{ws.at(ZipPath)}")
  build_installer(ws)
  println("generated \{ws.at(InstallerPath)}")
  println("generated \{ws.at(BundleDir)}")
}
