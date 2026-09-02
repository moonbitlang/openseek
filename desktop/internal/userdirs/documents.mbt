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
///
/// On Windows, we use `SHGetKnownFolderPath(FOLDERID_Documents)`, the
/// authority on Windows. `None` when the lookup fails — and always off
/// Windows, where the native stub returns empty bytes.
pub async fn documents_dir() -> @pathx.Path? {
  if @platform.win32 || @platform.win64 {
    let path = known_folder_documents()
    guard path.length() > 0 else { return None }
    Some(@utf8.decode_lossy(path))
  } else {
    guard @home.dir() is Some(home) else { return None }
    if xdg_documents_override(home) is Some(dir) {
      return Some(dir)
    }
    Some(home.join("Documents").normalize())
  }
}

///|
/// The XDG user-dirs override for the Documents folder, read from
/// `${XDG_CONFIG_HOME:-~/.config}/user-dirs.dirs` (Linux desktops localize
/// or move Documents there; the file does not exist on macOS or Windows).
/// `None` when there is no override. `xdg-user-dirs-update` may reset a removed
/// user dir to `$HOME`; that value resolves to the home directory like any
/// other supported value.
async fn xdg_documents_override(home : @pathx.Path) -> @pathx.Path? {
  let config_dir = if @env.get("XDG_CONFIG_HOME") is Some(dir) {
    @pathx.Path(dir)
  } else {
    home.join(".config")
  }
  let file = config_dir.join("user-dirs.dirs")
  if @fsx.try_read_text(file) is Some(content) {
    for line in content.split("\n") {
      if parse_xdg_documents_dir_line(home, line) is Some(dir) {
        return Some(dir.normalize())
      }
    }
  }
  None
}

///|
fn parse_xdg_documents_dir_line(
  home : @pathx.Path,
  line : StringView,
) -> @pathx.Path? {
  guard line.trim().strip_prefix("XDG_DOCUMENTS_DIR=") is Some(value) else {
    return None
  }
  parse_xdg_user_dir_value(home, value)
}

///|
fn parse_xdg_user_dir_value(
  home : @pathx.Path,
  raw : StringView,
) -> @pathx.Path? {
  guard unquote_xdg_value(raw.trim()) is Some(value) else { return None }
  if value == "$HOME" {
    return Some(home)
  }
  if value.strip_prefix("$HOME/") is Some(relative) {
    return Some(home.join(relative.to_owned()).normalize())
  }
  let path = @pathx.Path(value.to_owned())
  if path.is_host_absolute() {
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

///|
fn parsed_xdg_documents_line(line : String) -> String? {
  parse_xdg_documents_dir_line(Path("/home/u"), line.view()).map(path => {
    path.to_string()
  })
}

///|
#cfg(not(platform="windows"))
test "XDG Documents parser accepts documented home and absolute forms" {
  assert_true(
    parsed_xdg_documents_line("XDG_DOCUMENTS_DIR=\"$HOME/Documents\"")
    is Some("/home/u/Documents"),
  )
  assert_true(
    parsed_xdg_documents_line("  XDG_DOCUMENTS_DIR=$HOME/Documents  ")
    is Some("/home/u/Documents"),
  )
  assert_true(
    parsed_xdg_documents_line("XDG_DOCUMENTS_DIR=\"$HOME\"") is Some("/home/u"),
  )
  assert_true(
    parsed_xdg_documents_line("XDG_DOCUMENTS_DIR=/srv/docs")
    is Some("/srv/docs"),
  )
  assert_true(
    parsed_xdg_documents_line("XDG_DOCUMENTS_DIR=\"/srv/docs\"")
    is Some("/srv/docs"),
  )
}

///|
test "XDG Documents parser rejects malformed and relative values" {
  assert_true(
    parsed_xdg_documents_line("XDG_DOWNLOAD_DIR=\"$HOME/Downloads\"") is None,
  )
  assert_true(parsed_xdg_documents_line("XDG_DOCUMENTS_DIR=$HOMEfoo") is None)
  assert_true(parsed_xdg_documents_line("XDG_DOCUMENTS_DIR=Documents") is None)
  assert_true(
    parsed_xdg_documents_line("XDG_DOCUMENTS_DIR=\"$HOME/Documents") is None,
  )
  assert_true(
    parsed_xdg_documents_line("XDG_DOCUMENTS_DIR=$HOME/Documents\"") is None,
  )
  assert_true(
    parsed_xdg_documents_line("XDG_DOCUMENTS_DIR=\"$HOME/Doc\"uments\"") is None,
  )
}
