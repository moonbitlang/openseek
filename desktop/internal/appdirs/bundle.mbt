///|
const FrontendEntryPath = "assets/index.html"

///|
const DefaultEngine = "openseek"

///|
/// Locate the bundled frontend entry relative to the executable. On macOS
/// the assets live in `Contents/Resources/` — `Contents/MacOS/` may only
/// hold code, since non-`--deep` codesigning rejects data files there — so
/// probe `../Resources/` first; the executable-adjacent layout serves the
/// Linux AppImage and bare dev builds. Falls back to a cwd-relative path
/// for `moon run` during development.
pub async fn frontend_entry_path(framework_command : String) -> String {
  let command_dir = @mbpath.Path(framework_command).dirname().resolve()
  let candidates = [
    command_dir.join("..").join("Resources").join(FrontendEntryPath),
    command_dir.join(FrontendEntryPath),
  ]
  for candidate in candidates {
    let path = candidate.normalize().to_string()
    if @mbfs.exists(path) {
      return path
    }
  }
  FrontendEntryPath
}

///|
async fn bundled_engine_path(framework_command : String) -> String? {
  let command_path : @mbpath.Path = framework_command
  let command_dir = command_path.dirname().resolve()
  let candidates = match @env.get("OS") {
    Some("Windows_NT") => ["openseek.exe", "openseek"]
    _ => ["openseek", "openseek.exe"]
  }
  for candidate in candidates {
    let path = command_dir.join(candidate).normalize().to_string()
    if @mbfs.exists(path) {
      return Some(path)
    }
  }
  None
}

///|
/// The engine executable to run: the one bundled beside the host binary, or
/// the `OPENSEEK_ENGINE` override, or `openseek` on PATH.
pub async fn engine_command(framework_command : String) -> String {
  if bundled_engine_path(framework_command) is Some(path) {
    return path
  }
  @env.get("OPENSEEK_ENGINE").unwrap_or(DefaultEngine)
}
