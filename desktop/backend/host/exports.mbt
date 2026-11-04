///|
/// Imports the workspace analyzer cannot see: the Desktop window host in
/// `desktop/app` is its own module (`desktop/app/moon.work`), outside the root
/// workspace this package is measured in. Every block in this file is used
/// there and nowhere else in the workspace, so `moon ide analyze` reports it as
/// unused. They are exported on purpose, not accidentally.

///|
/// Resolve the packaged tools from the platform-independent resource
/// directory. Development deliberately uses PATH even if a previous package
/// build left generated `seekmoon/` files in the checkout, and so does a host
/// that was told of no resource directory at all.
///
/// Exported for the Desktop window host, which installs them before it starts
/// the engine (`desktop/app/main.mbt`).
pub async fn PackagedTools::resolve(
  resources : @resources.Resources?,
) -> PackagedTools? {
  guard resources is Some(resources) && resources.packaged else { return None }
  PackagedTools::resolve_from_resource_dir(resources.dir.to_string())
}

///|
/// Put the packaged tools first in this process's PATH. Desktop child
/// processes inherit this environment: OpenSeek's engine passes it to agent
/// mbtx snippets, while Codex app-server passes it to its own tool processes.
/// Keep an already-leading entry unchanged so embedding launchers cannot
/// duplicate it.
///
/// Exported for the Desktop window host, which calls it on the tools
/// `PackagedTools::resolve` returned (`desktop/app/main.mbt`).
pub fn PackagedTools::apply_to_process_env(self : PackagedTools) -> Unit {
  @sys.set_env_var("PATH", self.path_with_precedence(@sys.get_env_var("PATH")))
}

///|
/// Locate the frontend from the resource directory. The supported
/// development launcher exposes `desktop/` as that directory, while every
/// installed app exposes the package root containing canonical `seekmoon/`.
///
/// Exported for the Desktop window host, which serves it as the window asset
/// (`desktop/app/main.mbt`).
pub async fn frontend_entry_path(resources : @resources.Resources) -> String {
  if !resources.packaged {
    let path = resources.dir
      .dirname()
      .join("desktop-dev.html")
      .normalize()
      .to_string()
    guard @fs.exists(path) else {
      raise HostError("development frontend does not exist: \{path}")
    }
    return path
  }
  let path = resources.dir
    .join(PackagedFrontendEntryPath)
    .normalize()
    .to_string()
  guard @fs.exists(path) else {
    raise HostError("packaged frontend does not exist: \{path}")
  }
  path
}

///|
/// The running .app bundle root, when the executable sits in a macOS bundle
/// layout (`…/Name.app/Contents/MacOS/exe`); None anywhere else — dev
/// binaries and other platforms — which disables self-update.
///
/// Exported for the Desktop window host, whose relaunch-after-update path
/// needs the bundle it is running from (`desktop/app/main.mbt`).
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
/// Resolve this desktop bundle's working-host resources. Missing visualizer
/// files are reported when exporting, not when starting unrelated services.
///
/// Exported for the Desktop window host, which is the only caller that knows
/// Proton's resource directory and packaging state (`desktop/app/main.mbt`).
pub async fn desktop_resources(
  resources : @resources.Resources,
) -> HostResources {
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
  {
    moonbit: DesktopBundle,
    viz: Some(assets),
    bin_dir: PackagedTools::resolve(Some(resources)).map(tools => tools.bin_dir),
    ripgrep: ripgrep_command(Some(resources)),
    moongrep: moongrep_command(Some(resources)),
  }
}

///|
/// A desktop page reload cannot reclaim its old emulator instances. Retire
/// those PTYs before attaching the new page; WebSocket-owned sessions are
/// cancelled automatically with their connection task group.
///
/// Exported for the Desktop window host, which owns the window's connection
/// and sweeps it on `host.connect` (`desktop/app/internal/extension`).
pub fn HostConnection::close_terminals(self : HostConnection) -> Unit {
  @terminal.close_all_terminals(self.terminal)
}

///|
/// Route a local desktop file click, including targets for the native browser.
/// Bound only on the window so a remote path cannot become a local file URL.
///
/// Exported for the Desktop window host's window-only
/// `host.open_path_preview` command (`desktop/app/internal/extension`).
pub async fn open_path_preview(
  payload : @protocol.OpenPathPayload,
) -> @protocol.OpenPathReply {
  open_path_op(payload, preview_browser=true)
}
