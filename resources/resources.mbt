///|
/// Locate this program's bundled resources at `../share` relative to its
/// real executable directory, following launcher symlinks. Native programs and
/// file-backed Wasm modules use the same installation layout; neither cwd nor
/// environment selects resources.
///
/// A missing directory means this installation has no bundled resources.
/// Other filesystem failures, an invalid layout, and executable lookup errors
/// propagate so callers do not misreport inaccessible resources as absent.
pub async fn directory() -> String? {
  // Some platforms preserve the launcher's symlink spelling. Resolve the
  // executable itself before taking its parent, so links in PATH do not
  // redirect resource lookup to an unrelated installation.
  let directory = @path.Path(@fs.realpath(@exe.current_exe()))
    .dirname()
    .join(Path("../share"))
    .normalize()
    .to_string()
  let kind = @fs.kind(directory) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => return None
    error => raise error
  }
  guard kind is Directory else {
    fail("bundled resources path is not a directory: \{directory}")
  }
  Some(@fs.realpath(directory))
}
