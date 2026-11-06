///|
const PackagedFrontendEntryPath = "seekmoon/web/index.html"

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
/// Locate the visualizer assets belonging to this exact host build.
///
/// Both branches read the host's resource directory, exactly like
/// `frontend_entry_path`: an installed application resolves the canonical
/// `seekmoon/` tree, while the development launcher declares `desktop/` and
/// the checkout above it holds the shell and the bundle. Resolving both
/// entries the same way keeps them from disagreeing about which layout is
/// running. A missing asset fails instead of silently embedding an unrelated
/// artifact.
pub async fn HostState::viz_assets(self : HostState) -> VizAssets {
  guard self.resources.viz is Some(assets) else {
    raise HostError("this host has no bundled session visualizer")
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
