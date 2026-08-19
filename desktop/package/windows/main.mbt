///|
const BundleDir : String = "dist/windows-x64/SeekMoon"

///|
const ZipPath : String = "dist/SeekMoon-windows-x64.zip"

///|
const InstallerScript : String = "installer/openseek-desktop.nsi"

///|
const InstallerPath : String = "dist/SeekMoon-Setup.exe"

///|
const LocalMakensis : String = "dist/tools/nsis-3.12/makensis.exe"

///|
const ProgramFilesX86Makensis : String = "C:/Program Files (x86)/NSIS/makensis.exe"

///|
const ProgramFilesMakensis : String = "C:/Program Files/NSIS/makensis.exe"

///|
const AppAssetDir : String = BundleDir + "/assets"

///|
priv struct ArtifactPlan {
  zip : Bool
  installer : Bool
} derive(Debug, Eq)

///|
fn ArtifactPlan::parse(values : ArrayView[String]) -> ArtifactPlan raise {
  if values.is_empty() {
    return { zip: true, installer: true }
  }
  let mut zip = false
  let mut installer = false
  for value in values {
    match value {
      "app" => ()
      "zip" => zip = true
      "installer" => installer = true
      value =>
        raise @packaging.PackageError(
          "unsupported Windows package target '\{value}'; expected app, zip, or installer",
        )
    }
  }
  { zip, installer }
}

///|
fn package_command() -> @argparse.Command {
  Command(
    "package/windows",
    about="Build the Windows app bundle, portable zip, and NSIS installer.",
    flags=[
      FlagArg(
        "release",
        about="Build optimized release artifacts instead of debug artifacts.",
      ),
    ],
    options=[
      OptionArg(
        "target",
        action=Append,
        about="Artifact to produce: app, zip, or installer. Repeatable; defaults to zip and installer.",
      ),
    ],
  )
}

