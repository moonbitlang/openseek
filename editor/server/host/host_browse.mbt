// Host filesystem browsing for the repository picker: listing absolute host
// directories and switching the served workspace root. These are host-level
// packets handled outside the per-session policy server. What they may reach
// is bounded by the server's `HostBrowseScope`: unrestricted browsing is
// reserved for loopback listeners unless the operator grants an explicit
// `--browse-root` scope, so an unauthenticated LAN-bound server cannot be
// re-rooted onto arbitrary readable directories.

///|
/// Where host browsing and workspace switching may reach.
priv enum HostBrowseScope {
  /// The whole host filesystem — the loopback default.
  BrowseHost
  /// Only the given realpathed directory and its descendants.
  BrowseWithin(String)
  /// Browsing rejected entirely — the non-loopback default.
  BrowseDisabled
}

///|
fn HostBrowseScope::allows(self : HostBrowseScope, real : String) -> Bool {
  match self {
    BrowseHost => true
    BrowseWithin(scope) =>
      scope == "/" || real == scope || real.has_prefix("\{scope}/")
    BrowseDisabled => false
  }
}

///|
/// The parent offered in listings; `None` at the scope boundary so clients
/// cannot navigate above it.
fn HostBrowseScope::visible_parent(
  self : HostBrowseScope,
  real : String,
) -> String? {
  match self {
    BrowseWithin(scope) if real == scope => None
    _ => parent_host_path(real)
  }
}

///|
fn browse_disabled_error(request_id : String) -> @remote_protocol.ServerPacket {
  host_browse_error(
    request_id,
    InvalidUri,
    "Workspace browsing is disabled on this server. Restart it with --browse-root to allow switching repositories.",
  )
}

///|
/// One resolved host directory level or a filesystem-shaped failure.
priv enum HostDirectoryListResult {
  HostDirectoryListOk(@remote_protocol.HostDirectoryListing)
  HostDirectoryListError(@workspace.FileSystemProviderErrorCode, String)
}

///|
/// Answers `ListHostDirectory`: child directories of one absolute host path
/// (the current workspace root when the path is empty), dot-entries skipped,
/// repository-looking children flagged. Listing never leaves the browse
/// scope — an out-of-scope path is rejected before any filesystem probe, so
/// even existence outside the scope is not disclosed.
async fn list_host_directory_packet(
  workspace : NativeWorkspace,
  request : @remote_protocol.HostPathRequest,
) -> String {
  guard !(workspace.browse_scope is BrowseDisabled) else {
    return browse_disabled_error(request.id).to_json().stringify()
  }
  let target = if request.path == "" {
    // Start at the served root; fall back to the scope root when the served
    // root itself lies outside an explicit --browse-root scope.
    if workspace.browse_scope.allows(workspace.root.val) {
      workspace.root.val
    } else {
      match workspace.browse_scope {
        BrowseWithin(scope) => scope
        BrowseHost | BrowseDisabled => workspace.root.val
      }
    }
  } else {
    request.path
  }
  let packet : @remote_protocol.ServerPacket = match
    resolve_host_directory_listing(workspace.browse_scope, target) {
    HostDirectoryListOk(listing) =>
      HostDirectoryListed({ id: request.id, listing, })
    HostDirectoryListError(code, message) =>
      host_browse_error(request.id, code, message)
  }
  packet.to_json().stringify()
}

///|
async fn resolve_host_directory_listing(
  scope : HostBrowseScope,
  target : String,
) -> HostDirectoryListResult {
  let real = realpath_or_normalized(target)
  if !scope.allows(real) {
    return HostDirectoryListError(
      InvalidUri,
      "Path is outside the allowed browse scope.",
    )
  }
  if (Some(@fs.exists(real)) catch { _ => None }) != Some(true) {
    return HostDirectoryListError(FileNotFound, "Directory does not exist.")
  }
  match (Some(@fs.kind(real)) catch { _ => None }) {
    Some(Directory) => ()
    _ =>
      return HostDirectoryListError(
        FileNotADirectory,
        "Path is not a directory.",
      )
  }
  let names = Some(@fs.readdir(real, include_hidden=true)) catch { _ => None }
  guard names is Some(names) else {
    return HostDirectoryListError(Unavailable, "Unable to read directory.")
  }
  // MoonBit's default String order is shortlex; a directory picker wants
  // plain lexicographic order.
  names.sort_by(compare_names_lexicographic)
  let entries : Array[@remote_protocol.HostDirectoryEntry] = []
  for name in names {
    // The picker chooses repositories; hidden directories are noise there.
    guard !name.has_prefix(".") else { continue }
    let child = join_host_path(real, name)
    if (Some(@fs.kind(child)) catch { _ => None }) is Some(Directory) {
      entries.push({
        name,
        path: child,
        is_workspace: looks_like_repository_root(child),
      })
    }
  }
  HostDirectoryListOk({
    path: real,
    parent: scope.visible_parent(real),
    entries,
  })
}

