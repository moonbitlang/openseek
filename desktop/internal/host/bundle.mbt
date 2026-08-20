///|
const FrontendEntryPath = "assets/index.html"

///|
const ProtonPackageFrontendEntryPath = "target/proton-package-input/assets/index.html"

///|
const ProtonPackageRipgrepPath = "target/proton-package-input/bin/rg"

///|
/// Locate the bundled frontend entry relative to the executable. On macOS
/// the assets live in `Contents/Resources/` — `Contents/MacOS/` may only
/// hold code, since non-`--deep` codesigning rejects data files there — so
/// probe `../Resources/` first; the executable-adjacent layout serves the
/// Linux AppImage and the Windows bundle. If those installed layouts are
/// absent, a host under Moon's native `_build` layout derives the checked-in
/// development document from the same checkout.
pub async fn frontend_entry_path(framework_command : String) -> String {
  let command_dir = @pathx.Path(framework_command).dirname().resolve()
  let candidates = [
    command_dir
    .join("..")
    .join("Resources")
    .join(ProtonPackageFrontendEntryPath),
    command_dir.join("..").join("Resources").join(FrontendEntryPath),
    command_dir.join(FrontendEntryPath),
  ]
  for candidate in candidates {
    let path = candidate.normalize().to_string()
    if @fs.exists(path) {
      return path
    }
  }
  if @development.Layout::detect(framework_command) is Some(layout) {
    let path = layout.frontend_entry()
    guard @fs.exists(path) else {
      fail("development frontend does not exist: \{path}")
    }
    return path
  }
  FrontendEntryPath
}

///|
/// Locate the packaged ripgrep beside the installed Host. macOS stores data
/// below Contents/Resources; Linux and Windows keep the executable beside the
/// Host. Only a recognized Moon `_build` executable (or an embedding without
/// an executable path, used by development tests) may fall back to `PATH`.
/// An installed bundle with a missing asset fails closed instead of silently
/// running a machine-global ripgrep of an unknown version.
async fn ripgrep_command(executable : String?) -> String? {
  guard executable is Some(executable) else { return Some("rg") }
  let command_dir = @pathx.Path(executable).dirname().resolve()
  let candidates = [
    command_dir.join("..").join("Resources").join(ProtonPackageRipgrepPath),
    command_dir.join("rg.exe"),
    command_dir.join("rg"),
  ]
  for candidate in candidates {
    let path = candidate.normalize().to_string()
    if @fs.exists(path) {
      return Some(path)
    }
  }
  if @development.Layout::detect(executable) is Some(_) {
    Some("rg")
  } else {
    None
  }
}

///|
async test "ripgrep resolution uses only packaged or recognized development layouts" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-ripgrep-resolution-")
  let installed = root.join("installed")
  @fs.mkdir(installed.to_string(), recursive=true)
  let installed_host = installed.join("openseek-desktop").to_string()
  assert_true(ripgrep_command(Some(installed_host)) is None)
  let adjacent = installed.join("rg").to_string()
  @fs.write_file(adjacent, "rg", create_mode=CreateOrTruncate)
  assert_eq(ripgrep_command(Some(installed_host)), Some(adjacent))

  let macos = root.join("SeekMoon.app/Contents/MacOS")
  let resources_rg = root
    .join("SeekMoon.app/Contents/Resources")
    .join(ProtonPackageRipgrepPath)
  @fs.mkdir(macos.to_string(), recursive=true)
  @fs.mkdir(resources_rg.dirname().to_string(), recursive=true)
  @fs.write_file(resources_rg.to_string(), "rg", create_mode=CreateOrTruncate)
  assert_eq(
    ripgrep_command(Some(macos.join("openseek-desktop").to_string())),
    Some(resources_rg.normalize().to_string()),
  )

  let development = root.join("_build/native/debug/build/openseek_desktop")
  @fs.mkdir(development.to_string(), recursive=true)
  assert_eq(
    ripgrep_command(Some(development.join("openseek_desktop").to_string())),
    Some("rg"),
  )
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
async test "packaged frontend wins before the matching checkout document" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-development-frontend-")
  let command_dir = root.join("_build/native/debug/build/openseek_desktop")
  @fs.mkdir(command_dir.to_string(), recursive=true)
  let host = command_dir.join("openseek_desktop.exe").to_string()
  let development = root.join("desktop-dev.html").to_string()
  @fs.write_file(development, "development", create_mode=CreateOrTruncate)
  assert_eq(frontend_entry_path(host), development)
  let assets = command_dir.join("assets")
  @fs.mkdir(assets.to_string())
  let packaged = assets.join("index.html").to_string()
  @fs.write_file(packaged, "packaged", create_mode=CreateOrTruncate)
  assert_eq(frontend_entry_path(host), packaged)
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
/// Read the application version written by `proton_cli package`. Development
/// binaries have no package manifest and identify themselves explicitly
/// instead of consulting a second source version constant.
pub async fn package_version(executable : String) -> String {
  let command_dir = @pathx.Path(executable).dirname().resolve()
  let manifest = command_dir
    .join("..")
    .join("Resources")
    .join("proton-package.json")
    .normalize()
    .to_string()
  guard @fs.exists(manifest) else { return "development" }
  let text = @fs.read_file(manifest).text() catch { _ => return "development" }
  match @json.parse(text) {
    Object(fields) =>
      match fields.get("version") {
        Some(String(version)) if !version.is_blank() => version
        _ => "development"
      }
    _ => "development"
  }
}

///|
/// The running .app bundle root, when the executable sits in a macOS bundle
/// layout (`…/Name.app/Contents/MacOS/exe`); None anywhere else — dev
/// binaries and other platforms — which disables self-update.
pub fn app_bundle_path(executable : String) -> String? {
  let macos_dir = @pathx.Path(executable).dirname()
  let contents_dir = macos_dir.dirname()
  guard macos_dir.basename() == "MacOS" && contents_dir.basename() == "Contents" else {
    return None
  }
  let bundle = contents_dir.dirname().to_string()
  if bundle.has_suffix(".app") {
    Some(bundle)
  } else {
    None
  }
}
