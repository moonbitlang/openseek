// Decoding of the host's session replies. Both shapes originate in the
// engine (`sessions list --format=json` and `sessions show`) and are
// passed through
// the host verbatim; this module turns them into sidebar entries and
// transcript items, mirroring how the live event stream renders the same
// conversation.

///|
/// Parse a `list_sessions` reply into sidebar entries. `None` only for
/// structurally unusable JSON; unrecognized entries are skipped so one odd
/// session cannot blank the whole sidebar.
pub fn decode_sessions_reply(text : String) -> Array[SessionListItem]? {
  let json = @json.parse(text) catch { _ => return None }
  guard json is Object(reply) else { return None }
  guard reply.get("sessions") is Some(Array(entries)) else { return None }
  let items : Array[SessionListItem] = []
  for entry in entries {
    guard entry is Object(fields) else { continue }
    guard fields.get("id") is Some(String(id)) && !id.is_empty() else {
      continue
    }
    items.push({ id, title: json_text(fields, "title") })
  }
  Some(items)
}

///|
/// Parse a `load_session` reply (the durable session JSON) into transcript
/// items, reconstructing what the live transcript showed while the
/// conversation was running: reasoning before the answer, tool cards,
/// runtime updates, and error bubbles for turns that did not finish.
pub fn transcript_from_session_json(text : String) -> Array[TranscriptItem]? {
  let json = @json.parse(text) catch { _ => return None }
  guard json is Object(reply) else { return None }
  guard reply.get("session") is Some(Object(session)) else { return None }
  guard session.get("events") is Some(Array(events)) else { return Some([]) }
  let items : Array[TranscriptItem] = []
  for event in events {
    guard event is Object(event_fields) else { continue }
    guard event_fields.get("item") is Some(Object(item)) else { continue }
    guard item.get("kind") is Some(String(kind)) else { continue }
    guard item.get("payload") is Some(Object(payload)) else { continue }
    append_session_item(items, kind, payload)
  }
  Some(items)
}

///|
pub fn json_text(fields : Map[String, Json], key : String) -> String {
  match fields.get(key) {
    Some(String(value)) => value
    _ => ""
  }
}

///|
pub fn json_int(
  fields : Map[String, Json],
  key : String,
  fallback : Int,
) -> Int {
  match fields.get(key) {
    Some(Number(value, ..)) => value.to_int()
    _ => fallback
  }
}

///|
/// The field's text, falling back to a legacy field name when the current
/// one is absent.
fn json_first_text(
  fields : Map[String, Json],
  key : String,
  legacy : String,
) -> String {
  match fields.get(key) {
    Some(String(value)) => value
    _ => json_text(fields, legacy)
  }
}

///|
fn append_session_item(
  items : Array[TranscriptItem],
  kind : String,
  payload : Map[String, Json],
) -> Unit {
  match kind {
    "user" => {
      let content = json_text(payload, "content").trim().to_owned()
      if !content.is_empty() {
        items.push({ kind: User, content })
      }
    }
    "assistant" => {
      // Thinking-mode turns store the reasoning alongside the answer; the
      // live transcript showed it first, so replay does too.
      let reasoning = json_text(payload, "reasoning_content").trim().to_owned()
      if !reasoning.is_empty() {
        items.push({ kind: Reasoning, content: reasoning })
      }
      let content = json_text(payload, "content").trim().to_owned()
      if !content.is_empty() {
        items.push({ kind: Assistant(false), content })
      }
    }
    "tool_result" => {
      let is_error = payload.get("is_error") is Some(True)
      items.push({
        kind: Tool(
          non_empty_or(json_text(payload, "tool_name"), "tool"),
          is_error,
        ),
        content: json_text(payload, "content"),
      })
    }
    "runtime_notice" => {
      let content = json_text(payload, "content")
      if !content.trim().is_empty() {
        let update = parse_runtime_update(content)
        if !update.status.is_empty() || update.diagnostics.length() > 0 {
          items.push({
            kind: Tool(runtime_update_title(update), false),
            content: update.diagnostics.join("\n"),
          })
        }
      }
    }
    "summary" => {
      let content = json_text(payload, "content").trim().to_owned()
      if !content.is_empty() {
        items.push({ kind: Tool("summary", false), content })
      }
    }
    "terminal" => append_terminal_item(items, payload)
    _ => ()
  }
}

///|
fn append_terminal_item(
  items : Array[TranscriptItem],
  payload : Map[String, Json],
) -> Unit {
  let message = json_text(payload, "message").trim().to_owned()
  match json_text(payload, "kind") {
    // The final answer is usually already in the log as the last assistant
    // message; only a differing terminal message adds a bubble.
    "finished" =>
      if !message.is_empty() && !ends_with_assistant(items, message) {
        items.push({ kind: Assistant(false), content: message })
      }
    "aborted" =>
      items.push({
        kind: Assistant(true),
        content: if message.is_empty() {
          "aborted"
        } else {
          "aborted: " + message
        },
      })
    "interrupted" =>
      items.push({
        kind: Assistant(true),
        content: if message.is_empty() {
          "cancelled"
        } else {
          "cancelled: " + message
        },
      })
    "failed" =>
      items.push({
        kind: Assistant(true),
        content: non_empty_or(message, "failed"),
      })
    _ => ()
  }
}

///|
fn ends_with_assistant(items : Array[TranscriptItem], content : String) -> Bool {
  match items.get(items.length() - 1) {
    Some(item) => item.kind is Assistant(_) && item.content == content
    None => false
  }
}
