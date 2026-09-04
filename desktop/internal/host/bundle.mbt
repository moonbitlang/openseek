///|
const PackagedFrontendEntryPath = "seekmoon/web/index.html"

///|
const PackagedRipgrepPath = "seekmoon/bin/rg"

///|
const PackagedMoongrepPath = "seekmoon/bin/moongrep"

///|
const PackagedVizDir = "seekmoon/web/viz"

///|
/// The checkout-relative visualizer shell used during development. The
/// development launcher declares `desktop/` as Proton's resource directory,
/// so the shell sits one level above it, in the same place
/// `package/build.mjs` reads it from when staging a package.
const DevelopmentVizShellPath = "web/index.html"

///|
/// The development visualizer bundle. `package/build.mjs` builds the JS
/// targets at `debug` for the development launcher, the same profile
/// `engine_command` resolves for the development engine.
const DevelopmentVizBundlePath = "_build/js/debug/build/bobzhang/openseek-viz-app/openseek-viz-app.js"

///|
#cfg(platform="windows")
const PackagedExecutableSuffix = ".exe"

///|
#cfg(not(platform="windows"))
const PackagedExecutableSuffix = ""

///|
/// The visualizer shell and compiled bundle used for a standalone export.
pub struct VizAssets {
  shell : String
  bundle : String
}

///|
/// Locate the visualizer assets belonging to this exact host build.
///
/// Both branches read Proton's resource directory, exactly like
/// `frontend_entry_path`: an installed application resolves the canonical
/// `seekmoon/` tree, while the development launcher declares `desktop/` and
/// the checkout above it holds the shell and the bundle. Resolving both
/// entries the same way keeps them from disagreeing about which layout is
/// running. A missing asset fails instead of silently embedding an unrelated
/// artifact.
pub async fn viz_assets() -> VizAssets {
  let resource_dir : @pathx.Path = @proton.resource_dir()
  let assets : VizAssets = if @proton.is_packaged() {
    let viz = resource_dir.join(PackagedVizDir)
    {
      shell: viz.join("index.html").normalize().to_string(),
      bundle: viz.join("viz_app.js").normalize().to_string(),
    }
  } else {
    let checkout = resource_dir.dirname()
    {
      shell: checkout.join(DevelopmentVizShellPath).normalize().to_string(),
      bundle: checkout.join(DevelopmentVizBundlePath).normalize().to_string(),
    }
  }
  guard @fs.exists(assets.shell) else {
    raise HostError("session visualizer shell does not exist: \{assets.shell}")
  }
  guard @fs.exists(assets.bundle) else {
    raise HostError(
      "session visualizer bundle does not exist: \{assets.bundle}",
    )
  }
  assets
}

///|
/// Read the visualizer shell and bundle selected by `viz_assets`.
pub async fn VizAssets::read(self : VizAssets) -> (String, String) {
  let shell = @fs.read_file(self.shell).text() catch {
    error =>
      raise HostError("could not read session visualizer shell: \{error}")
  }
  let bundle = @fs.read_file(self.bundle).text() catch {
    error =>
      raise HostError("could not read session visualizer bundle: \{error}")
  }
  (shell, bundle)
}

///|
/// The installed directory containing the Desktop's packaged command-line
/// tools. The value exists only when the pinned ripgrep asset is present, so
/// an incomplete installed bundle cannot shadow the user's PATH with an empty
/// or unrelated directory.
struct PackagedTools {
  bin_dir : String
  ripgrep : String
}

///|
/// Resolve the packaged tools from Proton's platform-independent resource
/// directory. Development deliberately uses PATH even if a previous package
/// build left generated `seekmoon/` files in the checkout.
pub async fn PackagedTools::resolve() -> PackagedTools? {
  if !@proton.is_packaged() {
    return None
  }
  PackagedTools::resolve_from_resource_dir(@proton.resource_dir())
}

///|
/// Resolve a canonical resource root. This type method lets tests exercise
/// path policy without pretending their test executable is a Proton package.
async fn PackagedTools::resolve_from_resource_dir(
  resource_dir : String,
) -> PackagedTools? {
  let path = @pathx.Path(resource_dir)
    .join(PackagedRipgrepPath + PackagedExecutableSuffix)
    .normalize()
  guard @fs.exists(path.to_string()) else { return None }
  Some({ bin_dir: path.dirname().to_string(), ripgrep: path.to_string(), })
}

///|
/// Put the packaged tools first in this process's PATH. Desktop child
/// processes inherit this environment: OpenSeek's engine passes it to agent
/// shell tools, while Codex app-server passes it to its own tool processes.
/// Keep an already-leading entry unchanged so embedding launchers cannot
/// duplicate it.
pub fn PackagedTools::apply_to_process_env(self : PackagedTools) -> Unit {
  @sys.set_env_var("PATH", self.path_with_precedence(@sys.get_env_var("PATH")))
}

///|
fn PackagedTools::path_with_precedence(
  self : PackagedTools,
  current : String?,
) -> String {
  if current is Some(path) &&
    (path == self.bin_dir || path.has_prefix(self.bin_dir + @env.path_sep)) {
    return path
  }
  @env.prepend_to_path_env(self.bin_dir, current)
}

