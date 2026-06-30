///|
/// Per-user runtime directory for the host's own state (launch logs, the LSP
/// traffic log, sessions). It lives here instead of inside the .app bundle: a
/// signed bundle is read-only by convention (and may be mounted read-only under
/// app translocation), and writing next to the binary also breaks when a
/// repackage replaces the bundle under a running instance. Uses
/// `~/Library/Application Support/OpenSeek Desktop` where that layout exists
/// (macOS) and `~/.openseek-desktop` elsewhere.
async fn app_runtime_dir() -> String? {
  guard @home.dir() is Some(home) else { return None }
  let home_path : @path.Path = home
  let app_support = home_path.join("Library").join("Application Support")
  let app_support_exists = (@fs.kind(app_support.to_string()) is Directory) catch {
    _ => false
  }
  let dir = if app_support_exists {
    app_support.join("OpenSeek Desktop")
  } else {
    home_path.join(".openseek-desktop")
  }
  Some(dir.normalize().to_string())
}

///|
/// The runtime directory, created on demand. `None` when it cannot be
/// determined or created; callers then fall back to runtime defaults.
pub async fn prepared_runtime_dir() -> @path.Path? {
  guard app_runtime_dir() is Some(dir) else { return None }
  let exists = (@fs.kind(dir) is Directory) catch {
    @os_error.OSError(_) as os_error if os_error.is_ENOENT() => false
    error => raise error
  }
  if !exists {
    @fs.mkdir(dir) catch {
      error if @async.is_being_cancelled() => raise error
      _ => return None
    }
  }
  Some(dir)
}
