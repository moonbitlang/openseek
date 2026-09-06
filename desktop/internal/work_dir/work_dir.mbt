// Where a conversation works: the registered workspace directory the engine
// runs in.

///|
/// Exact session-to-directory bindings learned from a host-owned source such
/// as Codex app-server. Unlike the persisted OpenSeek workspace registry,
/// these grants live only for this process and authorize only one session id;
/// a web client cannot turn an arbitrary workspace hint into filesystem access.
priv struct HostWorkspaceAuthorizations {
  lock : @async.Mutex
  paths : Map[String, String]
}

///|
let host_workspace_authorizations : HostWorkspaceAuthorizations = {
  lock: Mutex(),
  paths: Map([]),
}

///|
/// Replace `session`'s process-local authorization with one normalized absolute
/// directory. Invalid bindings remove the old grant instead of preserving a
/// stale cwd after the authoritative source stopped supplying one.
async fn HostWorkspaceAuthorizations::authorize(
  self : HostWorkspaceAuthorizations,
  session : String,
  workspace : String,
) -> Unit {
  let trimmed = workspace.trim().to_owned()
  let candidate = @pathx.Path(trimmed).normalize().to_absolute()
  self.lock.acquire()
  defer self.lock.release()
  if @session_store.safe_session_id(session) && candidate is Some(candidate) {
    self.paths[session] = candidate.0
  } else {
    self.paths.remove(session)
  }
}

///|
async fn HostWorkspaceAuthorizations::revoke(
  self : HostWorkspaceAuthorizations,
  session : String,
) -> Unit {
  self.lock.acquire()
  defer self.lock.release()
  self.paths.remove(session)
}

///|
/// Accept `hint` only when it is the exact normalized directory previously
/// authorized for `session`; the caller still applies relative-path and real
/// symlink containment before touching the filesystem.
async fn HostWorkspaceAuthorizations::resolve(
  self : HostWorkspaceAuthorizations,
  session : String,
  hint : @pathx.Absolute,
) -> @pathx.Path? {
  let normalized = hint.normalize()
  self.lock.acquire()
  defer self.lock.release()
  if self.paths.get(session) == Some(normalized.0) {
    Some(normalized.to_path())
  } else {
    None
  }
}

///|
/// Record an exact workspace binding obtained by the native host from an
/// authoritative subsystem. This is intentionally not a client-facing op and
/// does not add the directory to OpenSeek's persisted workspace sidebar.
pub async fn authorize_host_workspace(
  session : String,
  workspace : String,
) -> Unit {
  host_workspace_authorizations.authorize(session, workspace)
}

///|
/// Remove a process-local workspace binding when its authoritative task is no
/// longer available.
pub async fn revoke_host_workspace(session : String) -> Unit {
  host_workspace_authorizations.revoke(session)
}

///|
/// Read only the exact process-local grant established by an authoritative
/// native subsystem. Unlike `resolve_in_workspace`, this does not let a safe
/// session id select any registered OpenSeek project; draft and turn mutation
/// endpoints use it to verify the cwd they previously authorized themselves.
pub async fn resolve_host_workspace_authorization(
  session : String,
  workspace : String,
) -> @pathx.Absolute? {
  guard @pathx.Absolute::from_uri_path(workspace) is Some(requested) &&
    host_workspace_authorizations.resolve(session, requested)
    is Some(authorized) else {
    return None
  }
  authorized.to_absolute()
}

///|
/// Per-conversation workspace directory: the registered workspace whose
/// durable store holds this session's record. The directory follows from the
/// session id and what's on disk, so resuming a conversation — even from a
/// fresh app launch — lands in the same directory without recording it
/// anywhere. `None` when no registered workspace claims the session or a
/// bound checkout is missing. Callers reject every unavailable root instead
/// of moving the run elsewhere.
pub async fn of_session(session : String) -> @pathx.Path? {
  guard @session_store.workspace_of(session) is Some(workspace) else {
    return None
  }
  // A session bound to one of the workspace's worktrees works in that
  // checkout while it exists. A retained binding whose checkout is missing
  // refuses every workspace operation until the user rebuilds it.
  @worktree.tree_dir(workspace, session).map(dir => dir.to_path())
}

