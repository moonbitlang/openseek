///|
/// User files always live in the stable platform data directory, including
/// development builds whose runtime logs live inside the checkout.
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
async fn create_unnamed_workspace_op() -> @protocol.BrowseDirectoryReply {
  let root = unnamed_workspaces_dir() catch {
    HostError(message) => return BrowseError(message)
  }
  create_unnamed_workspace_in(root) catch {
    error if @async.is_being_cancelled() => raise error
    HostError(message) => BrowseError(message)
    error => raise error
  }
}

///|
/// Exclusive mkdir arbitrates names across clients and host processes. Only
/// EEXIST advances the name; permission and disk failures must reach the UI.
/// Existing directories and their user files are never reused or removed.
async fn create_unnamed_workspace_in(
  root : @pathx.Absolute,
) -> @protocol.BrowseDirectoryReply {
  try {
    @fs.mkdir(root.to_string(), recursive=true) catch {
      @os_error.OSError(_) as error if error.is_EEXIST() => {
        guard @fs.kind(root.to_string()) is Directory else {
          raise HostError("workspace storage path is not a directory")
        }
      }
      error => raise error
    }
  } catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      raise HostError(
        "could not create the workspace storage directory: \{error}",
      )
  }
  for index = 1; ; index = index + 1 {
    let name = if index == 1 {
      "Unnamed workspace"
    } else {
      "Unnamed workspace \{index}"
    }
    let target = root.join((name : @pathx.Relative))
    let path = target.resource_path()
    @fs.mkdir(target.to_string()) catch {
      error if @async.is_being_cancelled() => raise error
      @os_error.OSError(_) as error if error.is_EEXIST() => continue
      error =>
        raise HostError("could not create the unnamed workspace: \{error}")
    }
    return Listing(path~, parent=Some(root.resource_path()), entries=[])
  }
}

///|
/// Use the canonical storage root so symlinked app-data directories still
/// classify registered (canonical) workspace paths consistently after reload.
pub async fn chat_workspace_root() -> String? {
  let root = unnamed_workspaces_dir() catch { HostError(_) => return None }
  let resolved = @fs.realpath(root.to_string()) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => root.to_string()
    error => raise error
  }
  guard @pathx.Path(resolved).to_absolute() is Some(root) else {
    raise HostError("workspace storage path is not absolute")
  }
  Some(root.resource_path())
}
