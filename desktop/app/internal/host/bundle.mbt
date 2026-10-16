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
const DevelopmentVizBundlePath = "_build/js/debug/build/moonbitlang/openseek-viz-app/openseek-viz-app.js"

///|
#cfg(platform="windows")
const PackagedExecutableSuffix = ".exe"

///|
#cfg(not(platform="windows"))
const PackagedExecutableSuffix = ""

///|
/// Locate the visualizer assets belonging to this exact host build.
///
/// Both branches read the host's resource directory, exactly like
/// `frontend_entry_path`: an installed application resolves the canonical
/// `seekmoon/` tree, while the development launcher declares `desktop/` and
/// the checkout above it holds the shell and the bundle. Resolving both
/// entries the same way keeps them from disagreeing about which layout is
/// running. Export reads validate these paths lazily, so a missing asset
/// does not prevent unrelated host services from starting.
pub fn viz_assets(resources : @resources.Resources?) -> VizAssets raise {
  guard resources is Some(resources) else {
    raise @working_host.HostError("this host has no bundled session visualizer")
  }
  let assets : VizAssets = if resources.packaged {
    let viz = resources.dir.join(PackagedVizDir)
    {
      shell: viz.join("index.html").normalize().to_string(),
      bundle: viz.join("viz_app.js").normalize().to_string(),
    }
  } else {
    let checkout = resources.dir.dirname()
    {
      shell: checkout.join(DevelopmentVizShellPath).normalize().to_string(),
      bundle: checkout.join(DevelopmentVizBundlePath).normalize().to_string(),
    }
  }
  assets
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
/// Resolve the packaged tools from the platform-independent resource
/// directory. Development deliberately uses PATH even if a previous package
/// build left generated `seekmoon/` files in the checkout, and so does a host
/// that was told of no resource directory at all.
pub async fn PackagedTools::resolve(
  resources : @resources.Resources?,
) -> PackagedTools? {
  guard resources is Some(resources) && resources.packaged else { return None }
  PackagedTools::resolve_from_resource_dir(resources.dir.to_string())
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
/// mbtx snippets, while Codex app-server passes it to its own tool processes.
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
/// Locate the frontend from the resource directory. The supported
/// development launcher exposes `desktop/` as that directory, while every
/// installed app exposes the package root containing canonical `seekmoon/`.
pub async fn frontend_entry_path(resources : @resources.Resources) -> String {
  if !resources.packaged {
    let path = resources.dir
      .dirname()
      .join("desktop-dev.html")
      .normalize()
      .to_string()
    guard @fs.exists(path) else {
      raise @working_host.HostError(
        "development frontend does not exist: \{path}",
      )
    }
    return path
  }
  let path = resources.dir
    .join(PackagedFrontendEntryPath)
    .normalize()
    .to_string()
  guard @fs.exists(path) else {
    raise @working_host.HostError("packaged frontend does not exist: \{path}")
  }
  path
}

///|
/// Locate ripgrep in the canonical resource tree. An installed bundle
/// with a missing asset fails closed instead of silently
/// running a machine-global ripgrep of an unknown version.
async fn ripgrep_command(resources : @resources.Resources?) -> String? {
  if PackagedTools::resolve(resources) is Some(tools) {
    return Some(tools.ripgrep)
  }
  if resources is Some(resources) && resources.packaged {
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
async fn moongrep_command(resources : @resources.Resources?) -> String? {
  guard resources is Some(resources) && resources.packaged else {
    return Some("moonx")
  }
  let path = resources.dir
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
  let development : @resources.Resources = { dir: "desktop", packaged: false, }
  assert_eq(ripgrep_command(Some(development)), Some("rg"))
  assert_eq(moongrep_command(Some(development)), Some("moonx"))
  // A host told of no resource directory resolves its tools the same way.
  assert_eq(ripgrep_command(None), Some("rg"))
  assert_eq(moongrep_command(None), Some("moonx"))
}

///|
async test "development frontend comes from the declared resource root" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-development-frontend-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  let development = root.join("desktop-dev.html").to_string()
  @fs.write_file(development, "development", create_mode=CreateOrTruncate)
  let resources = root.join("desktop")
  @fs.mkdir(resources.to_string(), recursive=true)
  let packaged = resources.join(PackagedFrontendEntryPath)
  @fs.mkdir(packaged.dirname().to_string(), recursive=true)
  @fs.write_file(packaged.to_string(), "packaged", create_mode=CreateOrTruncate)
  // Development must never consume generated package inputs left in the
  // checkout; the launcher's declared resource root identifies the source
  // checkout without threading the host executable through this API.
  assert_eq(
    frontend_entry_path({ dir: resources, packaged: false, }),
    development,
  )
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

///|
/// Read the install bootstrap supplied by the desktop host.
pub async fn ssh_installer_bootstrap(
  resources : @resources.Resources,
) -> String {
  @fs.read_file(resources.dir.join("seekmoon/remote-install.py").to_string()).text()
}
