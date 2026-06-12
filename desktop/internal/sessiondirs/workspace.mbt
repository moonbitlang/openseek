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
pub async fn session_workspace_dir(session : String) -> String? {
  guard safe_workspace_id(session) else { return None }
  guard workspace_root() is Some(root) else { return None }
  Some((root : @mbpath.Path).join(session).normalize().to_string())
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
/// app data, so it belongs where the user already looks for files. Honours
/// the XDG user-dirs override on Linux (localized or relocated Documents);
/// when no Documents folder exists at all (headless machines, redirected
/// Windows profiles), the folder lives directly under the home directory.
async fn workspace_root() -> String? {
  guard @env.home_dir() is Some(home) else { return None }
  let home_path : @mbpath.Path = home
  let documents : @mbpath.Path = match @xdg.documents_dir(home) {
    Some(dir) => dir
    None => home_path.join("Documents")
  }
  let parent = if is_dir(documents.to_string()) { documents } else { home_path }
  Some(parent.join(WorkspaceDirName).normalize().to_string())
}

///|
/// Whether `path` exists and is a directory; probe failures mean "no".
async fn is_dir(path : String) -> Bool {
  let kind = @fs.kind(path) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  kind is Directory
}
