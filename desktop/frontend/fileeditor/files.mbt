// The editor side-panel's filesystem calls: list a directory and read a file
// under the active conversation's workspace, through the host's
// `read_directory` / `read_file` ops. The host resolves every path against
// the session's workspace and rejects escapes, so the panel only ever sees
// that one conversation's tree. Each reply carries the full conversation
// owner and path it answers so a reply that lost a device/session switch can
// be discarded.

///|
/// List `path` (relative to the conversation workspace; "" is the root) and
/// fold the entries back as `DirLoaded`.
fn read_directory(
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  path : @pathx.Relative,
  workspace~ : @pathx.Absolute?,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = owner.session
      payload["path"] = path.0
      @interop.set_workspace(payload, workspace)
      let reply = @interop.bridge_request(
        owner.channel,
        "fs.read_directory",
        payload.to_value(),
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              DirFailed(
                owner~,
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
          scheduler.add(dispatch(DirLoaded(owner~, path~, entries~)))
        None =>
          scheduler.add(
            dispatch(
              DirFailed(owner~, path~, message="could not read directory"),
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
  owner : @interop.ConversationKey,
  workspace~ : @pathx.Absolute?,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = owner.session
      @interop.set_workspace(payload, workspace)
      let reply = @interop.bridge_request(
        owner.channel,
        "fs.list_files",
        payload.to_value(),
      ) catch {
        _ => {
          scheduler.add(dispatch(FileIndexFailed(owner~)))
          return
        }
      }
      match decode_file_index(@interop.reply_json_text(reply)) {
        Some((files, truncated)) =>
          scheduler.add(dispatch(FilesIndexed(owner~, files~, truncated~)))
        None => scheduler.add(dispatch(FileIndexFailed(owner~)))
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
  owner : @interop.ConversationKey,
  path : @pathx.Relative,
  name : String,
  range~ : @common.Range?,
  annotation? : String,
  workspace~ : @pathx.Absolute?,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = owner.session
      payload["path"] = path.0
      @interop.set_workspace(payload, workspace)
      let reply = @interop.bridge_request(
        owner.channel,
        "fs.read_file",
        payload.to_value(),
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              FileFailed(owner~, message=@interop.bridge_error_text(error)),
            ),
          )
          return
        }
      }
      match decode_file_content(@interop.reply_json_text(reply)) {
        Some(file) =>
          scheduler.add(
            dispatch(
              FileLoaded(owner~, path~, name~, file~, range~, annotation~),
            ),
          )
        None =>
          scheduler.add(
            dispatch(FileFailed(owner~, message="could not read file")),
          )
      }
    })
  })
}

///|
/// A workspace-relative path's final `/`-segment, for a mention chip's jump
/// target — it carries only the path, not a display name.
pub fn basename(path : @pathx.Relative) -> String {
  match [..path.0.split("/")] {
    [] => path.0
    [.., last] => last.to_owned()
  }
}

///|
/// An entry's workspace-relative path: the parent directory's path joined with
/// the entry name ("" parent = workspace root, so the child path is `name`).
fn child_path(parent : @pathx.Relative, name : String) -> @pathx.Relative {
  if parent.is_root() {
    Relative(name)
  } else {
    Relative("\{parent.0}/\{name}")
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
  owner : @interop.ConversationKey,
  paths : Array[@pathx.Relative],
  workspace~ : @pathx.Absolute?,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = owner.session
      payload["paths"] = paths.map(path => path.0)
      @interop.set_workspace(payload, workspace)
      let reply = @interop.bridge_request(
        owner.channel,
        "fs.stat_files",
        payload.to_value(),
      ) catch {
        _ => return
      }
      guard decode_file_stats(@interop.reply_json_text(reply)) is Some(stats) else {
        return
      }
      scheduler.add(dispatch(StatsLoaded(owner~, stats~)))
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
    guard @jsonx.json_text(fields, "path") is Some(path) && !path.is_empty() else {
      continue
    }
    // `sig` is absent for a file the host could not stat — a deleted file.
    stats.push({ path: Relative(path), sig: @jsonx.json_text(fields, "sig") })
  }
  Some(stats)
}

///|
/// Point the host's workspace watcher at `session`'s workspace, or park it
/// (`fs.unwatch`) when the panel no longer needs one. Fire-and-forget:
/// there is no reply worth folding, and a failure just means no live
/// updates until the next reconciliation re-sends.
fn watch_workspace(
  channel~ : @interop.ChannelId,
  session : String,
  workspace~ : @pathx.Absolute?,
) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    @js.async_run(() => {
      if session.is_empty() {
        let _ : @js.Value = @interop.bridge_request_in_order(
          channel,
          "fs.unwatch",
          @js.Object::new().to_value(),
        ) catch {
          _ => return
        }
      } else {
        let payload = @js.Object::new()
        payload["session"] = session
        @interop.set_workspace(payload, workspace)
        let _ : @js.Value = @interop.bridge_request_in_order(
          channel,
          "fs.watch",
          payload.to_value(),
        ) catch {
          _ => return
        }
      }
    })
  })
}