///|
/// The directory a conversation's engine runs in — the base for resolving a
/// relative transcript path to open. `None` when the id is unsafe, no home
/// directory is known, or a bound checkout is missing. A pure function of the
/// session id, so it answers even for a resumed conversation the frontend
/// loaded without a live `cwd`.
pub async fn session_cwd(session : String) -> @pathx.Absolute? {
  guard of_session(session) is Some(dir) else { return None }
  // `session_workspace_dir` is assembled from the absolute home directory.
  // Keep the validation here so that callers never regain the old `""`
  // sentinel or an unclassified string.
  dir.to_absolute()
}

///|
/// The recorded task base for a conversation-bound worktree. The optional
/// workspace hint follows `resolve_in_workspace`'s trust boundary: only an
/// attached workspace is considered, while a resumed conversation can recover
/// its owner from the durable session record. `None` is a conversation working
/// in the workspace root, which has no recorded base; the Git host may derive
/// its branch fork point when committed work exists.
pub async fn session_review_base(
  session : String,
  workspace? : String,
) -> String? {
  let workspace = if workspace is Some(hint) &&
    @pathx.Absolute::from_uri_path(hint) is Some(hint) &&
    @workspaces.registered_dir(hint) is Some(workspace) {
    Some(workspace)
  } else {
    @session_store.workspace_of(session)
  }
  guard workspace is Some(workspace) else { return None }
  @worktree.tree_base(workspace, session)
}

///|
/// Resolve a workspace-relative `relative` against the session's workspace
/// directory, returning the absolute path or `None` when the session id is
/// unsafe or `relative` would escape the workspace. The client supplies only
/// `relative` and (optionally) a `workspace` hint — honored only when the
/// path is a registered workspace, covering a fresh workspace conversation
/// whose durable record does not exist on disk yet. Deriving the root
/// host-side keeps the trust boundary here: a crafted `..` path or workspace
/// cannot reach outside directories the user attached.
pub async fn resolve_in_workspace(
  session : String,
  relative : String,
  workspace? : String,
) -> @pathx.Absolute? {
  let root = match workspace {
    Some(hint) if @pathx.Absolute::from_uri_path(hint) is Some(hint) =>
      match @workspaces.registered_dir(hint) {
        // The hint names the workspace; a session bound to one of its
        // worktrees still roots in that checkout. A Codex thread instead
        // supplies an exact process-local cwd authorized by app-server.
        Some(dir) =>
          @worktree.tree_dir(dir, session).map(root => root.to_path())
        None => host_workspace_authorizations.resolve(session, hint)
      }
    Some(_) => None
    None => of_session(session)
  }
  guard root is Some(root) else { return None }
  guard root.to_absolute() is Some(root) else { return None }
  // The protocol supplies text. Reject a complete absolute spelling before
  // classifying the remainder as workspace-relative host state.
  guard @pathx.Path(relative).to_absolute() is None else { return None }
  let relative = @pathx.Relative(relative).normalize()
  guard contained_path(root, relative) is Some(resolved) else { return None }
  // The lexical containment above stops `..` traversal but not a symlink inside
  // the workspace pointing outside it; reject one whose real target escapes.
  guard real_contains(root, resolved) else { return None }
  Some(resolved)
}

///|
/// Whether `path`'s real location — following symlinks — is `boundary` or lives
/// under it. The lexical `contained_path` / `Absolute::contains` checks resolve
/// `..` but not symlinks, so a link inside the boundary can still point out;
/// this canonicalizes both ends and re-checks. When either cannot be resolved —
/// most often the target does not exist, so there is no symlink to follow and
/// no file to leak — it trusts the lexical result already established.
async fn real_contains(
  boundary : @pathx.Absolute,
  path : @pathx.Absolute,
) -> Bool {
  let real_boundary = @fs.realpath(boundary.0) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return true
  }
  let real_path = @fs.realpath(path.0) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return true
  }
  guard @pathx.Path(real_boundary).to_absolute() is Some(real_boundary) else {
    return true
  }
  guard @pathx.Path(real_path).to_absolute() is Some(real_path) else {
    return true
  }
  real_boundary.contains(real_path)
}

