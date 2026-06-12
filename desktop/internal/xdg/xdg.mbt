// The slice of the XDG conventions the app actually consults: the user-dirs
// override that tells a Linux desktop where the Documents folder lives.

///|
/// The XDG user-dirs override for the Documents folder, read from
/// `${XDG_CONFIG_HOME:-~/.config}/user-dirs.dirs` (Linux desktops localize
/// or move Documents there; the file does not exist on macOS or Windows).
/// `None` when there is no override. The spec marks a disabled folder by
/// pointing it at `$HOME` itself, which callers should treat as their
/// home-directory fallback.
pub async fn documents_dir() -> String? {
  guard @home.dir() is Some(home) else { return None }
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
