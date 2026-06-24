// Where a conversation works: the per-session workspace directory the engine
// runs in.

///|
const WorkspaceDirName = "OpenSeek"

///|
/// Per-conversation workspace directory: `<workspace root>/<session id>`,
/// flat — desktop ids embed their creation date, so a name-sorted listing is
/// already chronological without a grouping level. A pure function of the
/// session id, so resuming a conversation — even from a fresh app launch —
/// lands in the same directory without recording it anywhere. `None` when the
/// id is unsafe as a path component or no home directory is known; the caller
/// falls back to the home directory.
async fn session_workspace_dir(session : String) -> @path.Path? {
  guard safe_workspace_id(session) else { return None }
  guard workspace_root() is Some(root) else { return None }
  Some(root.join(session).normalize())
}

///|
/// The directory a conversation's engine runs in, as a string — the base for
/// resolving a relative transcript path to open. `""` when the id is unsafe or
/// no home directory is known. A pure function of the session id, so it answers
/// even for a resumed conversation the frontend loaded without a live `cwd`.
pub async fn session_cwd(session : String) -> String {
  match session_workspace_dir(session) {
    Some(dir) => dir.to_string()
    None => ""
  }
}

///|
/// Resolve a workspace-relative `relative` against the session's workspace
/// directory, returning the absolute path or `None` when the session id is
/// unsafe or `relative` would escape the workspace. The client supplies only
/// `relative`; deriving the root from the session id here keeps the trust
/// boundary in the host, so a crafted `..` path cannot reach outside the
/// conversation's directory.
pub async fn resolve_in_workspace(
  session : String,
  relative : String,
) -> @path.Path? {
  guard session_workspace_dir(session) is Some(root) else { return None }
  contained_path(root, relative)
}

///|
/// Join `relative` onto `root` and return the absolute result only while it
/// stays within `root`. An absolute or `..`-laden `relative` that climbs out
/// of `root` yields `None`. Pure and root-relative, so the containment rule is
/// unit-testable without a real workspace.
fn contained_path(root : @path.Path, relative : String) -> @path.Path? {
  guard !(relative : @path.Path).is_absolute() else { return None }
  let resolved = root.join((relative : @path.Path)).normalize()
  // `relative()` of an escaping path is `..`-prefixed (or absolute); anything
  // else lands inside `root`.
  let rel = resolved.relative(base=root).to_string()
  guard rel != ".." && !rel.has_prefix("../") && !rel.has_prefix("..\\") else {
    return None
  }
  Some(resolved)
}

///|
/// Whether a session id can serve as a single path component under the
/// workspace root. Path separators and dot segments could escape the root —
/// those conversations work in the home directory instead.
fn safe_workspace_id(session : String) -> Bool {
  !session.is_empty() &&
  session != "." &&
  session != ".." &&
  !session.contains("/") &&
  !session.contains("\\")
}

///|
/// Root for per-conversation workspaces: an `OpenSeek` folder inside the
/// user's Documents directory — the agent's output is user-facing work, not
/// app data, so it belongs where the user already looks for files. Where
/// Documents is comes from the platform (`@userdirs.documents_dir`); when
/// that folder does not exist (headless machines, say), the folder lives
/// directly under the home directory.
async fn workspace_root() -> @path.Path? {
  guard @home.dir() is Some(home) else { return None }
  let parent : @path.Path = if @userdirs.documents_dir() is Some(documents) &&
    @fsx.is_dir(documents) {
    documents
  } else {
    home
  }
  Some(parent.join(WorkspaceDirName).normalize())
}