///|
/// Locate the frontend from Proton's resource directory. The supported
/// development launcher exposes `desktop/` as that directory, while every
/// installed app exposes the package root containing canonical `seekmoon/`.
pub async fn frontend_entry_path() -> String {
  if !@proton.is_packaged() {
    let path = @pathx.Path(@proton.resource_dir())
      .dirname()
      .join("desktop-dev.html")
      .normalize()
      .to_string()
    guard @fs.exists(path) else {
      raise HostError("development frontend does not exist: \{path}")
    }
    return path
  }
  let path = @pathx.Path(@proton.resource_dir())
    .join(PackagedFrontendEntryPath)
    .normalize()
    .to_string()
  guard @fs.exists(path) else {
    raise HostError("packaged frontend does not exist: \{path}")
  }
  path
}

///|
/// The pinned mooncakes coordinate used when the host resolves moongrep through
/// `moonx`. Search and Pattern Repair must validate with the same provider.
const MoongrepPackageCoordinate : String = "moonbit-community/moongrep@0.3.1"

///|
/// Locate ripgrep in the canonical Proton resource tree. An installed bundle
/// with a missing asset fails closed instead of silently
/// running a machine-global ripgrep of an unknown version.
async fn ripgrep_command() -> String? {
  if PackagedTools::resolve() is Some(tools) {
    return Some(tools.ripgrep)
  }
  if @proton.is_packaged() {
    None
  } else {
    Some("rg")
  }
}

///|
/// Locate the semantic-search provider beside the installed Host. A packaged
/// `moongrep` binary serves installed bundles, mirroring the ripgrep layout;
/// otherwise the provider resolves through `moonx` from PATH with a pinned
/// mooncakes registry coordinate.
///
/// This is deliberately not fail-closed like ripgrep: moongrep ships no
/// upstream release binaries, so a trial build has no asset to fail back on. A
/// real bundle with a staged `moongrep` binary always wins; the `moonx` PATH
/// fallback stays a documented interim provider until the package vendors a
/// moongrep binary (or a bundled `moongrep.wasm` run through the packaged
/// moonrun). The pinned coordinate keeps the version deterministic instead of
/// silently running an arbitrary machine binary.
async fn moongrep_command() -> String? {
  if !@proton.is_packaged() {
    return Some("moonx")
  }
  let path = @pathx.Path(@proton.resource_dir())
    .join(PackagedMoongrepPath + PackagedExecutableSuffix)
    .normalize()
    .to_string()
  if @fs.exists(path) {
    return Some(path)
  }
  Some("moonx")
}

///|
async test "packaged tools use only the canonical resource directory" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-ripgrep-resolution-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  let resources = root.join("Resources")
  let resource_dir = resources.to_string()
  assert_true(PackagedTools::resolve_from_resource_dir(resource_dir) is None)
  let packaged = resources
    .join(PackagedRipgrepPath + PackagedExecutableSuffix)
    .to_string()
  @fs.mkdir(@pathx.Path(packaged).dirname().to_string(), recursive=true)
  @fs.write_file(packaged, "rg", create_mode=CreateOrTruncate)
  guard PackagedTools::resolve_from_resource_dir(resource_dir)
    is Some(installed_tools) else {
    fail("expected canonical packaged tools")
  }
  let installed_bin = @pathx.Path(packaged).dirname().to_string()
  assert_eq(
    installed_tools.path_with_precedence(Some("/usr/bin")),
    "\{installed_bin}\{@env.path_sep}/usr/bin",
  )
  let already_first = "\{installed_bin}\{@env.path_sep}/usr/bin"
  assert_eq(
    installed_tools.path_with_precedence(Some(already_first)),
    already_first,
  )
}

///|
async test "unpackaged search commands use documented development providers" {
  if !@proton.is_packaged() {
    assert_eq(ripgrep_command(), Some("rg"))
    assert_eq(moongrep_command(), Some("moonx"))
  }
}

///|
async test "development frontend comes from Proton's declared resource root" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-development-frontend-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  let development = root.join("desktop-dev.html").to_string()
  @fs.write_file(development, "development", create_mode=CreateOrTruncate)
  let resources = root.join("desktop")
  @fs.mkdir(resources.to_string(), recursive=true)
  let resource_dir = resources.to_string()
  let previous_resource_dir = @sys.get_env_var("PROTON_RESOURCE_DIR")
  defer (match previous_resource_dir {
    Some(value) => @sys.set_env_var("PROTON_RESOURCE_DIR", value)
    None => @sys.unset_env_var("PROTON_RESOURCE_DIR")
  })
  @sys.set_env_var("PROTON_RESOURCE_DIR", resource_dir)
  let packaged = resources.join(PackagedFrontendEntryPath)
  @fs.mkdir(packaged.dirname().to_string(), recursive=true)
  @fs.write_file(packaged.to_string(), "packaged", create_mode=CreateOrTruncate)
  // Development must never consume generated package inputs left in the
  // checkout; the launcher's declared resource root identifies the source
  // checkout without threading the host executable through this API.
  assert_eq(frontend_entry_path(), development)
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
