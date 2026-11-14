// One file location for Desktop language operations. The frontend supplies
// the editor root and a workspace-relative or standard-library path. The host
// keeps the lexical spelling used by Viewer resources and the physical spelling
// to contain symlinks before invoking MoonBit tooling.

///|
priv struct LanguageRoot {
  lexical : @pathx.Absolute
  physical : @pathx.Absolute
}

///|
priv struct LanguagePath {
  root : LanguageRoot
  file : @pathx.Absolute
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
  let lexical = @pathx.Absolute::parse_resource_path(root)
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
/// Standard-library authority comes from the selected executable's toolchain.
async fn toolchain_stdlib_root(
  toolchain : @moonbit.ResolvedToolchain,
) -> @pathx.Absolute? {
  @pathx.Path(@fs.realpath(toolchain.bin_dir.join("../lib/core").to_string())).to_absolute() catch {
    _ => None
  }
}

///|
/// Keep existing workspace command arguments relative; standard-library
/// queries use a canonical absolute target with the same project cwd.
fn LanguagePath::cli_path(self : LanguagePath) -> String {
  self.file
  .relative_to(root=self.root.physical)
  .map_or(self.file.to_string(), relative => relative.0)
}

///|
fn LanguagePath::source_file(self : LanguagePath) -> @pathx.Absolute {
  self.file
  .relative_to(root=self.root.physical)
  .map_or(self.file, relative => self.root.lexical.join(relative))
}

///|
/// Authorize the project independently of the target. Existing relative paths
/// stay inside the workspace; absolute targets must belong to this toolchain's
/// canonical standard library, including after following symlinks.
async fn LanguagePath::resolve(
  session : String,
  root : String,
  path : String,
  stdlib_root? : @pathx.Absolute,
) -> LanguagePath {
  let root = LanguageRoot::authorize(session, root)
  if path.has_prefix("/") {
    guard stdlib_root is Some(stdlib) else { raise PathOutsideRoot }
    let file = real_path(@pathx.Absolute::parse_resource_path(path), "path")
    guard file.relative_to(root=stdlib) is Some(relative) && !relative.is_root() else {
      raise PathOutsideRoot
    }
    return { root, file, }
  }
  guard @pathx.Path(path).to_absolute() is None else {
    raise InvalidRequest("path must be relative to root")
  }
  let relative = @pathx.Relative(path).normalize()
  guard !relative.is_root() else {
    raise InvalidRequest("path must name a file below root")
  }
  let lexical_file = root.lexical.join(relative).normalize()
  guard root.lexical.contains(lexical_file) else { raise PathOutsideRoot }
  let file = real_path(lexical_file, "path")
  guard file.relative_to(root=root.physical) is Some(relative) &&
    !relative.is_root() else {
    raise PathOutsideRoot
  }
  { root, file, }
}
