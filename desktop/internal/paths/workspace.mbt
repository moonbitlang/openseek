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
pub fn session_workspace_dir(session : String) -> String? {
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
fn workspace_root() -> String? {
  guard home_dir() is Some(home) else { return None }
  let home_path : @mbpath.Path = home
  let documents : @mbpath.Path = match xdg_documents_dir(home) {
    Some(dir) => dir
    None => home_path.join("Documents")
  }
  let documents_exists = @mbfs.is_dir(documents.to_string()) catch {
    _ => false
  }
  let parent = if documents_exists { documents } else { home_path }
  Some(parent.join(WorkspaceDirName).normalize().to_string())
}

///|
/// The XDG user-dirs override for the Documents folder, read from
/// `${XDG_CONFIG_HOME:-~/.config}/user-dirs.dirs` (Linux desktops localize
/// or move Documents there; the file does not exist on macOS or Windows).
/// The spec marks a disabled folder by pointing it at `$HOME` itself, which
/// `workspace_root` then resolves to `~/OpenSeek` naturally.
fn xdg_documents_dir(home : String) -> String? {
  let config_dir = match non_empty(@env.get_env_var("XDG_CONFIG_HOME")) {
    Some(dir) => dir
    None => (home : @mbpath.Path).join(".config").to_string()
  }
  let file = (config_dir : @mbpath.Path).join("user-dirs.dirs").to_string()
  let content = @mbfs.read_file_to_string(file) catch { _ => return None }
  for line in content.split("\n") {
    let line = line.trim()
    guard line.has_prefix("XDG_DOCUMENTS_DIR=") else { continue }
    let value = line["XDG_DOCUMENTS_DIR=".length():].trim(chars="\"")
    if value.has_prefix("$HOME") {
      return Some(home + value["$HOME".length():].to_owned())
    }
    return Some(value.to_owned())
  }
  None
}
