// Where a conversation's durable record lives. Every store the desktop can
// reach — the global Scratch root and one `.openseek` per attached workspace —
// has the engine CLI's own layout: live records under `sessions/<id>`, archived
// ones under `archived/sessions/<id>`, and records condemned by a committed
// deletion under `archived/deleting/<id>`.
//
// Nothing here moves a record or decides policy; it answers where things are.
// A session id alone says nothing about which store owns it, so every lookup
// searches the stores rather than trusting a request hint.

///|
/// Debug is what the host boundary logs: proton renders a failed handler's
/// error through `Repr`, which prints only an opaque `<...: ...>` placeholder
/// for types without it — swallowing the one string that says what failed.
pub suberror StoreError {
  StoreError(String)
} derive(Debug)

///|
impl Show for StoreError with fn output(self, logger) {
  match self {
    StoreError(message) => logger.write_string(message)
  }
}

///|
const ArchivedDirName = "archived"

///|
/// Records rename here before physical removal, keeping the move
/// same-filesystem. The rename is permanent deletion's commit point:
/// everything under this directory is condemned by definition, so an
/// interrupted removal needs no recovery protocol — the next sweep simply
/// erases whatever it finds.
const DeletingDirName = "deleting"

///|
/// One store's archived twin, itself a store in the engine's layout — which is
/// what makes listing archived conversations one more `sessions list`.
pub fn archived_root(root : @pathx.Absolute) -> @pathx.Absolute {
  root.join(ArchivedDirName).normalize()
}

///|
/// Where a committed deletion parks records until a sweep erases them.
pub fn deleting_root(root : @pathx.Absolute) -> @pathx.Absolute {
  archived_root(root).join(DeletingDirName)
}

///|
/// Every store that can own a session id — one per attached workspace.
/// Correlation and stale-client defenses must search all of them: request
/// hints are optional and cannot be trusted to identify where an existing
/// record lives.
pub async fn known_roots() -> Array[@pathx.Absolute] {
  [
    for path in @workspaces.registered() => @workspaces.store_root(path)
  ]
}

///|
/// Whether a session id can serve as a single path component under a store or
/// the workspace root. Path separators and dot segments could escape the root —
/// those conversations work in the home directory instead.
pub fn safe_session_id(session : String) -> Bool {
  !session.is_empty() &&
  session != "." &&
  session != ".." &&
  !session.contains("/") &&
  !session.contains("\\")
}

///|
/// The registered workspace owning `session`, found by where the session's
/// durable record lives (`<workspace>/.openseek/sessions/<id>`). The record's
/// location is the mapping — there is no separate index to fall out of date.
/// `None` when no attached workspace holds the record.
pub async fn workspace_of(session : String) -> @pathx.Absolute? {
  guard safe_session_id(session) else { return None }
  for workspace in @workspaces.registered() {
    let record = @workspaces.store_root(workspace)
      .join("sessions")
      .join(session)
    if @fsx.is_dir(record.to_path()) {
      return Some(workspace)
    }
  }
  None
}

///|
/// The session store root holding `session`'s durable record: the in-project
/// store of the registered workspace that claims it. `None` when no attached
/// workspace holds the record — the client must name the workspace, or attach
/// it, rather than have the host guess a store.
pub async fn root_of(session : String) -> @pathx.Absolute? {
  workspace_of(session).map(@workspaces.store_root)
}

///|
/// The exact archived store selected by a host-produced sidebar row. Every
/// durable record lives in a registered workspace's store, and paths are
/// accepted only while that workspace is registered. Naming the store this
/// exactly is what prevents a same-ID record in another one from being chosen
/// by search order.
pub struct ArchivedStore {
  root : @pathx.Absolute
  workspace : @pathx.Absolute
  workspace_token : String
}