///|
/// Answers `SwitchWorkspace`: validates the target, re-roots the shared
/// workspace state, responds to the requester with its request id, and pushes
/// an uncorrelated `WorkspaceSwitched` to every other session so all
/// connected clients move together.
async fn switch_workspace_packets(
  workspace : NativeWorkspace,
  session : Int32,
  outbox : @aqueue.Queue[String],
  request : @remote_protocol.HostPathRequest,
) -> Unit {
  guard !(workspace.browse_scope is BrowseDisabled) else {
    outbox.put(browse_disabled_error(request.id).to_json().stringify())
    return
  }
  match resolve_switch_target(workspace.browse_scope, request.path) {
    HostSwitchTarget(real) => {
      workspace.switch_root(real)
      let name = host_basename(real)
      let response : @remote_protocol.ServerPacket = WorkspaceSwitched({
        id: request.id,
        root: real,
        name,
      })
      outbox.put(response.to_json().stringify())
      let push : @remote_protocol.ServerPacket = WorkspaceSwitched({
        id: "",
        root: real,
        name,
      })
      workspace.sessions.broadcast_except(session, push.to_json().stringify())
    }
    HostSwitchError(code, message) => {
      let error : @remote_protocol.ServerPacket = host_browse_error(
        request.id,
        code,
        message,
      )
      outbox.put(error.to_json().stringify())
    }
  }
}

///|
priv enum HostSwitchResult {
  HostSwitchTarget(String)
  HostSwitchError(@workspace.FileSystemProviderErrorCode, String)
}

///|
async fn resolve_switch_target(
  scope : HostBrowseScope,
  path : String,
) -> HostSwitchResult {
  if path == "" {
    return HostSwitchError(InvalidUri, "Workspace path is required.")
  }
  let real = realpath_or_normalized(path)
  if !scope.allows(real) {
    return HostSwitchError(
      InvalidUri,
      "Path is outside the allowed browse scope.",
    )
  }
  if (Some(@fs.exists(real)) catch { _ => None }) != Some(true) {
    return HostSwitchError(FileNotFound, "Workspace directory does not exist.")
  }
  match (Some(@fs.kind(real)) catch { _ => None }) {
    Some(Directory) => HostSwitchTarget(real)
    _ =>
      HostSwitchError(FileNotADirectory, "Workspace path is not a directory.")
  }
}

///|
/// Uncorrelated announcement of the currently served workspace, enqueued to
/// every newly attached session so a client that reconnected across a switch
/// can reconcile stale editor state against the live root.
fn workspace_announce_packet(workspace : NativeWorkspace) -> String {
  let root = workspace.root.val
  let packet : @remote_protocol.ServerPacket = WorkspaceSwitched({
    id: "",
    root,
    name: host_basename(root),
  })
  packet.to_json().stringify()
}

///|
fn host_browse_error(
  request_id : String,
  code : @workspace.FileSystemProviderErrorCode,
  message : String,
) -> @remote_protocol.ServerPacket {
  RemoteError(
    ProtocolError(
      ProtocolProviderError,
      message,
      request_id~,
      provider_code=code.to_string(),
    ),
  )
}

///|
/// A directory reads as a repository root when it carries MoonBit module
/// metadata or a git checkout marker.
async fn looks_like_repository_root(path : String) -> Bool {
  for marker in ["moon.mod", "moon.mod.json", ".git"] {
    if (Some(@fs.exists(join_host_path(path, marker))) catch { _ => None }) ==
      Some(true) {
      return true
    }
  }
  false
}

///|
/// Code-unit lexicographic comparison (the default `String` order is
/// shortlex, which reads wrongly in a file listing).
fn compare_names_lexicographic(left : String, right : String) -> Int32 {
  let shared = left.length().min(right.length())
  for index in 0..<shared {
    let l = left[index].to_int()
    let r = right[index].to_int()
    if l != r {
      return l - r
    }
  }
  left.length() - right.length()
}

///|
fn join_host_path(base : String, name : String) -> String {
  if base == "/" {
    "/\{name}"
  } else {
    "\{base}/\{name}"
  }
}

///|
/// The parent of a normalized absolute path; `None` at the filesystem root.
fn parent_host_path(path : String) -> String? {
  if path == "/" {
    return None
  }
  match path.rev_find("/") {
    Some(0) => Some("/")
    Some(index) => Some(path[0:index].to_owned())
    None => None
  }
}

///|
fn host_basename(path : String) -> String {
  if path == "/" {
    return "/"
  }
  match path.rev_after("/") {
    Some(name) => name.to_owned()
    None => path
  }
}
