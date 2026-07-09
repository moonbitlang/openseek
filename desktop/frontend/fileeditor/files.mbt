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
      @interop.set_workspace(payload, workspace)
      let reply = @interop.bridge_request("read_directory", payload.to_value()) catch {
        error => {
          scheduler.add(
            dispatch(
              DirFailed(
                session~,
                path~,
                message=@interop.bridge_error_text(error),
              ),
            ),
          )
          return
        }
      }
      match decode_dir_entries(@interop.reply_json_text(reply), path) {
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
/// Ask the host for the workspace's full file list (the fuzzy filter's
/// index) and fold it back as `FilesIndexed`. Failures fold as
/// `FileIndexFailed`, dropping the index so a later keystroke retries.
fn list_files(
  dispatch : @cmd.Emit[Msg],
  session : String,
  workspace~ : @pathx.Absolute?,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = session
      @interop.set_workspace(payload, workspace)
      let reply = @interop.bridge_request("list_files", payload.to_value()) catch {
        _ => {
          scheduler.add(dispatch(FileIndexFailed(session~)))
          return
        }
      }
      match decode_file_index(@interop.reply_json_text(reply)) {
        Some((files, truncated)) =>
          scheduler.add(dispatch(FilesIndexed(session~, files~, truncated~)))
        None => scheduler.add(dispatch(FileIndexFailed(session~)))
      }
    })
  })
}

///|
/// Parse a `list_files` reply into relative paths plus the truncation flag.
fn decode_file_index(text : String) -> (Array[@pathx.Relative], Bool)? {
  let json = @json.parse(text) catch { _ => return None }
  guard json is Object(reply) else { return None }
  guard reply.get("files") is Some(Array(items)) else { return None }
  let files : Array[@pathx.Relative] = []
  for item in items {
    guard item is String(path) else { continue }
    if !path.is_empty() {
      files.push(Relative(path))
    }
  }
  Some((files, reply.get("truncated") is Some(True)))
}

///|
/// Read `path` and fold its contents back as `FileLoaded`. `name` is the
/// entry's display name, forwarded for the viewer's title and language guess.
/// `range`, when present (a symbol jump's target), is forwarded for the
/// viewer to reveal and select once loaded; `annotation` (an annotation
/// chip's comment) rides along the same way, re-shown as an editor bubble
/// over that range.
pub fn read_file(
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
      @interop.set_workspace(payload, workspace)
      let reply = @interop.bridge_request("read_file", payload.to_value()) catch {
        error => {
          scheduler.add(
            dispatch(
              FileFailed(session~, message=@interop.bridge_error_text(error)),
            ),
          )
          return
        }
      }
      match decode_file_content(@interop.reply_json_text(reply)) {
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
/// A workspace-relative path's final `/`-segment, for a mention chip's jump
/// target — it carries only the path, not a display name.
pub fn basename(path : @pathx.Relative) -> String {
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
    // The host writes both fields on every entry.
    guard @jsonx.json_text(fields, "name") is Some(name) && !name.is_empty() else {
      continue
    }
    guard @jsonx.json_bool(fields, "is_dir") is Some(is_dir) else { continue }
    entries.push({ name, path: child_path(parent, name), is_dir })
  }
  Some(entries)
}

///|
fn decode_file_content(text : String) -> FileContent? {
  let json = @json.parse(text) catch { _ => return None }
  guard json is Object(reply) else { return None }
  guard @jsonx.json_text(reply, "kind") is Some(kind) else { return None }
  match kind {
    "binary" => Some(Binary)
    "oversized" => Some(Oversized)
    "content" => {
      // The `content` variant always carries all three fields.
      guard @jsonx.json_text(reply, "content") is Some(content) &&
        @jsonx.json_text(reply, "absolute") is Some(absolute) &&
        @jsonx.json_text(reply, "sig") is Some(sig) else {
        return None
      }
      guard !absolute.is_empty() else { return None }
      Some(Content(content~, absolute=Absolute(absolute), sig~))
    }
    _ => None
  }
}

///|
/// Stat the open tabs' files and fold the signatures back as `StatsLoaded`.
/// Best-effort: a failed call is dropped — the next change push retries.
fn stat_files(
  dispatch : @cmd.Emit[Msg],
  session : String,
  paths : Array[@pathx.Relative],
  workspace~ : @pathx.Absolute?,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = session
      payload["paths"] = paths.map(path => path.0)
      @interop.set_workspace(payload, workspace)
      let reply = @interop.bridge_request("stat_files", payload.to_value()) catch {
        _ => return
      }
      guard decode_file_stats(@interop.reply_json_text(reply)) is Some(stats) else {
        return
      }
      scheduler.add(dispatch(StatsLoaded(session~, stats~)))
    })
  })
}

///|
fn decode_file_stats(text : String) -> Array[FileStat]? {
  let json = @json.parse(text) catch { _ => return None }
  guard json is Object(reply) else { return None }
  guard reply.get("stats") is Some(Array(items)) else { return None }
  let stats : Array[FileStat] = []
  for item in items {
    guard item is Object(fields) else { continue }
    // Both fields are always on the wire; `sig` is "" for a file the host
    // could not stat.
    guard @jsonx.json_text(fields, "path") is Some(path) && !path.is_empty() else {
      continue
    }
    guard @jsonx.json_text(fields, "sig") is Some(sig) else { continue }
    stats.push({ path: Relative(path), sig })
  }
  Some(stats)
}

///|
/// Point the host's workspace watcher at `session`'s workspace (`""` parks
/// it). Fire-and-forget: there is no reply worth folding, and a failure just
/// means no live updates until the next reconciliation re-sends.
fn watch_workspace(session : String, workspace~ : @pathx.Absolute?) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = session
      @interop.set_workspace(payload, workspace)
      let _ : @js.Value = @interop.bridge_request(
        "watch_workspace",
        payload.to_value(),
      ) catch {
        _ => return
      }
    })
  })
}
