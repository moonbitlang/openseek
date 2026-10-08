///|
/// Resolve tool paths; only explicit @session paths select session storage.
/// Ordinary relative paths always retain their workspace-relative meaning.
pub async fn resolve(
  workspace_root : String,
  path : String,
  session_dir? : String,
) -> String {
  guard path.has_prefix("@") else {
    return @workspace_path.resolve(workspace_root, path)
  }
  guard path.strip_prefix("@session/") is Some(relative) else {
    fail(
      "unknown file namespace: \{path}; use ./\{path} for a literal workspace path",
    )
  }
  guard session_dir is Some(dir) else {
    fail("@session/ is unavailable in this tool registry")
  }
  guard !relative.contains("\\") &&
    !relative.contains("\u{0}") &&
    !relative.contains(":") &&
    !relative.split("/").any(part => part == "" || part == "." || part == "..") else {
    fail(
      "@session/ requires a file or subdirectory without empty, dot, or parent components",
    )
  }
  let scope = prepare(dir)
  let resolved = "\{scope.root()}/\{relative}"
  if scope.deny_reason(resolved) is Some(reason) {
    fail("invalid @session/ path: \{reason}")
  }
  resolved
}

///|
/// Keep scratch checks active at each tool's existing write/rollback gates.
pub async fn scope(
  workspace_root : String,
  write_scope : @write_scope.WriteScope?,
  session_dir : String?,
) -> @write_scope.WriteScope? {
  match session_dir {
    Some(dir) =>
      Some(@write_scope.with_session(write_scope, prepare(dir), workspace_root))
    None => write_scope
  }
}

///|
/// Whether the caller explicitly selected session storage.
pub fn is_session(path : String) -> Bool {
  path.has_prefix("@session/")
}

///|
async fn prepare(dir : String) -> @write_scope.WriteScope {
  @fs.mkdir(dir, recursive=true, permission=0o700) catch {
    @os_error.OSError(_) as error if error.is_EEXIST() => ()
    error => raise error
  }
  guard @fs.kind(dir, follow_symlink=false) is Directory else {
    fail("session scratch must be a directory, not a symlink")
  }
  match @write_scope.WriteScope::create(root=dir) {
    Ok(scope) => scope
    Err(reason) => fail(reason)
  }
}
