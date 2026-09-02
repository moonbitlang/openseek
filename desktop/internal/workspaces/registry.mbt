// The workspace registry: project directories attached to the desktop — the
// ones the user picked, plus the default workspace a first launch attaches on
// their behalf. A workspace conversation runs in the project itself and keeps
// its durable sessions inside it (`<workspace>/.openseek` — the engine CLI's
// own relative default), so the desktop and a TUI launched in that directory
// resume each other's conversations. The registry only remembers which
// directories are attached; the session files themselves say which workspace
// owns which conversation.

///|
/// Debug is what the host boundary logs: proton renders a failed handler's
/// error through `Repr`, which prints only an opaque `<...: ...>` placeholder
/// for types without it — swallowing the one string that says what failed.
pub suberror WorkspaceError {
  WorkspaceError(String)
} derive(Debug)

///|
impl Show for WorkspaceError with fn output(self, logger) {
  match self {
    WorkspaceError(message) => logger.write_string(message)
  }
}

///|
const WorkspacesFile = "workspaces.json"

///|
/// Registry reads and read-modify-write mutations share one process-wide
/// lock. Remote requests run in independent tasks; without this serialization
/// two concurrent add/remove operations can both read the same old list and
/// let the later write silently erase the earlier one.
let workspace_registry_lock : @async.Mutex = Mutex()

///|
/// The registry file: `<global session root>/workspaces.json`. That root
/// holds no conversations of its own — every durable record lives in the
/// store of the workspace this file registers.
fn workspaces_file() -> @pathx.Absolute? {
  global_store_root().map(root => root.join(WorkspacesFile))
}

///|
/// The canonical (symlink-resolved) spelling of a workspace directory — the
/// registry's one identity per project, so `/tmp/x` and `/private/tmp/x`
/// cannot register as two workspaces holding separate watcher, diagnostics,
/// and session state, and every path the registry hands out matches the
/// canonical paths tools like moonc report. Falls back to the lexical
/// spelling when resolution fails (the directory vanished), keeping a dead
/// entry addressable for removal.
async fn canonical_path(dir : @pathx.Absolute) -> @pathx.Absolute {
  let resolved = @fs.realpath(dir.0) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return dir
  }
  @pathx.Path(resolved).to_absolute().unwrap_or(dir)
}

///|
/// Everything the registry file holds. `initialized` records that the
/// registry has already been through its one-time setup — attaching the
/// default workspace. Keeping it inside the same file, rather than in a
/// marker of its own, means every add or remove rewrites it along with the
/// list, so neither half can drift and a detached default workspace can
/// never be resurrected by the next launch.
priv struct Registry {
  workspaces : Array[@pathx.Absolute]
  initialized : Bool
}

///|
/// The registry contents. A missing or malformed registry reads as "no
/// workspaces, not initialized" — the same state a first launch sees, which
/// is what a user with no usable registry should get. Entries canonicalize
/// on read, so a registry written before symlink resolution (or edited by
/// hand) collapses aliases of one physical directory into its first spelling.
async fn read_registry_unlocked() -> Registry {
  let uninitialized : Registry = { workspaces: [], initialized: false, }
  guard workspaces_file() is Some(file) else { return uninitialized }
  let text = @fsx.try_read_text(file.to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return uninitialized
  }
  guard text is Some(text) else { return uninitialized }
  let json = @json.parse(text) catch { _ => return uninitialized }
  guard json is Object(fields) else { return uninitialized }
  // A registry written before the default workspace existed carries no
  // marker and therefore reads as uninitialized — correct, since that user
  // has never been offered one.
  let initialized = fields.get("initialized") is Some(True)
  guard fields.get("workspaces") is Some(Array(items)) else {
    return { workspaces: [], initialized, }
  }
  let paths : Array[@pathx.Absolute] = []
  for item in items {
    guard item is String(path) && !path.is_empty() else { continue }
    // Registry JSON is an input boundary. Ignore an edited relative or
    // incomplete spelling rather than letting it enter host state.
    guard @pathx.Path(path).to_absolute() is Some(path) else { continue }
    let canonical = canonical_path(path)
    if !paths.contains(canonical) {
      paths.push(canonical)
    }
  }
  { workspaces: paths, initialized, }
}

