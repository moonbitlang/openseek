///|
/// Per-user runtime directory for the host's own state. The lepus framework
/// IPC config lives here instead of inside the .app bundle: a signed bundle
/// is read-only by convention (and may be mounted read-only under app
/// translocation), and writing next to the binary also breaks when a
/// repackage replaces the bundle under a running instance. Uses
/// `~/Library/Application Support/OpenSeek Desktop` where that layout exists
/// (macOS) and `~/.openseek-desktop` elsewhere.
async fn app_runtime_dir() -> String? {
  guard @home.dir() is Some(home) else { return None }
  let home_path : @mbpath.Path = home
  let app_support = home_path.join("Library").join("Application Support")
  let app_support_exists = (@mbfs.kind(app_support.to_string()) is Directory) catch {
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
/// determined or created; callers then fall back to lepus defaults.
pub async fn prepared_runtime_dir() -> String? {
  guard app_runtime_dir() is Some(dir) else { return None }
  let exists = (@mbfs.kind(dir) is Directory) catch { _ => false }
  if !exists {
    @mbfs.mkdir(dir) catch {
      _ => return None
    }
  }
  Some(dir)
}

///|
/// Drop framework configs left behind by earlier launches. Each launch writes
/// a fresh timestamped file (so two concurrent instances never clobber each
/// other); without this sweep they would accumulate forever.
pub async fn remove_stale_framework_configs(dir : String) -> Unit {
  let entries = @mbfs.readdir(dir) catch { _ => return }
  for entry in entries {
    if entry.has_prefix("lepus-framework-") && entry.has_suffix(".json") {
      @mbfs.remove(dir + "/" + entry) catch {
        _ => ()
      }
    }
  }
}
