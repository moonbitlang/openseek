///|
/// Per-user runtime directory for the host's own state (launch logs, the LSP
/// traffic log, sessions). It lives here instead of inside the .app bundle: a
/// signed bundle is read-only by convention (and may be mounted read-only under
/// app translocation), and writing next to the binary also breaks when a
/// repackage replaces the bundle under a running instance. Uses
/// `~/Library/Application Support/SeekMoon` where that layout exists
/// (macOS) and `~/.openseek-desktop` elsewhere. An unbundled Moon host instead
/// keeps state under the detected checkout's `desktop/target/dev-state`.
async fn app_runtime_dir(executable : String) -> @pathx.Path? {
  if @development.Layout::detect(executable) is Some(layout) {
    let state : @pathx.Path = layout.state_dir()
    return Some(state)
  }
  guard @home.dir() is Some(home) else { return None }
  let home_path : @pathx.Path = home
  let app_support = home_path.join("Library").join("Application Support")
  let app_support_exists = (@fs.kind(app_support.to_string()) is Directory) catch {
    _ => false
  }
  let dir = if app_support_exists {
    app_support.join("SeekMoon")
  } else {
    home_path.join(".openseek-desktop")
  }
  Some(dir.normalize())
}

///|
/// The runtime directory, created on demand. `None` when it cannot be
/// determined or created; callers then fall back to runtime defaults.
pub async fn prepared_runtime_dir(executable : String) -> @pathx.Path? {
  guard app_runtime_dir(executable) is Some(dir) else { return None }
  let exists = (@fs.kind(dir.to_string()) is Directory) catch {
    @os_error.OSError(_) as os_error if os_error.is_ENOENT() => false
    error => raise error
  }
  if !exists {
    @fs.mkdir(dir.to_string(), recursive=true) catch {
      error if @async.is_being_cancelled() => raise error
      _ => return None
    }
  }
  Some(dir)
}

///|
async test "development state stays inside the detected checkout" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-development-state-")
  let command_dir = root.join("_build/native/debug/build/openseek_desktop")
  @fs.mkdir(command_dir.to_string(), recursive=true)
  let executable = command_dir.join("openseek_desktop.exe").to_string()
  let expected = root.join("desktop/target/dev-state").to_string()
  guard prepared_runtime_dir(executable) is Some(actual) else {
    fail("detected development state directory was not created")
  }
  assert_eq(actual.to_string(), expected)
  assert_true(@fs.kind(expected) is Directory)
  @fs.rmdir(root.to_string(), recursive=true)
}
