///|
/// Paths belonging to an unbundled host built by Moon from this checkout.
/// The type is opaque so every consumer uses the same validated `_build`
/// layout instead of reconstructing parent-directory counts independently.
struct Layout {
  checkout_root : @path.Path
  build_root : @path.Path
}

///|
/// Recognize `_build/native/<profile>/build/openseek_desktop/<executable>` and
/// return the checkout and profile build roots it identifies. Installed
/// executables deliberately do not match this layout.
pub fn Layout::detect(executable : String) -> Layout? {
  let command_dir = @path.Path(executable).dirname().resolve()
  guard command_dir.basename() == "openseek_desktop" else { return None }
  let build_root = command_dir.dirname()
  guard build_root.basename() == "build" else { return None }
  let profile = build_root.dirname()
  guard profile.basename() == "debug" || profile.basename() == "release" else {
    return None
  }
  let native = profile.dirname()
  guard native.basename() == "native" else { return None }
  let moon_build = native.dirname()
  guard moon_build.basename() == "_build" else { return None }
  { checkout_root: moon_build.dirname(), build_root } |> Some
}

///|
/// Return the checked-in HTML document used by the unbundled frontend.
pub fn Layout::frontend_entry(self : Layout) -> String {
  self.checkout_root.join("desktop-dev.html").normalize().to_string()
}

///|
/// Return the engine output directory in the same native profile as the host.
pub fn Layout::engine_dir(self : Layout) -> String {
  self.build_root.join("bobzhang/openseek/cmd/openseek").normalize().to_string()
}

///|
/// Return the worktree-local directory for development auth, logs, and state.
pub fn Layout::state_dir(self : Layout) -> String {
  self.checkout_root.join("desktop/target/dev-state").normalize().to_string()
}