///|
pub async fn registered() -> Array[@pathx.Absolute] {
  workspace_registry_lock.acquire()
  defer workspace_registry_lock.release()
  read_registry_unlocked().workspaces
}

///|
async fn write_registry(registry : Registry) -> Unit {
  guard global_store_root() is Some(root) else {
    raise WorkspaceError("cannot determine a session root: HOME is unavailable")
  }
  @fsx.ensure_dir(root.to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise WorkspaceError("could not create \{root}: \{error}")
  }
  let json : Json = {
    "workspaces": registry.workspaces.map(path => path.0).to_json(),
    "initialized": registry.initialized.to_json(),
  }
  @fsx.write_text(root.join(WorkspacesFile).to_path(), json.stringify(indent=2)) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise WorkspaceError("could not save the workspace list: \{error}")
  }
}

///|
const WorkspaceDirName = "OpenSeek"

///|
/// The workspace a fresh install starts in: an `OpenSeek` folder inside the
/// user's Documents directory. The agent's output is user-facing work, not
/// app data, so it belongs where the user already looks for files. Where
/// Documents is comes from the platform (`@userdirs.documents_dir`); when
/// that folder does not exist (headless machines, say), the folder lives
/// directly under the home directory.
async fn default_workspace_dir() -> @pathx.Path? {
  guard @home.dir() is Some(home) else { return None }
  let parent : @pathx.Path = if @userdirs.documents_dir() is Some(documents) &&
    @fsx.is_dir(documents) {
    documents
  } else {
    home
  }
  Some(parent.join(WorkspaceDirName).normalize())
}

///|
/// The default workspace's canonical path, when it is attached right now.
/// `None` when the platform cannot name it, or when the user has detached it
/// since — a decision every later launch respects.
pub async fn default_workspace() -> @pathx.Absolute? {
  guard default_workspace_dir() is Some(dir) && dir.to_absolute() is Some(dir) else {
    return None
  }
  let canonical = canonical_path(dir)
  guard registered().contains(canonical) else { return None }
  Some(canonical)
}

///|
/// One-time registry setup: attach the default workspace
/// (`<Documents>/OpenSeek`, created when it is not there yet) so a fresh
/// install has somewhere to work, and record that this ran. Returns the
/// attached directory, or `None` when the registry has already been
/// initialized — the user may have detached the default workspace since, and
/// that decision outlives every later launch.
///
/// The host calls this before it serves any client, so the first
/// `workspace.list` a page sees already carries the default. There is
/// deliberately no commit broadcast: nothing is connected yet to receive one.
pub async fn initialize() -> @pathx.Absolute? {
  workspace_registry_lock.acquire()
  defer workspace_registry_lock.release()
  let registry = read_registry_unlocked()
  guard !registry.initialized else { return None }
  guard default_workspace_dir() is Some(dir) && dir.to_absolute() is Some(dir) else {
    raise WorkspaceError("cannot determine the default workspace directory")
  }
  @fsx.ensure_dir(dir.to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise WorkspaceError("could not create \{dir.0}: \{error}")
  }
  let canonical = canonical_path(dir)
  // Best-effort, exactly as `add_workspace` does it: the default workspace
  // is rarely a repository, but a user who initialized one there still gets
  // the in-project store kept out of `git status`.
  exclude_from_git(canonical, ".openseek")
  let paths = registry.workspaces
  if !paths.contains(canonical) {
    paths.push(canonical)
  }
  // The marker and the list commit together. A crash before this write
  // leaves the registry uninitialized, so the next launch simply repeats the
  // whole idempotent step.
  @async.protect_from_cancel(() => {
    write_registry({ workspaces: paths, initialized: true, })
  })
  Some(canonical)
}