///|
test "child_path joins entry names onto their parent directory" {
  assert_eq(child_path(@pathx.Relative::root(), "src").0, "src")
  assert_eq(child_path(@pathx.Relative::root(), "moon.mod").0, "moon.mod")
  assert_eq(child_path(Relative("src"), "main.mbt").0, "src/main.mbt")
  assert_eq(child_path(Relative("src/lib"), "util.mbt").0, "src/lib/util.mbt")
}

///|
test "language_id maps known extensions and falls back to plain text" {
  assert_eq(language_id("main.mbt"), "moonbit")
  assert_eq(language_id("pkg.generated.mbti"), "moonbit")
  assert_eq(language_id("README.mbt.md"), "moonbit")
  assert_eq(language_id("bundle.js"), "javascript")
  assert_eq(language_id("config.mjs"), "javascript")
  assert_eq(language_id("moon.mod.json"), "json")
  assert_eq(language_id("notes.txt"), "plaintext")
  assert_eq(language_id("LICENSE"), "plaintext")
}

///|
test "decode_dir_entries builds full relative paths and skips bad rows" {
  let reply =
    #|{"entries":[{"name":"src","is_dir":true},{"name":"moon.mod","is_dir":false},{"is_dir":true}]}
  let entries = decode_dir_entries(reply, @pathx.Relative::root()).unwrap()
  // The third row has no name and is dropped.
  assert_eq(entries.length(), 2)
  assert_eq(entries[0].name, "src")
  assert_eq(entries[0].path.0, "src")
  assert_true(entries[0].is_dir)
  assert_eq(entries[1].name, "moon.mod")
  assert_eq(entries[1].path.0, "moon.mod")
  assert_false(entries[1].is_dir)
}

///|
test "decode_dir_entries roots child paths at the parent directory" {
  let reply =
    #|{"entries":[{"name":"util.mbt","is_dir":false}]}
  let entries = decode_dir_entries(reply, Relative("src/lib")).unwrap()
  assert_eq(entries[0].path.0, "src/lib/util.mbt")
}

///|
test "decode_dir_entries rejects structurally unusable replies" {
  assert_true(decode_dir_entries("not json", @pathx.Relative::root()) is None)
  assert_true(
    decode_dir_entries("{\"entries\":42}", @pathx.Relative::root()) is None,
  )
}

///|
test "decode_file_index parses paths, truncation, and rejects garbage" {
  let reply =
    #|{"files":["moon.mod","src/lib.mbt",42,""],"truncated":true}
  let (files, truncated) = decode_file_index(reply).unwrap()
  // The non-string and empty rows are dropped.
  assert_eq(files.length(), 2)
  assert_eq(files[0].0, "moon.mod")
  assert_eq(files[1].0, "src/lib.mbt")
  assert_true(truncated)
  assert_true(decode_file_index("{\"files\":[]}").unwrap().0.is_empty())
  assert_false(decode_file_index("{\"files\":[]}").unwrap().1)
  assert_true(decode_file_index("not json") is None)
  assert_true(decode_file_index("{\"files\":42}") is None)
}

///|
test "decode_file_content decodes each reply kind" {
  assert_true(
    decode_file_content(
      "{\"kind\":\"content\",\"content\":\"hello\",\"absolute\":\"/ws/a.mbt\",\"sig\":\"12:34\"}",
    )
    is Some(
      Content(content="hello", absolute=Absolute("/ws/a.mbt"), sig="12:34")
    ),
  )
  assert_true(decode_file_content("{\"kind\":\"binary\"}") is Some(Binary))
  assert_true(
    decode_file_content("{\"kind\":\"oversized\"}") is Some(Oversized),
  )
  // The host writes all three fields on every content reply; one missing its
  // address or signature is malformed and unusable, as is anything else.
  assert_true(
    decode_file_content(
      "{\"kind\":\"content\",\"content\":\"x\",\"sig\":\"1:2\"}",
    )
    is None,
  )
  assert_true(
    decode_file_content(
      "{\"kind\":\"content\",\"content\":\"x\",\"absolute\":\"/ws/a.mbt\"}",
    )
    is None,
  )
  assert_true(decode_file_content("{\"truncated\":true}") is None)
  assert_true(decode_file_content("garbage") is None)
}