///|
/// The workspace directory an absolute `path` belongs to: the deepest
/// registered workspace containing it (the nested-roots convention language
/// clients use — VS Code's `getWorkspaceFolder` picks the innermost folder).
/// `None` for a relative path or anything outside every registered
/// workspace, which ops routed by path alone must refuse.
pub async fn attached_workspace_dir(path : @pathx.Absolute) -> @pathx.Absolute? {
  // LSP/navigation paths may contain `.` or `..`. Clean them with the host's
  // filesystem rules before selecting the deepest workspace or worktree, so
  // equivalent spellings are classified by their actual lexical location.
  guard path.to_path().normalize().to_absolute() is Some(resolved_absolute) else {
    return None
  }
  let mut best : @pathx.Absolute? = None
  for workspace in @workspaces.registered() {
    guard workspace.contains(resolved_absolute) else { continue }
    if best is Some(current) && current.0.length() >= workspace.0.length() {
      continue
    }
    best = Some(workspace)
  }
  guard best is Some(workspace) else { return None }
  // A path under a registered worktree belongs to that checkout, not the
  // workspace root: language ops routed by path alone must answer from the
  // worktree's own tree. An unregistered `.worktrees` path (a worker
  // slice) keeps resolving to the workspace root.
  let dir = @worktree.owner_dir(workspace, resolved_absolute)
  // Reject an absolute path whose real target — following symlinks — escapes
  // the owning directory; the lexical containment above does not follow links.
  guard real_contains(dir, resolved_absolute) else { return None }
  Some(dir)
}

///|
/// Join `relative` onto `root` and return the absolute result only while it
/// stays within `root`. An absolute or `..`-laden `relative` that climbs out
/// of `root` yields `None`. Pure and root-relative, so the containment rule is
/// unit-testable without a real workspace.
fn contained_path(
  root : @pathx.Absolute,
  relative : @pathx.Relative,
) -> @pathx.Absolute? {
  guard relative.to_path().to_absolute() is None else { return None }
  let resolved = root.join(relative).normalize()
  guard root.contains(resolved) else { return None }
  Some(resolved)
}

// Tests for the pure open-target rule. The full `of_session` chain depends on
// the registry and on what is on disk, and is covered by the live app.

///|
test "absolute paths open as themselves" {
  guard @pathx.Path("/home/u/repo").to_absolute() is Some(cwd) else {
    fail("expected an absolute working-directory fixture")
  }
  assert_true(open_target(Some(cwd), Path("/etc/hosts")) == Path("/etc/hosts"))
  // Normalized, but never re-rooted into the working directory.
  assert_true(open_target(Some(cwd), Path("/a/b/../c.mbt")) == Path("/a/c.mbt"))
}

///|
test "relative paths are taken against the working directory" {
  guard @pathx.Path("/home/u/repo").to_absolute() is Some(cwd) else {
    fail("expected an absolute working-directory fixture")
  }
  assert_true(
    open_target(Some(cwd), Path("core/builtin/array.mbt")) ==
    Path("/home/u/repo/core/builtin/array.mbt"),
  )
  assert_true(
    open_target(Some(cwd), Path("./main.mbt")) == Path("/home/u/repo/main.mbt"),
  )
}

///|
test "a relative path with no working directory is left untouched" {
  assert_true(
    open_target(None, Path("core/builtin/array.mbt")) ==
    Path("core/builtin/array.mbt"),
  )
  assert_true(open_target(None, Path("")) == Path(""))
}

