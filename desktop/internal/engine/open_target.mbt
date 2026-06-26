// Turning a transcript-referenced path into the absolute path to open. No
// containment is applied: the agent surfaced the path and the user clicked it,
// so an absolute path opens directly and a relative one is taken against the
// conversation's working directory.

///|
/// The absolute path to open for `path`. An absolute `path` is returned
/// normalized; a relative one is joined onto `cwd` (the conversation's working
/// directory). When `cwd` is blank — an unknown working directory — a relative
/// path is returned unchanged, leaving the opener to resolve it against the
/// host process's own directory.
pub fn open_target(cwd : String, path : String) -> String {
  let p = @path.Path(path)
  if p.is_absolute() {
    p.normalize().to_string()
  } else if cwd.is_empty() {
    path
  } else {
    @path.Path(cwd).join(p).normalize().to_string()
  }
}
