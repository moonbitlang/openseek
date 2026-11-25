///|
const WorkspaceMemoryLimit : Int32 = 8192

///|
/// The prompt snapshot pinned to a conversation's current compaction.
/// Keep it beside the transcript so resuming can reuse the same prompt
/// prefix, and so the snapshot does not become conversation history.
struct WorkspaceMemory {
  workspace_root : String
  store : SessionStore?
  mut cached : (String, WorkspaceMemorySnapshot)?
}

///|
#derive(FromJson, ToJson)
priv struct WorkspaceMemorySnapshot {
  workspace_root : String
  checkpoint : Int32
  body : String?
}

///|
/// Resolve one conversation's memory from its workspace. With a session
/// store the snapshot survives process restarts.
pub fn WorkspaceMemory::WorkspaceMemory(
  workspace_root~ : String,
  store? : SessionStore,
) -> WorkspaceMemory {
  { workspace_root, store, cached: None, }
}

///|
/// Load once on the first model request, then again only when the session
/// projects through a newly recorded summary. A missing file is pinned too.
pub async fn WorkspaceMemory::snapshot(
  self : WorkspaceMemory,
  session : @agent_session.Session,
) -> String? {
  let id = session.id()
  let checkpoint = latest_memory_checkpoint(session)
  if self.cached is Some((cached_id, snapshot)) &&
    cached_id == id.value() &&
    snapshot.checkpoint == checkpoint {
    return snapshot.body
  }
  let snapshot = if self.store is Some(store) {
    with_session_lock(store, id, Exclusive, () => {
      let path = "\{store.session_dir(id)}/workspace-memory.json"
      let saved = read_memory_snapshot(path)
      if saved is Some(saved) && saved.workspace_root == self.workspace_root {
        if saved.checkpoint == checkpoint {
          return saved
        }
        guard saved.checkpoint < checkpoint else {
          fail("stale workspace memory snapshot for session \{id.value()}")
        }
      }
      ignore(ensure_session_is_current(store, session))
      let snapshot = self.load_snapshot(checkpoint)
      write_text_atomic(
        path,
        Json(snapshot).stringify(),
        dirs=store.session_dir_chain(id),
      )
      snapshot
    })
  } else {
    self.load_snapshot(checkpoint)
  }
  self.cached = Some((id.value(), snapshot))
  snapshot.body
}

///|
fn latest_memory_checkpoint(session : @agent_session.Session) -> Int32 {
  let events = session.events()
  for offset in 0..<events.length() {
    let event = events[events.length() - 1 - offset]
    if event.item() is Summary(_) {
      return event.sequence()
    }
  }
  0
}

///|
async fn read_memory_snapshot(path : String) -> WorkspaceMemorySnapshot? {
  let text = @fs.read_text(path) catch {
    @os_error.OsError(NotFound, ..) => return None
    error => raise error
  }
  let snapshot : WorkspaceMemorySnapshot = @json.from_json(@json.parse(text))
  if snapshot.body is Some(body) &&
    @utf8.encode(body).length() > WorkspaceMemoryLimit {
    fail("workspace memory snapshot exceeds the 8 KiB body limit: \{path}")
  }
  Some(snapshot)
}

///|
async fn WorkspaceMemory::load_snapshot(
  self : WorkspaceMemory,
  checkpoint : Int32,
) -> WorkspaceMemorySnapshot {
  let root = self.workspace_root
  {
    workspace_root: root,
    checkpoint,
    body: read_workspace_memory(root) catch {
      error => fail("reading workspace memory: \{error}")
    },
  }
}

///|
async fn read_workspace_memory(root : String) -> String? {
  let path = @workspace_path.resolve(root, ".openseek/memory/MEMORY.md")
  let resolved = @fs.realpath(path) catch {
    @os_error.OsError(NotFound, ..) => return None
    error => raise error
  }
  guard @workspace_path.is_under_workspace_root(root, resolved) else {
    fail("memory file resolves outside the workspace: \{path}")
  }
  let kind = @fs.kind(resolved) catch {
    @os_error.OsError(NotFound, ..) => return None
    error => raise error
  }
  guard kind is Regular else {
    fail("memory file is not a regular file: \{path}")
  }
  let bytes = @fs.read_binary(resolved) catch {
    @os_error.OsError(NotFound, ..) => return None
    error => raise error
  }
  let text = @utf8.decode(bytes, ignore_bom=true)
  let body = bounded_memory_body(memory_markdown_body(text).trim())
  if body.is_empty() {
    None
  } else {
    Some(body)
  }
}

///|
/// The optional Markdown front matter is workspace bookkeeping.
fn memory_markdown_body(text : StringView) -> StringView {
  guard text.split_once("\n") is Some((opening, rest)) &&
    opening.trim_end() == "---" else {
    return text
  }
  let mut offset = 0
  for line in rest.split("\n") {
    offset += line.length() + 1
    if line.trim_end() == "---" {
      return rest[offset.min(rest.length()):]
    }
  }
  text
}

///|
/// Keep both ends on UTF-8 boundaries within the budget, including the notice.
fn bounded_memory_body(body : StringView) -> String raise {
  let bytes = @utf8.encode(body)
  if bytes.length() <= WorkspaceMemoryLimit {
    return body.to_owned()
  }
  let marker = "\n\n[Workspace memory truncated]\n\n"
  let budget = WorkspaceMemoryLimit - @utf8.encode(marker).length()
  let mut end = budget / 2
  let mut start = bytes.length() - (budget - end)
  while end > 0 && bytes[end] >= 0x80 && bytes[end] < 0xC0 {
    end -= 1
  }
  while start < bytes.length() && bytes[start] >= 0x80 && bytes[start] < 0xC0 {
    start += 1
  }
  @utf8.decode(bytes[:end]) + marker + @utf8.decode(bytes[start:])
}
