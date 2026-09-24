// One file location for Desktop language operations. The frontend supplies
// the exact editor root and a path relative to it; the host keeps both the
// lexical spelling used by Viewer resources and the physical spelling used
// to contain symlinks before invoking MoonBit tooling.

///|
priv struct LanguagePath {
  lexical_root : @pathx.Absolute
  physical_root : @pathx.Absolute
  physical_relative : @pathx.Relative
}

///|
/// Confirm that an explicit editor root is the checkout currently owned by
/// `session`. Keep `root` in its frontend resource form for the authorization
/// lookup: on Windows, converting `/C:/work` to `C:\work` first would make the
/// registered-workspace lookup reject the fresh conversation's first request.
/// The registry may return a canonical spelling with different case or after
/// resolving a junction, so compare physical directory identity while keeping
/// the client's lexical root for Viewer resources.
async fn LanguagePath::authorized_root(
  session : String,
  root : String,
) -> @pathx.Absolute {
  guard @pathx.Absolute::from_uri_path(root) is Some(lexical_root) else {
    raise PayloadError("root must be absolute")
  }
  let lexical_root = lexical_root.normalize()
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
    raise HostError("root has no directory ownership for this conversation")
  }
  let requested_physical = @fs.realpath(lexical_root.to_string()) catch {
    _ => raise HostError("requested language root is unavailable")
  }
  let authorized_physical = @fs.realpath(authorized.to_string()) catch {
    _ => raise HostError("authorized language root is unavailable")
  }
  guard @pathx.Path(requested_physical).to_absolute()
    is Some(requested_physical) &&
    @pathx.Path(authorized_physical).to_absolute() is Some(authorized_physical) &&
    requested_physical.relative_to(root=authorized_physical) is Some(relative) &&
    relative.is_root() else {
    @xlog.warn(category="language") <?
      {
        "event": "language_root_ownership_mismatch",
        "session": session,
        "requested_root": requested_physical,
        "authorized_root": authorized_physical,
      }
    raise HostError("root does not match the conversation checkout")
  }
  lexical_root
}

///|
/// Resolve one host-authorized editor root and relative file path. The
/// physical containment check also rejects a symlink target leaving it.
async fn LanguagePath::resolve(
  session : String,
  root : String,
  path : String,
) -> LanguagePath {
  let lexical_root = LanguagePath::authorized_root(session, root)
  guard @pathx.Path(path).to_absolute() is None else {
    raise PayloadError("path must be relative to root")
  }
  let relative = @pathx.Relative(path).normalize()
  guard !relative.is_root() else {
    raise PayloadError("path must name a file below root")
  }
  let lexical_file = lexical_root.join(relative).normalize()
  guard lexical_root.contains(lexical_file) else {
    raise HostError("path is outside root")
  }
  let physical_root_text = @fs.realpath(lexical_root.to_string()) catch {
    _ => raise HostError("root is unavailable")
  }
  let physical_file_text = @fs.realpath(lexical_file.to_string()) catch {
    _ => raise HostError("path is unavailable")
  }
  guard @pathx.Path(physical_root_text).to_absolute() is Some(physical_root) &&
    @pathx.Path(physical_file_text).to_absolute() is Some(physical_file) else {
    raise HostError("root or path is not a host absolute path")
  }
  guard physical_file.relative_to(root=physical_root) is Some(physical_relative) &&
    !physical_relative.is_root() else {
    raise HostError("path is outside root")
  }
  { lexical_root, physical_root, physical_relative, }
}
