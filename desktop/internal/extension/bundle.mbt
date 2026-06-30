///|
const FrontendEntryPath = "assets/index.html"

///|
/// Locate the bundled frontend entry relative to the executable. On macOS
/// the assets live in `Contents/Resources/` — `Contents/MacOS/` may only
/// hold code, since non-`--deep` codesigning rejects data files there — so
/// probe `../Resources/` first; the executable-adjacent layout serves the
/// Linux AppImage and the Windows bundle. The final cwd-relative fallback only
/// resolves when an `assets/` tree sits in the working directory; the supported
/// development flow runs a packaged bundle, not the bare host binary.
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

///|
/// Return the directory that contains the bundled frontend entry and sibling
/// assets such as `viewer.css`.
pub fn frontend_asset_dir(entry_path : String) -> String {
  @path.Path(entry_path).dirname().to_string()
}

///|
/// Read the HTML document handed to proton's `html()` entry. Proton serves the
/// document from `proton://app/` (the origin its `__MoonBit__` bridge reaches),
/// while the native resource handler serves sibling static assets from
/// `frontend_asset_dir`.
pub async fn frontend_document(entry_path : String) -> String {
  @fs.read_file(entry_path).text()
}