///|
/// The containment rule the FS bridge ops rely on: in-tree relatives resolve
/// against the root, while anything climbing out — `..` segments or an
/// absolute path — is rejected. This is the security boundary for browsing a
/// conversation's workspace from the webview, so pin it directly.
test "contained_path keeps in-tree relatives and rejects escapes" {
  guard @pathx.Path("/home/u/OpenSeek/sess").to_absolute() is Some(root) else {
    fail("expected an absolute workspace fixture")
  }
  guard contained_path(root, @pathx.Relative::root()) is Some(root_path) &&
    contained_path(root, Relative("src/main.mbt")) is Some(file_path) &&
    contained_path(root, Relative("./a/../b")) is Some(normalized) else {
    fail("expected contained fixture paths")
  }
  assert_eq(root_path.0, "/home/u/OpenSeek/sess")
  assert_eq(file_path.0, "/home/u/OpenSeek/sess/src/main.mbt")
  assert_eq(normalized.0, "/home/u/OpenSeek/sess/b")
  assert_true(contained_path(root, Relative("..")) is None)
  assert_true(contained_path(root, Relative("../sibling")) is None)
  assert_true(contained_path(root, Relative("../../etc/passwd")) is None)
  assert_true(contained_path(root, Relative("/etc/passwd")) is None)
  assert_true(contained_path(root, Relative("src/../../escape")) is None)
}

///|
async test "host-authorized workspaces are exact and session-scoped" {
  let root = @fs.tmpdir(prefix="openseek-authorized-workspace-")
  let session = "codex-authorized-workspace-test"
  revoke_host_workspace(session)
  authorize_host_workspace(session, root)
  let exact = resolve_host_workspace_authorization(session, root)
  let authorized = resolve_in_workspace(session, "src/main.mbt", workspace=root)
  let other_session = resolve_in_workspace(
    "codex-other-workspace-test",
    "src/main.mbt",
    workspace=root,
  )
  let escape = resolve_in_workspace(session, "../outside", workspace=root)
  revoke_host_workspace(session)
  let revoked = resolve_in_workspace(session, "", workspace=root)
  let exact_revoked = resolve_host_workspace_authorization(session, root)
  @fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  assert_true(
    authorized is Some(path) &&
    @pathx.Path(root).join(Relative("src/main.mbt")).to_absolute() == Some(path),
  )
  assert_true(other_session is None)
  assert_true(exact is Some(_))
  assert_true(escape is None)
  assert_true(revoked is None)
  assert_true(exact_revoked is None)
}

///|
/// The symlink half of the trust boundary: `contained_path` is purely lexical,
/// so a link *inside* the workspace pointing *outside* it passes that check;
/// `real_contains` follows the link and rejects it. A real in-tree file passes,
/// and a path that does not exist has no link to follow so it is trusted.
async test "real_contains rejects a symlink escaping the boundary" {
  let root = @fs.tmpdir(prefix="openseek-boundary-")
  let outside = @fs.tmpdir(prefix="openseek-outside-")
  // A real file inside the boundary, and a symlink inside the boundary that
  // points at a file outside it (the escape the lexical check misses).
  let inside = "\{root}/inside.txt"
  @fs.write_file(inside, b"x", create_mode=CreateOrTruncate)
  let secret = "\{outside}/secret.txt"
  @fs.write_file(secret, b"s", create_mode=CreateOrTruncate)
  let link = "\{root}/link.txt"
  @fs.symlink(target=secret, link)
  guard @pathx.Path(root).to_absolute() is Some(root_path) &&
    @pathx.Path(inside).to_absolute() is Some(inside_path) &&
    @pathx.Path("\{root}/missing.txt").to_absolute() is Some(missing_path) &&
    @pathx.Path(link).to_absolute() is Some(link_path) else {
    fail("expected absolute temporary paths")
  }
  // Capture the verdicts, then clean up before asserting — `@fs.rmdir` is
  // async so it cannot run in a `defer`, and a failed assertion must not leak
  // the temp trees.
  let inside_ok = real_contains(root_path, inside_path)
  // A path that does not exist is trusted: no link to follow, no file to leak.
  let missing_ok = real_contains(root_path, missing_path)
  let link_escapes = real_contains(root_path, link_path)
  @fs.rmdir(root, recursive=true) catch {
    _ => ()
  }
  @fs.rmdir(outside, recursive=true) catch {
    _ => ()
  }
  assert_true(inside_ok)
  assert_true(missing_ok)
  assert_false(link_escapes)
}
