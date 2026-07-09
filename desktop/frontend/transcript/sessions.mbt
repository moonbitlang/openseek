// Decoding of the host's session replies. Both shapes originate in the
// engine (`sessions list --format=json` and `sessions show`) and are
// passed through
// the host verbatim; this module turns them into sidebar entries and
// transcript items, mirroring how the live event stream renders the same
// conversation.

///|
/// Parse a `list_sessions` reply into sidebar entries: the host groups
/// sessions by workspace store, and each entry carries its group's workspace
/// so the sidebar can section them. `None` only for structurally unusable
/// JSON; unrecognized entries (and failed groups — their error is the group's
/// own affair) are skipped so one odd session cannot blank the whole sidebar.
pub fn decode_sessions_reply(text : String) -> Array[SessionListItem]? {
  let json = @json.parse(text) catch { _ => return None }
  guard json is Object(reply) else { return None }
  guard reply.get("groups") is Some(Array(groups)) else { return None }
  let items : Array[SessionListItem] = []
  for group in groups {
    guard group is Object(group_fields) else { continue }
    // The host emits both group fields unconditionally ("" names the global
    // scratch group); a group missing either is malformed and skipped whole.
    guard @jsonx.json_text(group_fields, "workspace") is Some(workspace) &&
      @jsonx.json_text(group_fields, "name") is Some(workspace_name) else {
      continue
    }
    guard group_fields.get("sessions") is Some(Array(entries)) else { continue }
    for entry in entries {
      guard entry is Object(fields) else { continue }
      guard fields.get("id") is Some(String(id)) && !id.is_empty() else {
        continue
      }
      items.push({
        id,
        title: @jsonx.json_text(fields, "title"),
        workspace,
        workspace_name,
      })
    }
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
fn append_session_item(
  items : Array[TranscriptItem],
  kind : String,
  payload : Map[String, Json],
) -> Unit {
  // Every payload writes `content` unconditionally (the store's structs have
  // no optional content); an item missing one is malformed and dropped.
  // Whether *blank* content still earns a bubble is per-kind display policy.
  let content = @jsonx.json_text(payload, "content")
  match kind {
    "user" =>
      if content is Some(content) {
        let content = content.trim().to_owned()
        if !content.is_empty() {
          items.push({ kind: User, content })
        }
      }
    "assistant" => {
      // Thinking-mode turns store the reasoning alongside the answer (the
      // store omits the field entirely otherwise); the live transcript
      // showed it first, so replay does too.
      if @jsonx.json_text(payload, "reasoning_content") is Some(reasoning) {
        let reasoning = reasoning.trim().to_owned()
        if !reasoning.is_empty() {
          items.push({ kind: Reasoning, content: reasoning })
        }
      }
      if content is Some(content) {
        let content = content.trim().to_owned()
        if !content.is_empty() {
          items.push({ kind: Assistant(false), content })
        }
      }
    }
    "tool_result" => {
      guard @jsonx.json_text(payload, "tool_name") is Some(tool_name) &&
        @jsonx.json_bool(payload, "is_error") is Some(is_error) &&
        content is Some(content) else {
        return
      }
      items.push({
        kind: Tool(
          name=if tool_name.trim().is_empty() { "tool" } else { tool_name },
          is_error~,
          brief=@jsonx.json_text(payload, "brief"),
        ),
        content,
      })
    }
    "runtime_notice" =>
      if content is Some(content) && !content.trim().is_empty() {
        let update = parse_runtime_update(content)
        if !update.status.is_empty() || update.diagnostics.length() > 0 {
          items.push({
            kind: Tool(
              name=runtime_update_title(update),
              is_error=false,
              brief=None,
            ),
            content: update.diagnostics.join("\n"),
          })
        }
      }
    "summary" =>
      if content is Some(content) {
        let content = content.trim().to_owned()
        if !content.is_empty() {
          items.push({ kind: Summary, content })
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
  // The store's terminal item always carries both fields (`message` may be
  // blank — a turn that finished without a distinct closing line).
  guard @jsonx.json_text(payload, "kind") is Some(kind) &&
    @jsonx.json_text(payload, "message") is Some(message) else {
    return
  }
  let message = message.trim().to_owned()
  match kind {
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
        content: if message.is_empty() {
          "failed"
        } else {
          message
        },
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
