// The user's per-purpose folders, each answered by its platform's authority.
// Only Documents is consulted today.

///|
#cfg(platform="windows")
extern "C" fn known_folder_documents() -> Bytes = "openseek_desktop_documents_dir"

///|
/// The user's Documents folder — where it is supposed to be, not whether it
/// exists: the Windows known folder (which OneDrive's folder move or group
/// policy may relocate), the XDG user-dirs override on Linux desktops, or
/// `~/Documents`. `None` when no platform authority answers and no home
/// directory is known.
///
/// On Windows, we use `SHGetKnownFolderPath(FOLDERID_Documents)`, the
/// authority on Windows. `None` when the lookup fails — and always off
/// Windows, where the native stub returns empty bytes.
#cfg(platform="windows")
pub async fn documents_dir() -> String? {
  let path = known_folder_documents()
  guard path.length() > 0 else { return None }
  Some(@utf8.decode_lossy(path))
}

///|
#cfg(not(platform="windows"))
pub async fn documents_dir() -> String? {
  guard @home.dir() is Some(home) else { return None }
  if xdg_documents_override(home) is Some(dir) {
    return Some(dir)
  }
  Some(home.join("Documents").normalize().to_string())
}

///|
/// The XDG user-dirs override for the Documents folder, read from
/// `${XDG_CONFIG_HOME:-~/.config}/user-dirs.dirs` (Linux desktops localize
/// or move Documents there; the file does not exist on macOS or Windows).
/// `None` when there is no override. `xdg-user-dirs-update` may reset a removed
/// user dir to `$HOME`; that value resolves to the home directory like any
/// other supported value.
async fn xdg_documents_override(home : @path.Path) -> String? {
  let config_dir = match @env.get("XDG_CONFIG_HOME") {
    Some(dir) => @path.Path(dir)
    None => home.join(".config").to_string()
  }
  let file = config_dir.join("user-dirs.dirs").to_string()
  let content = @fs.read_file(file).text() catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  for line in content.split("\n") {
    if parse_xdg_documents_dir_line(home, line) is Some(dir) {
      return Some(dir.normalize().to_string())
    }
  }
  None
}

///|
fn parse_xdg_documents_dir_line(
  home : @path.Path,
  line : StringView,
) -> @path.Path? {
  guard line.trim().strip_prefix("XDG_DOCUMENTS_DIR=") is Some(value) else {
    return None
  }
  parse_xdg_user_dir_value(home, value)
}

///|
fn parse_xdg_user_dir_value(home : @path.Path, raw : StringView) -> @path.Path? {
  guard unquote_xdg_value(raw.trim()) is Some(value) else { return None }
  if value == "$HOME" {
    return Some(home)
  }
  if value.strip_prefix("$HOME/") is Some(relative) {
    return Some(home.join(relative.to_owned()).normalize())
  }
  let path = @path.Path(value.to_owned())
  if path.is_absolute() {
    Some(path.normalize())
  } else {
    None
  }
}

///|
fn unquote_xdg_value(value : StringView) -> StringView? {
  if value.strip_prefix("\"") is Some(rest) {
    guard rest.strip_suffix("\"") is Some(inner) else { return None }
    guard !inner.contains_char('"') else { return None }
    return Some(inner)
  }
  guard value.strip_suffix("\"") is None else { return None }
  guard !value.contains_char('"') else { return None }
  Some(value)
}
