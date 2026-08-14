// Turning a transcript-referenced path into the absolute path to open. No
// containment is applied: the agent surfaced the path and the user clicked it,
// so an absolute path opens directly and a relative one is taken against the
// conversation's working directory.

///|
/// The path to open for `path`. An absolute `path` is returned normalized; a
/// relative one is joined onto `cwd` (the conversation's working directory).
/// When `cwd` is unknown, a relative path is returned unchanged, leaving the
/// opener to resolve it against the host process's own directory.
pub fn open_target(cwd : @pathx.Absolute?, path : @pathx.Path) -> @pathx.Path {
  if path.to_absolute() is Some(_) {
    path.normalize()
  } else if cwd is Some(cwd) && path.to_relative() is Some(relative) {
    cwd.to_path().join(relative).normalize()
  } else {
    path
  }
}
