// Where a conversation works: the per-session workspace directory the engine
// runs in.

///|
const WorkspaceDirName = "OpenSeek"

///|
/// Per-conversation workspace directory. A conversation whose durable record
/// lives inside a registered workspace works in that project directory; a
/// scratch conversation gets `<workspace root>/<session id>`, flat — desktop
/// ids embed their creation date, so a name-sorted listing is already
/// chronological without a grouping level. Either way the directory follows
/// from the session id and what's on disk, so resuming a conversation — even
/// from a fresh app launch — lands in the same directory without recording it
/// anywhere. `None` when the id is unsafe as a path component or no home
/// directory is known; the caller falls back to the home directory.
async fn session_workspace_dir(session : String) -> @path.Path? {
  if workspace_of_session(session) is Some(workspace) {
    return Some(workspace)
  }
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
/// `relative` and (optionally) a `workspace` hint — honored only when the
/// path is a registered workspace, covering a fresh workspace conversation
/// whose durable record does not exist on disk yet. Deriving the root
/// host-side keeps the trust boundary here: a crafted `..` path or workspace
/// cannot reach outside directories the user attached.
pub async fn resolve_in_workspace(
  session : String,
  relative : String,
  workspace? : String,
) -> @path.Path? {
  let root = if workspace is Some(hint) &&
    registered_workspace(hint) is Some(dir) {
    Some(dir)
  } else {
    session_workspace_dir(session)
  }
  guard root is Some(root) else { return None }
  guard contained_path(root, relative) is Some(resolved) else { return None }
  // The lexical containment above stops `..` traversal but not a symlink inside
  // the workspace pointing outside it; reject one whose real target escapes.
  guard real_contains(root.to_string(), resolved.to_string()) else {
    return None
  }
  Some(resolved)
}

///|
/// Whether `path`'s real location — following symlinks — is `boundary` or lives
/// under it. The lexical `contained_path` / `@pathx.contains` checks resolve
/// `..` but not symlinks, so a link inside the boundary can still point out;
/// this canonicalizes both ends and re-checks. When either cannot be resolved —
/// most often the target does not exist, so there is no symlink to follow and
/// no file to leak — it trusts the lexical result already established.
async fn real_contains(boundary : String, path : String) -> Bool {
  let real_boundary = @fs.realpath(boundary) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return true
  }
  let real_path = @fs.realpath(path) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return true
  }
  @pathx.contains(real_boundary, real_path)
}

///|
/// The workspace directory an absolute `path` belongs to: the deepest
/// registered workspace containing it (the nested-roots convention language
/// clients use — VS Code's `getWorkspaceFolder` picks the innermost folder),
/// or — under the scratch-workspace root — the per-session directory that
/// owns it. `None` for a relative path or anything outside, which ops routed
/// by path alone must refuse.
pub async fn attached_workspace_dir(path : String) -> @path.Path? {
  let candidate : @path.Path = Path(path)
  guard candidate.is_absolute() else { return None }
  let resolved = candidate.normalize().to_string()
  let mut best : String? = None
  for workspace in registered_workspaces() {
    guard @pathx.contains(workspace, resolved) else { continue }
    if best is Some(current) && current.length() >= workspace.length() {
      continue
    }
    best = Some(workspace)
  }
  let dir : @path.Path = if best is Some(workspace) {
    Path(workspace)
  } else {
    guard workspace_root() is Some(root) else { return None }
    guard @pathx.relative_to(resolved, root=root.to_string()) is Some(rest) &&
      !rest.is_empty() else {
      return None
    }
    // The first segment under the scratch root names the owning session's
    // directory; the root itself belongs to no conversation.
    let session = match rest.find("/") {
      Some(index) => rest.view(end_offset=index).to_owned()
      None => rest
    }
    root.join(Path(session)).normalize()
  }
  // Reject an absolute path whose real target — following symlinks — escapes
  // the owning directory; the lexical containment above does not follow links.
  guard real_contains(dir.to_string(), resolved) else { return None }
  Some(dir)
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