///|
pub async fn ArchivedStore::for_workspace(workspace : String) -> ArchivedStore {
  guard @pathx.Absolute::from_uri_path(workspace) is Some(path) &&
    @workspaces.registered_dir(path) is Some(registered) else {
    raise StoreError("\{workspace} is not a registered workspace")
  }
  // Resource URIs use their authority for the device, so a UNC path has no
  // reversible encoding and is rejected explicitly instead of being published
  // under a new host.
  guard registered.to_uri_path() is Some(workspace_token) else {
    raise StoreError("UNC paths are not supported by frontend resources")
  }
  {
    root: @workspaces.store_root(registered),
    workspace: registered,
    workspace_token,
  }
}

///|
/// The store root whose archived `sessions/<id>` holds this conversation's
/// durable record.
pub async fn archived_root_of(session : String) -> @pathx.Absolute? {
  guard !session.is_empty() else { return None }
  for root in known_roots() {
    if @fsx.is_dir(archived_root(root).join("sessions").join(session).to_path()) {
      return Some(root)
    }
  }
  None
}

///|
/// The store root whose live `sessions/<id>` holds this conversation's
/// durable record, searched like `archived_root_of`. Archive must find the
/// record where it actually lives: a stale client can name a conversation long
/// after its workspace detached, and the session id alone says nothing about
/// which store owns it.
pub async fn live_root_of(session : String) -> @pathx.Absolute? {
  guard !session.is_empty() else { return None }
  for root in known_roots() {
    if @fsx.is_dir(root.join("sessions").join(session).to_path()) {
      return Some(root)
    }
  }
  None
}

///|
pub async fn ensure_not_archived(session : String) -> Unit {
  if archived_root_of(session) is Some(_) {
    raise StoreError("session is archived; unarchive it first")
  }
}

///|
/// Whether `candidate` is a sub-run transcript descended from `ancestor`.
/// Walk the structural `-sr-N` suffixes instead of matching a textual prefix:
/// a user-chosen id such as `chat-sr-not-an-ordinal` must remain unrelated.
fn is_descendant(candidate : String, ancestor : String) -> Bool {
  let mut current = candidate
  for ;; {
    guard @wire.split_child_session_id(current) is Some((parent, _)) else {
      return false
    }
    if parent == ancestor {
      return true
    }
    current = parent
  }
}

///|
/// The parent plus every descendant record present beside it in one live or
/// archived store. Session records are flat sibling directories even though
/// the sidebar presents them as a tree.
pub async fn family_in(
  store : @pathx.Absolute,
  session : String,
) -> Array[String] {
  let sessions_dir = store.join("sessions")
  let entries = @fs.readdir(sessions_dir.to_string(), sort=true) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise StoreError("could not list session records: \{error}")
  }
  let family : Array[String] = [session]
  for candidate in entries {
    if candidate != session &&
      is_descendant(candidate, session) &&
      @fsx.is_dir(sessions_dir.join(candidate).to_path()) {
      family.push(candidate)
    }
  }
  family
}

// Tests for the pure session-id rules the store layout depends on. The
// lookups themselves need real stores on disk and are covered where the
// archive ops are.

///|
test "session ids are accepted as store record names" {
  assert_true(safe_session_id("desktop-20260611-093045-123"))
  assert_true(safe_session_id("my-cli-session"))
  assert_true(safe_session_id("a.b"))
}

///|
test "session ids that could escape their root are refused" {
  assert_false(safe_session_id(""))
  assert_false(safe_session_id("."))
  assert_false(safe_session_id(".."))
  assert_false(safe_session_id("a/b"))
  assert_false(safe_session_id("a\\b"))
  assert_false(safe_session_id("../escape"))
}

///|
test "sub-run descent follows the structural suffix, not a text prefix" {
  assert_true(is_descendant("chat-sr-1", "chat"))
  assert_true(is_descendant("chat-sr-1-sr-2", "chat"))
  assert_false(is_descendant("chat-sr-not-an-ordinal", "chat"))
  assert_false(is_descendant("chat", "chat"))
  assert_false(is_descendant("other-sr-1", "chat"))
}

///|
pub extend StoreError with Debug::{to_repr}
