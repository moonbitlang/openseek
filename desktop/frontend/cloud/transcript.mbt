///|
/// Normalize visible Cloud messages for the transcript and downloaded export.
fn normalized_item(kind : String, data : Json) -> Json? {
  match kind {
    "user" | "tool_result" => Some({ "kind": Json(kind), "payload": data })
    "assistant_message" => {
      // The visualizer's durable AssistantMessage requires tool_calls.
      let payload = match data {
        Object(fields) if fields.get("tool_calls") is None => {
          let fields = fields.copy()
          fields["tool_calls"] = Json::array([])
          Json(fields)
        }
        _ => data
      }
      Some({ "kind": "assistant", "payload": payload })
    }
    "tool_call" => {
      let call : Json = match data {
        {
          "id": String(id),
          "function": {
            "name": String(name),
            "arguments": String(arguments),
            ..
          },
          ..
        } =>
          { "id": Json(id), "name": Json(name), "arguments": Json(arguments) }
        _ => data
      }
      Some({
        "kind": "assistant",
        "payload": { "content": "", "tool_calls": [call] },
      })
    }
    "task_finished" =>
      match data {
        {
          "status": "completed",
          "result": { "output": { "answer": String(answer), .. }, .. },
          ..
        } =>
          Some({
            "kind": "terminal",
            "payload": { "kind": "finished", "message": Json(answer) },
          })
        _ => None
      }
    _ => None
  }
}

///|
/// Adapt Cloud's flattened events to the shared durable-message projector.
/// Record IDs and task-local event sequences are not host durable sequences.
fn append_item(
  items : Array[@transcript.TranscriptItem],
  kind : String,
  data : Json,
  ts : Double?,
) -> Unit {
  let normalized = normalized_item(kind, data)
  if normalized is Some(normalized) {
    let item : @protocol.SessionItem = @json.from_json(normalized) catch {
      _ => @protocol.Unknown(normalized)
    }
    if !(item is @protocol.Unknown(_)) {
      ignore(@transcript.apply_session_item(items, item, ts?))
      return
    }
  }
  let kind : @transcript.ItemKind = if kind == "task_finished" {
    let status = match data {
      { "status": String(status), .. } => Some(status)
      _ => None
    }
    if status == Some("completed") {
      TurnEnd
    } else {
      Notice(
        label="Task " + status.unwrap_or("ended"),
        brief=None,
        is_error=status == Some("failed") || status == Some("interrupted"),
        body=Some(data.stringify(indent=2)),
      )
    }
  } else if kind is ("compaction_failed" | "auto_compaction_failed") &&
    data is { "error": String(error), .. } {
    Failure(error)
  } else {
    Notice(
      label=kind,
      brief=None,
      is_error=false,
      body=Some(data.stringify(indent=2)),
    )
  }
  items.push({ kind, ts, sequence: None, })
}

///|
pub fn Conversation::items(
  self : Conversation,
) -> Array[@transcript.TranscriptItem] {
  let items : Array[@transcript.TranscriptItem] = []
  for record in self.records {
    append_item(items, record.kind, record.data, Some(record.created_at))
  }
  for event in self.events {
    append_item(items, event.kind, event.data, None)
  }
  if !self.history_required && self.notice is Some(message) {
    items.push({ kind: Failure(message), ts: None, sequence: None, })
  }
  items
}

///|
/// Match occurrences against durable records, preserving repeated equal messages.
/// A history read and its live events may describe the same saved message.
fn Conversation::events_not_in(
  self : Conversation,
  records : Array[Record],
) -> Array[Event] {
  let consumed : Array[Int32] = []
  self.events.filter(event => {
    for index in 0..<records.length() {
      let record = records[index]
      if !consumed.contains(index) &&
        record.task_id == event.task_id &&
        record.kind == event.kind &&
        record.data == event.data {
        consumed.push(index)
        return false
      }
    }
    true
  })
}
