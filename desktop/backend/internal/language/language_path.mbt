// One file location for Desktop language operations. The frontend supplies
// the exact editor root and a path relative to it; the host keeps both the
// lexical spelling used by Viewer resources and the physical spelling used
// to contain symlinks before invoking MoonBit tooling.

///|
priv struct LanguageRoot {
  lexical : @pathx.Absolute
  physical : @pathx.Absolute
}

///|
priv struct LanguagePath {
  root : LanguageRoot
  physical_relative : @pathx.Relative
}

///|
async fn real_path(path : @pathx.Absolute, subject : String) -> @pathx.Absolute {
  let real = @fs.realpath(path.to_string())
  guard @pathx.Path(real).to_absolute() is Some(real) else {
    raise Unavailable(subject)
  }
  real
}

///|
/// Confirm that an explicit editor root is the checkout currently owned by
/// `session`. Keep `root` in its frontend resource form for the authorization
/// lookup: on Windows, converting `/C:/work` to `C:\work` first would make the
/// registered-workspace lookup reject the fresh conversation's first request.
/// The registry may return a canonical spelling with different case or after
/// resolving a junction, so compare physical directory identity while keeping
/// the client's lexical root for Viewer resources.
async fn LanguageRoot::authorize(
  session : String,
  root : String,
) -> LanguageRoot {
  guard @pathx.Absolute::from_uri_path(root) is Some(lexical) else {
    raise InvalidRequest("root must be absolute")
  }
  let lexical = lexical.normalize()
  let authorized = match
    @work_dir.resolve_in_workspace(session, "", workspace=root) {
    Some(root) => Some(root)
    None => @work_dir.resolve_in_workspace(session, "")
  }
  guard authorized is Some(authorized) else {
    @xlog.warn(category="language") <?
      {
        "event": "language_root_ownership_missing",
        "session": session,
        "requested_root": root,
      }
    raise RootNotOwned
  }
  let physical = real_path(lexical, "requested language root")
  let authorized = real_path(authorized, "authorized language root")
  guard physical.relative_to(root=authorized) is Some(relative) &&
    relative.is_root() else {
    @xlog.warn(category="language") <?
      {
        "event": "language_root_ownership_mismatch",
        "session": session,
        "requested_root": physical.to_string(),
        "authorized_root": authorized.to_string(),
      }
    raise RootMismatch
  }
  { lexical, physical, }
}

///|
/// Resolve one host-authorized editor root and relative file path. The
/// physical containment check also rejects a symlink target leaving it.
async fn LanguagePath::resolve(
  session : String,
  root : String,
  path : String,
) -> LanguagePath {
  let root = LanguageRoot::authorize(session, root)
  guard @pathx.Path(path).to_absolute() is None else {
    raise InvalidRequest("path must be relative to root")
  }
  let relative = @pathx.Relative(path).normalize()
  guard !relative.is_root() else {
    raise InvalidRequest("path must name a file below root")
  }
  let lexical_file = root.lexical.join(relative).normalize()
  guard root.lexical.contains(lexical_file) else { raise PathOutsideRoot }
  let physical_file = real_path(lexical_file, "path")
  guard physical_file.relative_to(root=root.physical) is Some(physical_relative) &&
    !physical_relative.is_root() else {
    raise PathOutsideRoot
  }
  { root, physical_relative, }
}
