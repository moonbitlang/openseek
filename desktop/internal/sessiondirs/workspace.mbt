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
pub async fn session_workspace_dir(session : String) -> @path.Path? {
  guard safe_workspace_id(session) else { return None }
  guard workspace_root() is Some(root) else { return None }
  Some(root.join(session).normalize())
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
