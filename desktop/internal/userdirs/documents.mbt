// The user's per-purpose folders, each answered by its platform's authority.
// Only Documents is consulted today.

///|
extern "C" fn known_folder_documents() -> Bytes = "openseek_desktop_documents_dir"

///|
/// The user's Documents folder — where it is supposed to be, not whether it
/// exists: the Windows known folder (which OneDrive's folder move or group
/// policy may relocate), the XDG user-dirs override on Linux desktops, or
/// `~/Documents`. `None` when no platform authority answers and no home
/// directory is known.
pub async fn documents_dir() -> String? {
  if @env.get("OS") is Some("Windows_NT") &&
    windows_documents_dir() is Some(dir) {
    return Some(dir)
  }
  guard @home.dir() is Some(home) else { return None }
  if xdg_documents_override(home) is Some(dir) {
    return Some(dir)
  }
  Some((home : @mbpath.Path).join("Documents").normalize().to_string())
}

///|
/// `SHGetKnownFolderPath(FOLDERID_Documents)`, the authority on Windows.
/// `None` when the lookup fails — and always off Windows, where the native
/// stub returns empty bytes.
fn windows_documents_dir() -> String? {
  let path = known_folder_documents()
  guard path.length() > 0 else { return None }
  Some(@utf8.decode_lossy(path))
}

///|
/// The XDG user-dirs override for the Documents folder, read from
/// `${XDG_CONFIG_HOME:-~/.config}/user-dirs.dirs` (Linux desktops localize
/// or move Documents there; the file does not exist on macOS or Windows).
/// `None` when there is no override. The spec marks a disabled folder by
/// pointing it at `$HOME` itself, which resolves to the home directory like
/// any other value.
async fn xdg_documents_override(home : String) -> String? {
  let config_dir = match @env.get("XDG_CONFIG_HOME") {
    Some(dir) => dir
    None => (home : @mbpath.Path).join(".config").to_string()
  }
  let file = (config_dir : @mbpath.Path).join("user-dirs.dirs").to_string()
  let content = @fs.read_file(file).text() catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
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
