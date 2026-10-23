///|
fn Conversation::session_view(
  self : Conversation,
) -> @transcript.SessionLoadView {
  @transcript.session_from_reply({
    session: self.document,
    watermark: None,
    prediction: None,
  })
}

///|
/// The service can save a prompt or fail to start an engine before any native
/// record exists. Supplement only those records; assistant/tool projection
/// remains owned by the native session document.
fn service_item(kind : String, data : Json) -> @protocol.SessionItem? {
  if kind == "user" {
    let item : @protocol.SessionItem = @json.from_json({
      "kind": "user",
      "payload": data,
    }) catch {
      _ => return None
    }
    return if item is @protocol.User(_) { Some(item) } else { None }
  }
  guard kind == "task_finished" && data is { "status": "failed", .. } else {
    return None
  }
  let reason = match data {
    { "reason": String(reason), .. } | { "error": String(reason), .. } => reason
    { "result": { "reason": String(reason), .. }, .. } => reason
    _ => "Cloud task failed."
  }
  Some(@protocol.Terminal(@protocol.Failed(reason)))
}

///|
fn append_native(
  items : Array[@transcript.TranscriptItem],
  events : Array[@protocol.SessionEvent],
  start : Int32,
  end : Int32,
) -> Bool {
  let mut failed = false
  for index in start..<end {
    let event = events[index]
    ignore(
      @transcript.apply_session_item(
        items,
        event.item,
        ts?=event.ts,
        sequence=event.sequence,
      ),
    )
    if event.item is @protocol.Terminal(terminal) &&
      !(terminal is (@protocol.Finished(_) | @protocol.ContextYield(_))) {
      failed = true
    }
  }
  failed
}

///|
pub fn Conversation::items(
  self : Conversation,
) -> Array[@transcript.TranscriptItem] {
  let native = self.document.events.unwrap_or([])
  let items : Array[@transcript.TranscriptItem] = []
  let service = self.records.map(record => {
    (record.task_id, record.kind, record.data, Some(record.created_at))
  })
  for event in self.events {
    if !self.records.any(record => {
        record.task_id == event.task_id && record.kind == event.kind
      }) {
      service.push((event.task_id, event.kind, event.data, None))
    }
  }
  let mut cursor = 0
  let mut task : String? = None
  let mut native_failure = false
  for (task_id, kind, data, ts) in service {
    guard service_item(kind, data) is Some(item) else { continue }
    if task != Some(task_id) {
      native_failure = false
      task = Some(task_id)
    }
    if item is @protocol.User(user) {
      let mut matched : Int32? = None
      for index in cursor..<native.length() {
        guard native[index].item is @protocol.User(saved) else { continue }
        let same = match (user.submission_id, saved.submission_id) {
          (Some(id), Some(saved_id)) => id == saved_id
          _ => user.content == saved.content
        }
        if same {
          matched = Some(index)
          break
        }
      }
      if matched is Some(index) {
        ignore(append_native(items, native, cursor, index + 1))
        cursor = index + 1
        native_failure = false
        continue
      }
    }
    // Keep the current native turn ahead of its service result, and place
    // missing service turns before the next native User anchor.
    let mut end = cursor
    while end < native.length() && !(native[end].item is @protocol.User(_)) {
      end += 1
    }
    native_failure = append_native(items, native, cursor, end) || native_failure
    cursor = end
    if item is @protocol.User(_) {
      native_failure = false
    } else if native_failure {
      continue
    }
    ignore(@transcript.apply_session_item(items, item, ts?))
  }
  ignore(append_native(items, native, cursor, native.length()))
  if !self.history_required && self.notice is Some(message) {
    items.push({ kind: Failure(message), ts: None, sequence: None, })
  }
  items
}
