///|
const FrontendEntryPath = "assets/index.html"

///|
/// Locate the bundled frontend entry relative to the executable. On macOS
/// the assets live in `Contents/Resources/` — `Contents/MacOS/` may only
/// hold code, since non-`--deep` codesigning rejects data files there — so
/// probe `../Resources/` first; the executable-adjacent layout serves the
/// Linux AppImage and bare dev builds. Falls back to a cwd-relative path
/// for `moon run` during development.
pub async fn frontend_entry_path(framework_command : String) -> String {
  let command_dir = @path.Path(framework_command).dirname().resolve()
  let candidates = [
    command_dir.join("..").join("Resources").join(FrontendEntryPath),
    command_dir.join(FrontendEntryPath),
  ]
  for candidate in candidates {
    let path = candidate.normalize().to_string()
    if @fs.exists(path) {
      return path
    }
  }
  FrontendEntryPath
}
