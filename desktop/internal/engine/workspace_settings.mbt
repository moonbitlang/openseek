// Per-workspace desktop settings: `<workspace>/.openseek/settings.json`,
// desktop-owned like `worktrees.json` beside it. The file travels with the
// workspace directory, so every client of this host — and a reattach after
// a detach — sees the same choices. The file controls where new conversations
// start and whether OpenSeek populates new or repaired worktrees with the
// top-level submodules already initialized in the main checkout.

///|
const WorkspaceSettingsFile = "settings.json"

///|
/// Reads and read-modify-write mutations share one process-wide lock, the
/// `worktrees.json` discipline: without it two concurrent writes could both
/// read the same old file and let the later one silently erase the earlier.
let workspace_settings_lock : @async.Mutex = Mutex()

///|
fn workspace_settings_file(workspace : @pathx.Absolute) -> @pathx.Absolute {
  workspace_session_root(workspace).join(WorkspaceSettingsFile)
}

///|
/// The stored fields. Settings JSON is an input boundary: a malformed file
/// reads as no overrides (every setting on its default) rather than
/// poisoning later operations, and unknown fields from a newer build are
/// carried through a save verbatim so a downgrade's edit never eats them.
fn parse_workspace_settings(text : String) -> Map[String, Json] {
  let json = @json.parse(text) catch { _ => return {} }
  guard json is Object(fields) else { return {} }
  fields
}

///|
/// A missing or unreadable file reads as no overrides.
async fn read_workspace_settings_unlocked(
  workspace : @pathx.Absolute,
) -> Map[String, Json] {
  let text = @fsx.try_read_text(workspace_settings_file(workspace).to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return {}
  }
  guard text is Some(text) else { return {} }
  parse_workspace_settings(text)
}

///|
/// Whether a new conversation in this workspace starts in a fresh bound git
/// worktree. Anything but an explicit `true` is the Local default.
fn settings_worktree_mode(fields : Map[String, Json]) -> Bool {
  fields.get("worktree_mode") is Some(True)
}

///|
fn workspace_settings_payload(
  workspace : @pathx.Absolute,
  fields : Map[String, Json],
) -> @protocol.WorkspaceSettingsPayload raise EngineError {
  {
    workspace: workspace.resource_path(),
    worktree_mode: settings_worktree_mode(fields),
    // Preserve the historical behavior unless this workspace explicitly
    // disables submodule provisioning.
    checkout_submodules: Some(
      !(fields.get("checkout_submodules") is Some(False)),
    ),
  }
}

///|
async fn write_workspace_settings(
  workspace : @pathx.Absolute,
  fields : Map[String, Json],
) -> Unit {
  let store = workspace_session_root(workspace)
  @fsx.ensure_dir(store.to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise EngineError("could not create \{store}: \{error}")
  }
  @fsx.write_text(
    workspace_settings_file(workspace).to_path(),
    fields.to_json().stringify(indent=2),
  ) catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      raise EngineError("could not save the workspace settings: \{error}")
  }
}

///|
/// One workspace's desktop-owned settings. Only a registered workspace may
/// be read: op payloads name a workspace, but the registry — host state —
/// decides which directories the webview may reach.
pub async fn workspace_settings(
  workspace : String,
) -> @protocol.WorkspaceSettingsPayload {
  guard @pathx.Absolute::from_uri_path(workspace) is Some(absolute) &&
    registered_workspace(absolute) is Some(dir) else {
    raise EngineError("\{workspace} is not a registered workspace")
  }
  workspace_settings_lock.acquire()
  defer workspace_settings_lock.release()
  workspace_settings_payload(dir, read_workspace_settings_unlocked(dir))
}

///|
/// Patch one workspace's settings and broadcast the committed state. The
/// write and `on_committed` callback are one finite,
/// cancellation-shielded linearization point under the lock — the
/// `workspaces.json` pattern — so every client learns of commits in the
/// same total order even if the requester disconnects before its reply.
pub async fn update_workspace_settings(
  workspace : String,
  on_committed : (@protocol.WorkspaceSettingsPayload) -> Unit,
  worktree_mode? : Bool,
  checkout_submodules? : Bool,
) -> @protocol.WorkspaceSettingsPayload {
  guard @pathx.Absolute::from_uri_path(workspace) is Some(absolute) &&
    registered_workspace(absolute) is Some(dir) else {
    raise EngineError("\{workspace} is not a registered workspace")
  }
  workspace_settings_lock.acquire()
  defer workspace_settings_lock.release()
  let fields = read_workspace_settings_unlocked(dir)
  if worktree_mode is Some(worktree_mode) {
    fields["worktree_mode"] = worktree_mode.to_json()
  }
  if checkout_submodules is Some(checkout_submodules) {
    fields["checkout_submodules"] = checkout_submodules.to_json()
  }
  let payload = workspace_settings_payload(dir, fields)
  @async.protect_from_cancel(() => {
    write_workspace_settings(dir, fields)
    on_committed(payload)
  })
  payload
}

// Tests cover the pure parse/serialize pieces and the file round trip; the
// registry gate is the same `registered_workspace` check the worktree ops
// use and is covered by the live app.

///|
test "workspace settings parse tolerantly and keep unknown fields" {
  assert_true(
    settings_worktree_mode(
      parse_workspace_settings("{\"worktree_mode\": true}"),
    ),
  )
  // Only an explicit `true` opts in; anything else is the Local default.
  assert_false(
    settings_worktree_mode(
      parse_workspace_settings("{\"worktree_mode\": \"yes\"}"),
    ),
  )
  assert_false(settings_worktree_mode(parse_workspace_settings("not json")))
  assert_false(settings_worktree_mode(parse_workspace_settings("")))
  let fields = parse_workspace_settings("{\"future\": 1}")
  fields["worktree_mode"] = true.to_json()
  assert_true(settings_worktree_mode(fields))
  assert_true(fields.get("future") is Some(_))
  guard @pathx.Absolute::from_uri_path("/repo") is Some(workspace) else {
    fail("expected an absolute workspace path")
  }
  let payload = workspace_settings_payload(workspace, fields)
  assert_eq(payload.checkout_submodules, Some(true))
  fields["checkout_submodules"] = false.to_json()
  assert_eq(
    workspace_settings_payload(workspace, fields).checkout_submodules,
    Some(false),
  )
}

///|
async test "workspace settings survive a write/read round trip independently" {
  let dir = @fs.tmpdir(prefix="openseek-workspace-settings-")
  guard @pathx.Path(dir).to_absolute() is Some(workspace) else {
    fail("expected an absolute temporary workspace path")
  }
  let sibling = workspace.join("sibling")
  assert_false(
    settings_worktree_mode(read_workspace_settings_unlocked(workspace)),
  )
  let fields = read_workspace_settings_unlocked(workspace)
  fields["worktree_mode"] = true.to_json()
  fields["checkout_submodules"] = false.to_json()
  write_workspace_settings(workspace, fields)
  let reread = read_workspace_settings_unlocked(workspace)
  assert_true(settings_worktree_mode(reread))
  assert_eq(reread.get("checkout_submodules"), Some(false.to_json()))
  // The file lives below one workspace root, so an adjacent workspace keeps
  // both defaults when only this workspace is edited.
  let sibling_payload = workspace_settings_payload(
    sibling,
    read_workspace_settings_unlocked(sibling),
  )
  assert_false(sibling_payload.worktree_mode)
  assert_eq(sibling_payload.checkout_submodules, Some(true))
  @fs.rmdir(dir, recursive=true) catch {
    _ => ()
  }
}
