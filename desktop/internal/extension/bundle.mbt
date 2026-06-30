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
/// The script tag the bundled `index.html` uses to pull in the JS bundle. It is
/// replaced with the inlined bundle so the document is self-contained.
const FrontendScriptTag = "<script src=\"./frontend.js\"></script>"

///|
/// The frontend bundle's filename, a sibling of the entry HTML.
const FrontendBundleName = "frontend.js"

///|
/// Build the self-contained HTML document handed to proton's `html()` entry:
/// the bundled `index.html` with its `<script src="./frontend.js">` reference
/// replaced by the inlined bundle. Proton serves the document from
/// `proton://app/` (the origin its `__MoonBit__` bridge reaches), while the
/// native resource handler serves sibling static assets from `frontend_asset_dir`.
/// `entry_path` is the resolved index.html path from `frontend_entry_path`; the
/// bundle is read from its sibling `frontend.js`.
pub async fn frontend_document(entry_path : String) -> String {
  let html = @fs.read_file(entry_path).text()
  let bundle_path = @path.Path(entry_path)
    .dirname()
    .join(FrontendBundleName)
    .to_string()
  let bundle = @fs.read_file(bundle_path).text()
  // Neutralize any literal `</script` in the bundle so it cannot close the
  // inlined tag early; the browser unescapes `<\/script` back to the same text.
  let inlined = bundle.replace_all(old="</script", new="<\\/script")
  html.replace(
    old=FrontendScriptTag,
    new="<script>\n" + inlined + "\n</script>",
  )
}