///|
/// Register `path` as a workspace and return the updated list. The path must
/// name an existing directory; `~` expands to the home directory. Registering
/// an already-registered directory is a no-op. A git repository gets the
/// in-project session store added to `.git/info/exclude`, so attaching a
/// project never dirties its status.
pub async fn add(
  path : String,
  on_committed : (Array[@pathx.Absolute]) -> Unit raise,
) -> Array[@pathx.Absolute] {
  // A real directory pick never contains control characters. A NUL-padded
  // dialog buffer once slipped through the is_dir check below — C-level
  // filesystem calls truncate at the first NUL while the MoonBit string
  // keeps the rest — and poisoned the registry, so refuse them outright.
  guard !path.iter().any(ch => ch.is_control()) else {
    raise WorkspaceError("workspace path contains control characters")
  }
  let dir = expanded_path(path)
  guard @fsx.is_dir(dir.to_path()) else {
    raise WorkspaceError("\{dir.0} is not a directory")
  }
  // A worktree is not a workspace: registering a linked checkout would root
  // stores and language ops at a directory that can vanish with the
  // worktree. Non-git directories and repository subdirectories stay
  // attachable.
  if @gitx.is_linked_worktree(dir) {
    raise WorkspaceError(
      "\{dir.0} is a linked git worktree; attach the main checkout instead",
    )
  }
  let canonical = canonical_path(dir)
  // Best-effort ancillary work is deliberately before the durable commit:
  // cancellation here changes no registry state and needs no invalidation.
  exclude_from_git(dir, ".openseek")
  workspace_registry_lock.acquire()
  defer workspace_registry_lock.release()
  let registry = read_registry_unlocked()
  let paths = registry.workspaces
  // The write and broadcast callback are one finite, cancellation-shielded
  // linearization point while the lock is held. Once disk changes, every
  // client is therefore notified in that same total order even if the
  // requester disconnects before its RPC response.
  @async.protect_from_cancel(() => {
    if !paths.contains(canonical) {
      paths.push(canonical)
      write_registry({ ..registry, workspaces: paths, })
    }
    on_committed(paths)
  })
  paths
}

///|
/// Drop `path` from the registry and return the updated list. Only the
/// registry entry goes away — the directory and any sessions inside it are
/// untouched, so re-adding the workspace brings its conversations back.
pub async fn remove(
  path : String,
  on_committed : (Array[@pathx.Absolute]) -> Unit raise,
) -> Array[@pathx.Absolute] {
  let target = canonical_path(expanded_path(path))
  workspace_registry_lock.acquire()
  defer workspace_registry_lock.release()
  let registry = read_registry_unlocked()
  let paths = registry.workspaces.filter(p => p != target)
  @async.protect_from_cancel(() => {
    // `initialized` is rewritten untouched: detaching the default workspace
    // is a decision, not a reset, so the next launch must not attach it
    // again.
    write_registry({ ..registry, workspaces: paths, })
    on_committed(paths)
  })
  paths
}

///|
/// Expand and absolutize a user-supplied workspace path: `~` becomes the home
/// directory, a relative path resolves against the process cwd.
pub fn expanded_path(path : String) -> @pathx.Absolute raise WorkspaceError {
  let trimmed = path.trim().to_owned()
  guard !trimmed.is_empty() else {
    raise WorkspaceError("workspace path must not be empty")
  }
  let expanded : @pathx.Path = if trimmed == "~" {
    guard @home.dir() is Some(home) else {
      raise WorkspaceError("no home directory to expand ~ against")
    }
    home
  } else if trimmed is ['~', '/', .. rest] {
    guard @home.dir() is Some(home) else {
      raise WorkspaceError("no home directory to expand ~ against")
    }
    home.join(rest.to_owned())
  } else {
    Path(trimmed)
  }
  // `resolve` establishes the absolute-path guarantee; normalization keeps
  // that classification while cleaning the final workspace spelling.
  expanded.resolve().normalize()
}

///|
/// A client-supplied workspace path, accepted only when it is registered:
/// op payloads may name a workspace, but the registry — host state — decides
/// which directories the webview may reach. The hint canonicalizes before
/// the comparison, so a client still holding an attach-time symlink spelling
/// keeps matching the registry's physical one.
pub async fn registered_dir(path : @pathx.Absolute) -> @pathx.Absolute? {
  let canonical = canonical_path(path)
  if registered().contains(canonical) {
    Some(canonical)
  } else {
    None
  }
}

