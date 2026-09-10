// Per-workspace desktop settings: `<workspace>/.openseek/settings.json`,
// desktop-owned like `worktrees.json` beside it. The file travels with the
// workspace directory, so every client of this host — and a reattach after
// a detach — sees the same choices. The file controls where new conversations
// start and how OpenSeek populates new or repaired worktrees with the
// top-level submodules already initialized in the main checkout.

///|
const WorkspaceSettingsFile = "settings.json"

///|
/// Existing workspaces and malformed hand-edited settings retain the short
/// checkout bound chosen for conversation creation.
const DefaultSubmoduleCheckoutTimeoutSeconds : Int = 10

///|
/// Reads and read-modify-write mutations share one process-wide lock, the
/// `worktrees.json` discipline: without it two concurrent writes could both
/// read the same old file and let the later one silently erase the earlier.
let settings_lock : @async.Mutex = Mutex()

///|
fn settings_file(workspace : @pathx.Absolute) -> @pathx.Absolute {
  store_root(workspace).join(WorkspaceSettingsFile)
}

///|
/// The stored fields. Settings JSON is an input boundary: a malformed file
/// reads as no overrides (every setting on its default) rather than
/// poisoning later operations, and unknown fields from a newer build are
/// carried through a save verbatim so a downgrade's edit never eats them.
fn parse_settings(text : String) -> Map[String, Json] {
  let json = @json.parse(text) catch { _ => return {} }
  guard json is Object(fields) else { return {} }
  fields
}

///|
/// A missing or unreadable file reads as no overrides.
async fn read_settings_unlocked(
  workspace : @pathx.Absolute,
) -> Map[String, Json] {
  let text = @fsx.try_read_text(settings_file(workspace).to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return {}
  }
  guard text is Some(text) else { return {} }
  parse_settings(text)
}

///|
/// Whether a new conversation in this workspace starts in a fresh bound git
/// worktree. Anything but an explicit `true` is the Local default.
fn worktree_mode_of(fields : Map[String, Json]) -> Bool {
  fields.get("worktree_mode") is Some(True)
}

///|
/// Keep disk input and the Settings select on the same four choices. Other
/// numbers, fractions, strings, and booleans read as the default instead of
/// reaching the timeout primitive unchecked.
fn submodule_timeout_of(fields : Map[String, Json]) -> Int {
  guard fields.get("submodule_checkout_timeout_seconds")
    is Some(Number(value, ..)) else {
    return DefaultSubmoduleCheckoutTimeoutSeconds
  }
  let seconds = value.to_int()
  match seconds {
    5 | 10 | 30 | 60 if value == seconds.to_double() => seconds
    _ => DefaultSubmoduleCheckoutTimeoutSeconds
  }
}

///|
fn settings_payload(
  workspace : @pathx.Absolute,
  fields : Map[String, Json],
) -> @protocol.WorkspaceSettingsPayload raise WorkspaceError {
  // Resource URIs use their authority for the device, so a UNC path has no
  // reversible encoding and is rejected explicitly instead of being published
  // under a new host.
  guard workspace.to_uri_path() is Some(resource_path) else {
    raise WorkspaceError("UNC paths are not supported by frontend resources")
  }
  {
    workspace: resource_path,
    worktree_mode: worktree_mode_of(fields),
    // Preserve the historical behavior unless this workspace explicitly
    // disables submodule provisioning.
    checkout_submodules: !(fields.get("checkout_submodules") is Some(False)),
    submodule_checkout_timeout_seconds: submodule_timeout_of(fields),
  }
}

///|
async fn write_settings(
  workspace : @pathx.Absolute,
  fields : Map[String, Json],
) -> Unit {
  let store = store_root(workspace)
  @fsx.ensure_dir(store.to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise WorkspaceError("could not create \{store}: \{error}")
  }
  @fsx.write_text(
    settings_file(workspace).to_path(),
    fields.to_json().stringify(indent=2),
  ) catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      raise WorkspaceError("could not save the workspace settings: \{error}")
  }
}

///|
/// One workspace's desktop-owned settings. Only a registered workspace may
/// be read: op payloads name a workspace, but the registry — host state —
/// decides which directories the webview may reach.
pub async fn settings(workspace : String) -> @protocol.WorkspaceSettingsPayload {
  guard @pathx.Absolute::from_uri_path(workspace) is Some(absolute) &&
    registered_dir(absolute) is Some(dir) else {
    raise WorkspaceError("\{workspace} is not a registered workspace")
  }
  settings_lock.acquire()
  defer settings_lock.release()
  settings_payload(dir, read_settings_unlocked(dir))
}

