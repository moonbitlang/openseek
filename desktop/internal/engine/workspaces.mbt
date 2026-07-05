// The workspace registry: project directories the user attached to the
// desktop. A workspace conversation runs in the project itself and keeps its
// durable sessions inside it (`<workspace>/.openseek` — the engine CLI's own
// relative default), so the desktop and a TUI launched in that directory
// resume each other's conversations. The registry only remembers which
// directories the user attached; the session files themselves say which
// workspace owns which conversation.

///|
const WorkspacesFile = "workspaces.json"

///|
/// The registry file: `<global session root>/workspaces.json`, beside the
/// scratch conversations' session store.
fn workspaces_file() -> @path.Path? {
  resolved_session_root().map(root => root.join(WorkspacesFile))
}

///|
/// The registered workspace directories, in registration order. A missing or
/// malformed registry reads as "no workspaces".
pub async fn registered_workspaces() -> Array[String] {
  guard workspaces_file() is Some(file) else { return [] }
  let text = @fsx.try_read_text(file) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return []
  }
  guard text is Some(text) else { return [] }
  let json = @json.parse(text) catch { _ => return [] }
  guard json is Object(fields) && fields.get("workspaces") is Some(Array(items)) else {
    return []
  }
  let paths : Array[String] = []
  for item in items {
    if item is String(path) && !path.is_empty() && !paths.contains(path) {
      paths.push(path)
    }
  }
  paths
}

///|
async fn write_registry(paths : Array[String]) -> Unit {
  guard resolved_session_root() is Some(root) else {
    raise EngineError(
      "cannot determine a session root; set OPENSEEK_SESSION_ROOT",
    )
  }
  @fsx.ensure_dir(root) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise EngineError("could not create \{root}: \{error}")
  }
  let registry : Json = { "workspaces": paths.to_json() }
  @fsx.write_text(root.join(WorkspacesFile), registry.stringify(indent=2)) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise EngineError("could not save the workspace list: \{error}")
  }
}

///|
/// Register `path` as a workspace and return the updated list. The path must
/// name an existing directory; `~` expands to the home directory. Registering
/// an already-registered directory is a no-op. A git repository gets the
/// in-project session store added to `.git/info/exclude`, so attaching a
/// project never dirties its status.
pub async fn add_workspace(path : String) -> Array[String] {
  // A real directory pick never contains control characters. A NUL-padded
  // dialog buffer once slipped through the is_dir check below — C-level
  // filesystem calls truncate at the first NUL while the MoonBit string
  // keeps the rest — and poisoned the registry, so refuse them outright.
  guard !path.iter().any(ch => ch.is_control()) else {
    raise EngineError("workspace path contains control characters")
  }
  let dir = expanded_workspace_path(path)
  guard @fsx.is_dir(dir) else { raise EngineError("\{dir} is not a directory") }
  let canonical = dir.to_string()
  let paths = registered_workspaces()
  if !paths.contains(canonical) {
    paths.push(canonical)
    write_registry(paths)
  }
  exclude_store_from_git(dir)
  paths
}

///|
/// Drop `path` from the registry and return the updated list. Only the
/// registry entry goes away — the directory and any sessions inside it are
/// untouched, so re-adding the workspace brings its conversations back.
pub async fn remove_workspace(path : String) -> Array[String] {
  let target = expanded_workspace_path(path).to_string()
  let paths = registered_workspaces().filter(p => p != target)
  write_registry(paths)
  paths
}

///|
/// Expand and absolutize a user-supplied workspace path: `~` becomes the home
/// directory, a relative path resolves against the process cwd.
fn expanded_workspace_path(path : String) -> @path.Path raise EngineError {
  let trimmed = path.trim().to_owned()
  guard !trimmed.is_empty() else {
    raise EngineError("workspace path must not be empty")
  }
  let expanded : @path.Path = if trimmed == "~" {
    guard @home.dir() is Some(home) else {
      raise EngineError("no home directory to expand ~ against")
    }
    home
  } else if trimmed is ['~', '/', .. rest] {
    guard @home.dir() is Some(home) else {
      raise EngineError("no home directory to expand ~ against")
    }
    home.join(rest.to_owned())
  } else {
    Path(trimmed)
  }
  expanded.resolve().normalize()
}

///|
/// A client-supplied workspace path, accepted only when it is registered:
/// op payloads may name a workspace, but the registry — host state — decides
/// which directories the webview may reach.
async fn registered_workspace(path : String) -> @path.Path? {
  let trimmed = path.trim().to_owned()
  guard !trimmed.is_empty() else { return None }
  if registered_workspaces().contains(trimmed) {
    Some(Path(trimmed))
  } else {
    None
  }
}

///|
/// A workspace's durable session store: the engine CLI's relative default
/// (`.openseek`) inside the project.
pub fn workspace_session_root(workspace : @path.Path) -> @path.Path {
  workspace.join(".openseek").normalize()
}

///|
/// The registered workspace owning `session`, found by where the session's
/// durable record lives (`<workspace>/.openseek/sessions/<id>`). The record's
/// location is the mapping — there is no separate index to fall out of date.
/// `None` for scratch conversations, whose records live in the global store.
async fn workspace_of_session(session : String) -> @path.Path? {
  guard safe_workspace_id(session) else { return None }
  for path in registered_workspaces() {
    let workspace : @path.Path = Path(path)
    let record = workspace_session_root(workspace)
      .join("sessions")
      .join(session)
    if @fsx.is_dir(record) {
      return Some(workspace)
    }
  }
  None
}

///|
/// The session store root holding `session`'s durable record: its workspace's
/// in-project store when one claims it, otherwise the global root.
async fn session_store_root(session : String) -> @path.Path? {
  if workspace_of_session(session) is Some(workspace) {
    return Some(workspace_session_root(workspace))
  }
  resolved_session_root()
}

///|
/// Keep the in-project session store out of `git status`: append `.openseek/`
/// to `.git/info/exclude` (repo-local, unlike the user's own `.gitignore`).
/// Only a directory `.git` qualifies — a worktree or submodule keeps its real
/// git dir elsewhere and is left alone. Best-effort: a failure never blocks
/// registration.
async fn exclude_store_from_git(dir : @path.Path) -> Unit {
  let git_dir = dir.join(".git")
  let is_repo = @fsx.is_dir(git_dir) catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  }
  guard is_repo else { return }
  let exclude = git_dir.join("info").join("exclude")
  let existing = (@fsx.try_read_text(exclude) catch {
    error if @async.is_being_cancelled() => raise error
    _ => None
  }).unwrap_or("")
  for line in existing.split("\n") {
    let line = line.trim().to_owned()
    if line == ".openseek" || line == ".openseek/" {
      return
    }
  }
  let updated = if existing.is_empty() || existing.has_suffix("\n") {
    existing + ".openseek/\n"
  } else {
    existing + "\n.openseek/\n"
  }
  @fsx.ensure_dir(git_dir.join("info")) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return
  }
  @fsx.write_text(exclude, updated) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
}
