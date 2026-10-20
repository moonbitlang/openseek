///|
/// Paths belonging to an unbundled host built by Moon from this checkout.
/// The type is opaque so every consumer uses the same validated `_build`
/// layout instead of reconstructing parent-directory counts independently.
struct Layout {
  checkout_root : @path.Path
}

///|
/// Recognize
/// `desktop/app/_build/native/<profile>/build/openseek_desktop/app/<executable>`
/// and return the checkout it identifies. The window host builds in its own
/// `desktop/app/moon.work`, so its `_build` sits beside that workspace file
/// rather than at the checkout root. Installed executables deliberately do
/// not match this layout.
pub fn Layout::detect(executable : String) -> Layout? {
  let command_dir = @path.Path(executable).dirname().resolve()
  guard command_dir.basename() == "app" else { return None }
  let module_dir = command_dir.dirname()
  guard module_dir.basename() == "openseek_desktop" else { return None }
  let build_root = module_dir.dirname()
  guard build_root.basename() == "build" else { return None }
  let profile = build_root.dirname()
  guard profile.basename() == "debug" || profile.basename() == "release" else {
    return None
  }
  let native = profile.dirname()
  guard native.basename() == "native" else { return None }
  let moon_build = native.dirname()
  guard moon_build.basename() == "_build" else { return None }
  let workspace = moon_build.dirname()
  guard workspace.basename() == "app" else { return None }
  let desktop = workspace.dirname()
  guard desktop.basename() == "desktop" else { return None }
  { checkout_root: desktop.dirname(), } |> Some
}

///|
/// Return the worktree-local directory for development auth, logs, and state.
pub fn Layout::state_dir(self : Layout) -> String {
  self.checkout_root.join("desktop/target/dev-state").normalize().to_string()
}