///|
/// A workspace's durable session store: the engine CLI's relative default
/// (`.openseek`) inside the project.
pub fn store_root(workspace : @pathx.Absolute) -> @pathx.Absolute {
  workspace.join(".openseek").normalize()
}

///|
/// Keep a desktop-owned directory (`.openseek`, `.worktrees`) out of
/// `git status`: append `<entry>/` to `.git/info/exclude` (repo-local,
/// unlike the user's own `.gitignore`). Only a directory `.git` qualifies —
/// a worktree or submodule keeps its real git dir elsewhere and is left
/// alone. Best-effort: a failure never blocks the caller.
pub async fn exclude_from_git(dir : @pathx.Absolute, entry : String) -> Unit {
  let git_dir = dir.join(".git")
  let is_repo = @fsx.is_dir(git_dir.to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  }
  guard is_repo else { return }
  let exclude = git_dir.join("info").join("exclude")
  let existing = (@fsx.try_read_text(exclude.to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => None
  }).unwrap_or("")
  for line in existing.split("\n") {
    let line = line.trim().to_owned()
    if line == entry || line == "\{entry}/" {
      return
    }
  }
  let updated = if existing.is_empty() || existing.has_suffix("\n") {
    "\{existing}\{entry}/\n"
  } else {
    "\{existing}\n\{entry}/\n"
  }
  @fsx.ensure_dir(git_dir.join("info").to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return
  }
  @fsx.write_text(exclude.to_path(), updated) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
}

// Tests for the workspace registry's pure pieces: user-path expansion and
// the in-project session-store layout. The registry file itself and the
// session→workspace probe depend on the filesystem and are covered by the
// live app.

///|
#cfg(not(platform="windows"))
test "a workspace's session store is the engine's in-project default" {
  assert_eq(
    store_root(@pathx.Path("/home/u/proj").resolve()).to_string(),
    "/home/u/proj/.openseek",
  )
}

///|
#cfg(not(platform="windows"))
test "workspace paths expand ~ against the home directory" {
  guard @home.dir() is Some(home) else {
    // No home in this environment; nothing to expand against.
    return
  }
  assert_eq(expanded_path("~").0, home.to_string())
  assert_eq(
    expanded_path("~/proj").0,
    home.join("proj").normalize().to_string(),
  )
  // Absolute paths pass through (normalized), and surrounding blanks drop.
  assert_eq(expanded_path("  /srv/code//app  ").0, "/srv/code/app")
}

///|
test "blank workspace paths are refused" {
  let _ = expanded_path("   ") catch {
    WorkspaceError(message) => {
      assert_true(message.contains("must not be empty"))
      return
    }
  }
  fail("a blank workspace path was accepted")
}

///|
/// Both spellings of one physical directory canonicalize to the same
/// identity, and a vanished directory keeps its lexical spelling so a dead
/// registry entry stays removable.
async test "workspace identity follows symlinks and survives deletion" {
  let dir = @fs.tmpdir(prefix="openseek-workspace-canon-")
  let real = @pathx.Path(dir).join("real")
  @fs.mkdir(real.to_string())
  let link = @pathx.Path(dir).join("link")
  @fs.symlink(link.to_string(), target=real.to_string())
  let missing = @pathx.Path(dir).join("missing")
  guard real.to_absolute() is Some(real_path) &&
    link.to_absolute() is Some(link_path) &&
    missing.to_absolute() is Some(missing_path) else {
    fail("expected absolute temporary workspace paths")
  }
  let canonical = canonical_path(real_path)
  let linked = canonical_path(link_path)
  let vanished = canonical_path(missing_path)
  @fs.rmdir(dir, recursive=true) catch {
    _ => ()
  }
  assert_eq(linked, canonical)
  assert_eq(vanished.0, missing.to_string())
}

///|
pub extend WorkspaceError with Debug::{to_repr}
