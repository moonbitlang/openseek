// The editor side-panel's filesystem calls: list a directory and read a file
// under the active conversation's workspace, through the host's
// `read_directory` / `read_file` ops. The host resolves every path against
// the session's workspace and rejects escapes, so the panel only ever sees
// that one conversation's tree. Each reply carries the `session` and `path`
// it answers so a reply that lost a conversation switch can be discarded.

///|
/// List `path` (relative to the conversation workspace; "" is the root) and
/// fold the entries back as `DirLoaded`.
fn read_directory(
  dispatch : @cmd.Emit[Msg],
  session : String,
  path : @pathx.Relative,
  workspace~ : @pathx.Absolute?,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = session
      payload["path"] = path.0
      set_workspace(payload, workspace)
      let reply = bridge_request("read_directory", payload.to_value()) catch {
        error => {
          scheduler.add(
            dispatch(
              DirFailed(session~, path~, message=bridge_error_text(error)),
            ),
          )
          return
        }
      }
      match decode_dir_entries(reply_json_text(reply), path) {
        Some(entries) =>
          scheduler.add(dispatch(DirLoaded(session~, path~, entries~)))
        None =>
          scheduler.add(
            dispatch(
              DirFailed(session~, path~, message="could not read directory"),
            ),
          )
      }
    })
  })
}

///|
/// Read `path` and fold its contents back as `FileLoaded`. `name` is the
/// entry's display name, forwarded for the viewer's title and language guess.
/// `range`, when present (a symbol jump's target), is forwarded for the
/// viewer to reveal and select once loaded; `annotation` (an annotation
/// chip's comment) rides along the same way, re-shown as an editor bubble
/// over that range.
fn read_file(
  dispatch : @cmd.Emit[Msg],
  session : String,
  path : @pathx.Relative,
  name : String,
  range~ : @common.Range?,
  annotation? : String,
  workspace~ : @pathx.Absolute?,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = session
      payload["path"] = path.0
      set_workspace(payload, workspace)
      let reply = bridge_request("read_file", payload.to_value()) catch {
        error => {
          scheduler.add(
            dispatch(FileFailed(session~, message=bridge_error_text(error))),
          )
          return
        }
      }
      match decode_file_content(reply_json_text(reply)) {
        Some(file) =>
          scheduler.add(
            dispatch(
              FileLoaded(session~, path~, name~, file~, range~, annotation~),
            ),
          )
        None =>
          scheduler.add(
            dispatch(FileFailed(session~, message="could not read file")),
          )
      }
    })
  })
}

///|
/// Attach the workspace hint to an op payload, when the conversation has one.
fn set_workspace(payload : @js.Object, workspace : @pathx.Absolute?) -> Unit {
  if workspace is Some(workspace) {
    set_trimmed(payload, "workspace", workspace.0)
  }
}

///|
/// A workspace-relative path's final `/`-segment, for a mention chip's jump
/// target — it carries only the path, not a display name.
fn basename(path : @pathx.Relative) -> String {
  match path.0.split("/").collect() {
    [] => path.0
    segments => segments[segments.length() - 1].to_owned()
  }
}

///|
/// An entry's workspace-relative path: the parent directory's path joined with
/// the entry name ("" parent = workspace root, so the child path is `name`).
fn child_path(parent : @pathx.Relative, name : String) -> @pathx.Relative {
  if parent.is_root() {
    Relative(name)
  } else {
    Relative(parent.0 + "/" + name)
  }
}

///|
/// Parse a `read_directory` reply into entries carrying full relative paths.
/// `None` only for structurally unusable JSON; a malformed row is skipped.
fn decode_dir_entries(
  text : String,
  parent : @pathx.Relative,
) -> Array[FileEntry]? {
  let json = @json.parse(text) catch { _ => return None }
  guard json is Object(reply) else { return None }
  guard reply.get("entries") is Some(Array(items)) else { return None }
  let entries : Array[FileEntry] = []
  for item in items {
    guard item is Object(fields) else { continue }
    let name = @transcript.json_text(fields, "name")
    guard !name.is_empty() else { continue }
    let is_dir = fields.get("is_dir") is Some(True)
    entries.push({ name, path: child_path(parent, name), is_dir })
  }
  Some(entries)
}

///|
/// A decoded `read_file` reply. Withheld files are their own cases — the
/// wording of their notices is this side's business — and only a real file
/// carries an address for path-routed ops (hover on a notice document has
/// nothing to ask about).
priv enum FileContent {
  Binary
  Oversized
  Content(content~ : String, absolute~ : @pathx.Absolute)
}

///|
fn decode_file_content(text : String) -> FileContent? {
  let json = @json.parse(text) catch { _ => return None }
  guard json is Object(reply) else { return None }
  match @transcript.json_text(reply, "kind") {
    "binary" => Some(Binary)
    "oversized" => Some(Oversized)
    "content" => {
      guard reply.get("content") is Some(String(content)) else { return None }
      let absolute = @transcript.json_text(reply, "absolute")
      guard !absolute.is_empty() else { return None }
      Some(Content(content~, absolute=Absolute(absolute)))
    }
    _ => None
  }
}
