///|
fn Conversation::session_view(
  self : Conversation,
) -> @transcript.SessionLoadView {
  @transcript.session_from_reply({
    session: self.document,
    watermark: None,
    prediction: self.prediction,
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
    (
      record.task_id,
      record.kind,
      record.data,
      Some(record.created_at),
      record.engine_sequence,
    )
  })
  for event in self.events {
    if !self.records.any(record => {
        record.task_id == event.task_id && record.kind == event.kind
      }) {
      service.push((event.task_id, event.kind, event.data, None, None))
    }
  }
  let mut cursor = 0
  let mut task : String? = None
  let mut native_failure = false
  for (task_id, kind, data, ts, engine_sequence) in service {
    guard service_item(kind, data) is Some(item) else { continue }
    if kind == "task_finished" &&
      self.terminal_record is Some((native_task, sequence)) &&
      native_task == task_id &&
      native.search_by(event => event.sequence == sequence) is Some(index) &&
      index >= cursor {
      // The live terminal identifies its own turn even before history
      // supplies a service User anchor or after native steering inputs.
      ignore(append_native(items, native, cursor, index))
      let failed = append_native(items, native, index, index + 1)
      cursor = index + 1
      if !failed {
        ignore(@transcript.apply_session_item(items, item, ts?))
      }
      continue
    }
    if task != Some(task_id) {
      native_failure = false
      task = Some(task_id)
    }
    if item is @protocol.User(user) &&
      native.search_by(event => {
        event.item is @protocol.User(native_user) &&
        (
          engine_sequence == Some(event.sequence) ||
          (
            user.submission_id is Some(_) &&
            user.submission_id == native_user.submission_id
          )
        )
      })
      is Some(index) {
      // Use durable identity to reconcile the service and native copies.
      if index >= cursor {
        ignore(append_native(items, native, cursor, index + 1))
        cursor = index + 1
        native_failure = false
      }
      continue
    }
    // Keep the current native turn ahead of its service result, and place
    // missing service turns before the next native User anchor.
    let mut end = cursor
    while end < native.length() {
      let event = native[end]
      if event.item is @protocol.User(_) {
        // A service-only prompt may be recovered after a prior turn
        // arrived through SSE without a service-side history anchor.
        guard item is @protocol.User(_) &&
          ts is Some(submitted) &&
          event.ts is Some(saved) &&
          saved > 0.0 &&
          saved < submitted else {
          break
        }
      }
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
  if self.sending && self.pending is Some(pending) {
    ignore(
      @transcript.apply_session_item(
        items,
        @protocol.User({
          content: pending.content,
          submission_id: Some(pending.id),
        }),
      ),
    )
  }
  if !self.history_required && self.notice is Some(message) {
    items.push({ kind: Failure(message), ts: None, sequence: None, })
  }
  items
}
