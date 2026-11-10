///|
/// Locate the retired standalone-chat storage without creating or deleting it.
/// Its stable app-data path lets clients exclude old chats from project lists.
fn unnamed_workspaces_dir() -> @pathx.Absolute raise HostError {
  guard platform_app_data_dir() is Some(data) else {
    raise HostError("cannot determine the application data directory")
  }
  guard data.join("SeekMoon").join("workspaces").to_absolute() is Some(root) else {
    raise HostError("the application data directory must be absolute")
  }
  root.normalize()
}

///|
/// Use the canonical storage root so symlinked app-data directories still
/// classify registered (canonical) workspace paths consistently after reload.
pub async fn chat_workspace_root() -> @protocol.ChatWorkspaceRoot {
  let root = unnamed_workspaces_dir() catch {
    HostError(message) => return Failed(message)
  }
  chat_workspace_root_in(root)
}

///|
async fn chat_workspace_root_in(
  root : @pathx.Absolute,
) -> @protocol.ChatWorkspaceRoot {
  try {
    let resolved = @fs.realpath(root.to_string()) catch {
      @os_error.OsError(NotFound, ..) => return Ready(root.resource_path())
      error => raise error
    }
    guard @fs.kind(resolved) is Directory else {
      return Failed("workspace storage path is not a directory")
    }
    guard @pathx.Path(resolved).to_absolute() is Some(canonical) else {
      return Failed("workspace storage path is not absolute")
    }
    Ready(canonical.resource_path())
  } catch {
    error => Failed("cannot access workspace storage: \{error}")
  }
}