///|
/// Patch one workspace's settings and broadcast the committed state. The
/// write and `on_committed` callback are one finite,
/// cancellation-shielded linearization point under the lock — the
/// `workspaces.json` pattern — so every client learns of commits in the
/// same total order even if the requester disconnects before its reply.
pub async fn update_settings(
  workspace : String,
  on_committed : (@protocol.WorkspaceSettingsPayload) -> Unit,
  worktree_mode? : Bool,
  checkout_submodules? : Bool,
  submodule_checkout_timeout_seconds? : Int,
) -> @protocol.WorkspaceSettingsPayload {
  guard @pathx.Absolute::from_uri_path(workspace) is Some(absolute) &&
    registered_dir(absolute) is Some(dir) else {
    raise WorkspaceError("\{workspace} is not a registered workspace")
  }
  settings_lock.acquire()
  defer settings_lock.release()
  let fields = read_settings_unlocked(dir)
  if worktree_mode is Some(worktree_mode) {
    fields["worktree_mode"] = worktree_mode.to_json()
  }
  if checkout_submodules is Some(checkout_submodules) {
    fields["checkout_submodules"] = checkout_submodules.to_json()
  }
  if submodule_checkout_timeout_seconds is Some(seconds) {
    if !(seconds is (5 | 10 | 30 | 60)) {
      raise WorkspaceError(
        "submodule checkout timeout must be 5, 10, 30, or 60 seconds",
      )
    }
    fields["submodule_checkout_timeout_seconds"] = seconds.to_json()
  }
  let payload = settings_payload(dir, fields)
  @async.protect_from_cancel(() => {
    write_settings(dir, fields)
    on_committed(payload)
  })
  payload
}

// Tests cover the pure parse/serialize pieces and the file round trip; the
// registry gate is the same `registered_dir` check the worktree ops
// use and is covered by the live app.

///|
#cfg(not(platform="windows"))
test "workspace settings parse tolerantly and keep unknown fields" {
  assert_true(worktree_mode_of(parse_settings("{\"worktree_mode\": true}")))
  // Only an explicit `true` opts in; anything else is the Local default.
  assert_false(worktree_mode_of(parse_settings("{\"worktree_mode\": \"yes\"}")))
  assert_false(worktree_mode_of(parse_settings("not json")))
  assert_false(worktree_mode_of(parse_settings("")))
  let fields = parse_settings("{\"future\": 1}")
  fields["worktree_mode"] = true.to_json()
  assert_true(worktree_mode_of(fields))
  assert_true(fields.get("future") is Some(_))
  guard @pathx.Absolute::from_uri_path("/repo") is Some(workspace) else {
    fail("expected an absolute workspace path")
  }
  let payload = settings_payload(workspace, fields)
  assert_true(payload.checkout_submodules)
  assert_eq(
    payload.submodule_checkout_timeout_seconds,
    DefaultSubmoduleCheckoutTimeoutSeconds,
  )
  fields["checkout_submodules"] = false.to_json()
  assert_false(settings_payload(workspace, fields).checkout_submodules)
  fields["submodule_checkout_timeout_seconds"] = Json(30)
  assert_eq(
    settings_payload(workspace, fields).submodule_checkout_timeout_seconds,
    30,
  )
  for invalid in [Json(0), Json(15), Json(1.5), Json("ten")] {
    fields["submodule_checkout_timeout_seconds"] = invalid
    assert_eq(
      settings_payload(workspace, fields).submodule_checkout_timeout_seconds,
      DefaultSubmoduleCheckoutTimeoutSeconds,
    )
  }
}

///|
async test "workspace settings survive a write/read round trip independently" {
  let dir = @fs.tmpdir(prefix="openseek-workspace-settings-")
  guard @pathx.Path(dir).to_absolute() is Some(workspace) else {
    fail("expected an absolute temporary workspace path")
  }
  let sibling = workspace.join("sibling")
  assert_false(worktree_mode_of(read_settings_unlocked(workspace)))
  let fields = read_settings_unlocked(workspace)
  fields["worktree_mode"] = true.to_json()
  fields["checkout_submodules"] = false.to_json()
  fields["submodule_checkout_timeout_seconds"] = Json(30)
  write_settings(workspace, fields)
  let reread = read_settings_unlocked(workspace)
  assert_true(worktree_mode_of(reread))
  assert_eq(reread.get("checkout_submodules"), Some(false.to_json()))
  assert_eq(reread.get("submodule_checkout_timeout_seconds"), Some(Json(30)))
  // The file lives below one workspace root, so an adjacent workspace keeps
  // both defaults when only this workspace is edited.
  let sibling_payload = settings_payload(
    sibling,
    read_settings_unlocked(sibling),
  )
  assert_false(sibling_payload.worktree_mode)
  assert_true(sibling_payload.checkout_submodules)
  assert_eq(
    sibling_payload.submodule_checkout_timeout_seconds,
    DefaultSubmoduleCheckoutTimeoutSeconds,
  )
  @fs.rmdir(dir, recursive=true) catch {
    _ => ()
  }
}