///|
fn ArtifactPlan::from_matches(
  matches : @argparse.Matches,
) -> ArtifactPlan raise {
  match matches.values.get("target") {
    Some(values) => ArtifactPlan::parse(values)
    None => ArtifactPlan::parse([])
  }
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
/// Build everything the bundle needs. CEF replaces WebView2, so no WebView2
/// SDK headers are fetched.
async fn build_outputs(
  ws : @packaging.Workspace,
  release~ : Bool,
) -> @xterm_assets.Assets {
  @packaging.ensure_cef_runtime(ws)
  @packaging.build_frontend_bundle(ws, release~)
  let terminal_assets = @xterm_assets.build(
    ws,
    @xterm_assets.windows_x64_target(),
  )
  @packaging.build_native_host(ws, release~, extra_args=["--warn-list", "-20"])
  @packaging.build_engine(ws, release~)
  terminal_assets
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
  terminal_assets : @xterm_assets.Assets,
  release~ : Bool,
) -> Unit {
  let native_binary = ws.native_binary(release~)
  let engine_binary = ws.engine_binary(release~)
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
  let target = @moonbit.moonbit_windows_x64_toolchain()
  @moonbit.stage_moonbit_toolchain_seed(
    ws,
    target,
    BundleDir + "/" + target.seed_relative_dir(),
  )
  stage_proton_runtime(ws)
}

///|
/// Stage the CEF runtime the way the Windows loader needs it. proton.dll
/// (and libcef.dll, which it imports) must sit in the executable's own
/// directory: both are in the import table, and the DLL search never
/// descends into a subdirectory, so a nested layout fails before any
/// MoonBit code runs. proton.dll then derives every other path from its
/// own module directory — cef_process.exe beside itself, `Resources\`
/// (with `locales\`) under the same root — so flattening `bin\` into the
/// bundle root keeps those defaults working too.
async fn stage_proton_runtime(ws : @packaging.Workspace) -> Unit {
  let dist = @packaging.proton_runtime_dist(ws).0
  let bin = dist + "/bin"
  for entry in @asyncfs.readdir(bin, sort=true) {
    let source = "\{bin}/\{entry}"
    if @asyncfs.kind(source) is Directory {
      @packaging.copy_tree(source, ws.at(BundleDir + "/" + entry))
    } else {
      @packaging.copy_file(source, ws.at(BundleDir + "/" + entry))
    }
  }
  @packaging.copy_tree(dist + "/Resources", ws.at(BundleDir + "/Resources"))
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
  let app_version = ws.module_version()
  @packaging.run_checked(
    makensis_command(ws),
    [
      "/DAPP_VERSION=\{app_version}",
      "/DSOURCE_DIR=\{ws.at(BundleDir)}",
      "/DOUTPUT_DIR=\{ws.at("dist")}",
      ws.at(InstallerScript),
    ],
    dir=ws.dir(),
  )
}

///|
async fn main {
  // Parse first: a mistyped target must fail before the build, not after it.
  let matches = package_command().parse()
  let artifacts = ArtifactPlan::from_matches(matches)
  let release = matches.flags.get("release").unwrap_or(false)
  let ws = @packaging.locate_workspace()
  if artifacts.installer {
    ensure_makensis(ws)
  }
  let terminal_assets = build_outputs(ws, release~)
  println("built openseek engine: \{ws.engine_binary(release~)}")
  reset_bundle_dirs(ws)
  copy_bundle_files(ws, terminal_assets, release~)
  if artifacts.zip {
    zip_bundle(ws)
    println("generated \{ws.at(ZipPath)}")
  }
  if artifacts.installer {
    build_installer(ws)
    println("generated \{ws.at(InstallerPath)}")
  }
  println("generated \{ws.at(BundleDir)}")
}

///|
test "windows package args default to zip and installer" {
  let matches = package_command().parse(argv=[])
  let artifacts = ArtifactPlan::from_matches(matches)
  assert_eq(artifacts, { zip: true, installer: true })
  assert_false(matches.flags.get("release").unwrap_or(false))
}

///|
test "windows package args accept release" {
  let matches = package_command().parse(argv=["--release", "--target", "app"])
  let artifacts = ArtifactPlan::from_matches(matches)
  assert_eq(artifacts, { zip: false, installer: false })
  assert_true(matches.flags.get("release").unwrap_or(false))
}

///|
test "windows package target app skips distribution archives" {
  let matches = package_command().parse(argv=["--target", "app"])
  assert_eq(ArtifactPlan::from_matches(matches), {
    zip: false,
    installer: false,
  })
}

///|
test "windows package target zip skips installer" {
  let matches = package_command().parse(argv=["--target", "zip"])
  assert_eq(ArtifactPlan::from_matches(matches), { zip: true, installer: false })
}

///|
test "windows package target installer skips zip" {
  let matches = package_command().parse(argv=["--target", "installer"])
  assert_eq(ArtifactPlan::from_matches(matches), { zip: false, installer: true })
}

///|
test "windows package targets can be repeated" {
  let matches = package_command().parse(argv=[
    "--target", "app", "--target", "zip", "--target", "installer",
  ])
  assert_eq(ArtifactPlan::from_matches(matches), { zip: true, installer: true })
}

///|
test "windows package rejects an unsupported target" {
  let matches = package_command().parse(argv=["--target", "msi"])
  try ArtifactPlan::from_matches(matches) catch {
    err =>
      assert_true(
        err
        .to_string()
        .contains(
          "unsupported Windows package target 'msi'; expected app, zip, or installer",
        ),
      )
  } noraise {
    _ => fail("expected unsupported Windows package target to fail")
  }
}

///|
test "windows package args reject removed zip-only flag" {
  try package_command().parse(argv=["--zip-only"]) catch {
    err =>
      assert_true(
        err.to_string().contains("unexpected argument '--zip-only' found"),
      )
  } noraise {
    _ => fail("expected removed --zip-only flag to fail")
  }
}
