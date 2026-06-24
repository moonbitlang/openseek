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
  path : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = session
      payload["path"] = path
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
fn read_file(
  dispatch : @cmd.Emit[Msg],
  session : String,
  path : String,
  name : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = session
      payload["path"] = path
      let reply = bridge_request("read_file", payload.to_value()) catch {
        error => {
          scheduler.add(
            dispatch(FileFailed(session~, message=bridge_error_text(error))),
          )
          return
        }
      }
      match decode_file_content(reply_json_text(reply)) {
        Some(content) =>
          scheduler.add(dispatch(FileLoaded(session~, path~, name~, content~)))
        None =>
          scheduler.add(
            dispatch(FileFailed(session~, message="could not read file")),
          )
      }
    })
  })
}

///|
/// An entry's workspace-relative path: the parent directory's path joined with
/// the entry name ("" parent = workspace root, so the child path is `name`).
fn child_path(parent : String, name : String) -> String {
  if parent.is_empty() {
    name
  } else {
    parent + "/" + name
  }
}

///|
/// Parse a `read_directory` reply into entries carrying full relative paths.
/// `None` only for structurally unusable JSON; a malformed row is skipped.
fn decode_dir_entries(text : String, parent : String) -> Array[FileEntry]? {
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
/// Parse a `read_file` reply. `content` already holds a short notice when the
/// host withheld a binary or oversized file, so the panel shows it verbatim.
fn decode_file_content(text : String) -> String? {
  let json = @json.parse(text) catch { _ => return None }
  guard json is Object(reply) else { return None }
  guard reply.get("content") is Some(String(content)) else { return None }
  Some(content)
}
