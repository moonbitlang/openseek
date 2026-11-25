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
  guard kind == "task_finished" &&
    data is { "status": String(status), .. } &&
    status is ("failed" | "interrupted") else {
    return None
  }
  let reason = match data {
    { "reason": String(reason), .. } | { "error": String(reason), .. } => reason
    { "result": { "reason": String(reason), .. }, .. } => reason
    _ => if status == "interrupted" { "" } else { "Cloud task failed." }
  }
  Some(
    @protocol.Terminal(
      if status == "interrupted" {
        Interrupted(reason)
      } else {
        Failed(reason)
      },
    ),
  )
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
/// Cloud recovery can interrupt a task after the engine wrote its answer.
/// Keep its text as process output so the shared renderer retains this turn.
fn interrupt_answers(
  items : Array[@transcript.TranscriptItem],
  start : Int32,
) -> Unit {
  for index in start..<items.length() {
    let item = items[index]
    let kind : @transcript.ItemKind = match item.kind {
      Assistant(finished=true, reasoning~, prose~, calls~, replay~, ..) =>
        Assistant(
          reasoning~,
          prose~,
          calls~,
          replay~,
          finished=false,
          end_sequence=None,
        )
      Answer(text) =>
        Assistant(
          reasoning=None,
          prose=Some(text),
          calls=[],
          replay=false,
          finished=false,
          end_sequence=None,
        )
      _ => continue
    }
    items[index] = { ..item, kind, }
  }
}

///|
pub fn Conversation::items(
  self : Conversation,
  locale : @i18n.Locale,
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
  let mut task_start = 0
  for (task_id, kind, data, ts, engine_sequence) in service {
    guard kind is ("user" | "task_finished") else { continue }
    let new_task = task != Some(task_id)
    if new_task {
      task_start = items.length()
      native_failure = false
      task = Some(task_id)
    }
    if kind == "user" &&
      engine_sequence is Some(sequence) &&
      native.search_by(event => {
        event.sequence == sequence && event.item is @protocol.User(_)
      })
      is Some(index) {
      // Only the explicit native sequence establishes that this service
      // submission is already represented. Equal text is not ownership.
      if index >= cursor {
        ignore(append_native(items, native, cursor, index))
        if new_task {
          task_start = items.length()
        }
        ignore(append_native(items, native, index, index + 1))
        cursor = index + 1
        native_failure = false
      }
      continue
    }
    guard service_item(kind, data) is Some(item) else { continue }
    // Keep the current native turn ahead of its service result, and place
    // missing service turns before the next native User anchor.
    let mut end = cursor
    while end < native.length() && !(native[end].item is @protocol.User(_)) {
      end += 1
    }
    native_failure = append_native(items, native, cursor, end) || native_failure
    cursor = end
    if item is @protocol.User(_) {
      if new_task {
        task_start = items.length()
      }
      native_failure = false
    } else {
      if item is @protocol.Terminal(Interrupted(_)) {
        interrupt_answers(items, task_start)
      }
      if native_failure {
        continue
      }
    }
    ignore(@transcript.apply_session_item(items, item, ts?))
  }
  ignore(append_native(items, native, cursor, native.length()))
  for pending in self.pending_assistants {
    items.push(pending.item)
  }
  if (self.history_cached || !self.history_required) &&
    self.notice is Some(message) {
    items.push({
      kind: Failure(message.text(locale)),
      ts: None,
      sequence: None,
    })
  }
  items
}
