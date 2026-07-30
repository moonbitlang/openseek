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
/// A decoded `session.load` reply: the transcript the snapshot renders as,
/// and the highest event sequence it contains — the client's starting
/// watermark, deciding which later `session.event` commits are already in
/// the snapshot. An explicit top-level watermark is authoritative; replies
/// from older hosts derive it from the maximum stored event sequence instead.
/// An empty record therefore remains at 0 in either shape.
pub struct SessionLoadView {
  items : Array[TranscriptItem]
  watermark : Int
  // Durable event boundaries retained alongside the display projection.
  // Each tuple is `(event sequence, is terminal, projected item count after
  // the event)`. An event may add no bubble, so an exact lifecycle/EOF
  // boundary cannot be reconstructed from `items` alone.
  event_boundaries : Array[(Int, Bool, Int)]
}

///|
/// Parse a `load_session` reply (the durable session JSON) into transcript
/// items plus its watermark, reconstructing what the live transcript showed
/// while the conversation was running: reasoning before the answer, tool
/// cards, runtime updates, and error bubbles for turns that did not finish.
/// `None` only for structurally unusable JSON — the caller reports that as a
/// failed load, never as an empty conversation.
pub fn decode_session_load_reply(text : String) -> SessionLoadView? {
  let json = @json.parse(text) catch { _ => return None }
  guard json is Object(reply) else { return None }
  guard reply.get("session") is Some(Object(session)) else { return None }
  let explicit_watermark = @jsonx.json_int(reply, "watermark")
  guard session.get("events") is Some(Array(events)) else {
    return Some({
      items: [],
      watermark: explicit_watermark.unwrap_or(0),
      event_boundaries: [],
    })
  }
  let items : Array[TranscriptItem] = []
  let event_boundaries : Array[(Int, Bool, Int)] = []
  let mut derived_watermark = 0
  for event in events {
    guard event is Object(event_fields) else { continue }
    // Old desktop hosts return the store JSON verbatim without a top-level
    // watermark, but every stored event already carries its sequence. Derive
    // the same frontier from those entries so reconnecting through an older
    // host cannot roll a newer client's watermark back to zero.
    let sequence = @jsonx.json_int(event_fields, "sequence")
    if sequence is Some(sequence) && sequence > derived_watermark {
      derived_watermark = sequence
    }
    guard event_fields.get("item") is Some(Object(item)) else { continue }
    guard item.get("kind") is Some(String(kind)) else { continue }
    guard item.get("payload") is Some(Object(payload)) else { continue }
    append_session_item(items, kind, payload)
    if sequence is Some(sequence) {
      event_boundaries.push((sequence, kind == "terminal", items.length()))
    }
  }
  Some({
    items,
    watermark: explicit_watermark.unwrap_or(derived_watermark),
    event_boundaries,
  })
}

///|
/// The items half of `decode_session_load_reply`, kept for callers (and
/// tests) that predate watermarks.
pub fn transcript_from_session_json(text : String) -> Array[TranscriptItem]? {
  decode_session_load_reply(text).map(view => view.items)
}

///|
/// Project one durable session item — a `session.event` commit's
/// `{kind, payload}` — onto the transcript, appending the 0..N items it
/// renders as. The same projector `transcript_from_session_json` replays a
/// whole snapshot through, so a transcript built incrementally from commits
/// and one rebuilt from the next snapshot agree by construction.
pub fn apply_session_item(
  items : Array[TranscriptItem],
  kind : String,
  payload : Map[String, Json],
) -> Unit {
  append_session_item(items, kind, payload)
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
          items.push({ kind: Assistant(is_danger=false), content })
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
      // Goal-family notices are transport (set/clear/block markers, the
      // baseline pairing record) or model-directed text — never display
      // cards. Local prefix check: this js-only package cannot depend on
      // agent_session's parsers.
      if content is Some(content) &&
        !content.trim().is_empty() &&
        !content.has_prefix("[goal") {
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
        items.push({ kind: Assistant(is_danger=false), content: message })
      }
    "aborted" =>
      items.push({
        kind: Assistant(is_danger=true),
        content: if message.is_empty() {
          "aborted"
        } else {
          "aborted: \{message}"
        },
      })
    "interrupted" =>
      items.push({
        kind: Assistant(is_danger=true),
        content: if message.is_empty() {
          "cancelled"
        } else {
          "cancelled: \{message}"
        },
      })
    "failed" =>
      items.push({
        kind: Assistant(is_danger=true),
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
  items is [.., item] && item.kind is Assistant(_) && item.content == content
}

// Tests for decoding the host's session replies: the sidebar list and the
// durable-session-to-transcript mapping.

///|
test "session list decoding keeps well-formed entries and skips the rest" {
  let text =
    #|{"groups":[
    #|  {"workspace":"","name":"","session_root":"/home/user/.openseek","error":"","sessions":[
    #|    {"id":"desktop-b","title":"newest","updated_at_ms":2000,"last_sequence":4},
    #|    {"id":"","title":"no id"},
    #|    "not an object"
    #|  ]},
    #|  {"workspace":"/home/user/proj","name":"proj","session_root":"/home/user/proj/.openseek","error":"","sessions":[
    #|    {"id":"tui-a","title":""}
    #|  ]},
    #|  {"workspace":"/home/user/broken","name":"broken","session_root":"/home/user/broken/.openseek","error":"session list failed","sessions":[]}
    #|]}
  guard decode_sessions_reply(text) is Some(items) else {
    fail("expected a decoded list")
  }
  inspect(items.length(), content="2")
  inspect(items[0].id, content="desktop-b")
  assert_true(items[0].title is Some("newest"))
  inspect(items[0].workspace, content="")
  inspect(items[1].id, content="tui-a")
  // The engine always writes `title`; "" is its value for a session with no
  // user message yet.
  assert_true(items[1].title is Some(""))
  inspect(items[1].workspace, content="/home/user/proj")
  inspect(items[1].workspace_name, content="proj")
}

///|
test "session list decoding rejects structurally unusable replies" {
  assert_true(decode_sessions_reply("not json") is None)
  assert_true(decode_sessions_reply("{\"groups\":42}") is None)
  assert_true(decode_sessions_reply("[]") is None)
}

///|
fn session_reply(events_json : String) -> String {
  let prefix =
    #|{"session":{"version":1,"id":"desktop-x","system_prompt":"system","events":[
  let suffix =
    #|]}}
  prefix + events_json + suffix
}

///|
test "session load derives an old host's missing watermark from event sequences" {
  let events =
    #|{"sequence":1,"item":{"kind":"user","payload":{"content":"question"}}},
    #|{"sequence":4,"item":{"kind":"terminal","payload":{"kind":"finished","message":"answer"}}}
  guard decode_session_load_reply(session_reply(events)) is Some(view) else {
    fail("expected a decoded session")
  }
  inspect(view.watermark, content="4")
  inspect(view.event_boundaries.length(), content="2")
  let (first_sequence, first_terminal, first_boundary) = view.event_boundaries[0]
  inspect(first_sequence, content="1")
  assert_false(first_terminal)
  inspect(first_boundary, content="1")
  let (sequence, is_terminal, boundary) = view.event_boundaries[1]
  inspect(sequence, content="4")
  assert_true(is_terminal)
  inspect(boundary, content="2")
}

///|
test "an explicit session watermark remains authoritative" {
  let text =
    #|{"watermark":7,"session":{"version":1,"id":"desktop-x","events":[
    #|{"sequence":9,"item":{"kind":"user","payload":{"content":"question"}}}
    #|]}}
  guard decode_session_load_reply(text) is Some(view) else {
    fail("expected a decoded session")
  }
  inspect(view.watermark, content="7")
  inspect(view.event_boundaries.length(), content="1")
}

///|
test "transcript mapping replays a finished conversation" {
  let events =
    #|{"sequence":1,"item":{"kind":"user","payload":{"content":"  question  "}}},
    #|{"sequence":2,"item":{"kind":"tool_result","payload":{"tool_call_id":"c1","tool_name":"shell","content":"output","is_error":true,"brief":"ran ls → exit 1"}}},
    #|{"sequence":3,"item":{"kind":"assistant","payload":{"content":"answer","tool_calls":[],"reasoning_content":"thought"}}},
    #|{"sequence":4,"item":{"kind":"terminal","payload":{"kind":"finished","message":"answer"}}}
  guard transcript_from_session_json(session_reply(events)) is Some(items) else {
    fail("expected transcript items")
  }
  inspect(items.length(), content="4")
  guard items[0].kind is User else { fail("expected user item") }
  inspect(items[0].content, content="question")
  guard items[1].kind is Tool(name="shell", is_error=true, brief=Some(brief)) else {
    fail("expected tool card")
  }
  inspect(brief, content="ran ls → exit 1")
  inspect(items[1].content, content="output")
  guard items[2].kind is Reasoning else { fail("expected reasoning item") }
  inspect(items[2].content, content="thought")
  guard items[3].kind is Assistant(is_danger=false) else {
    fail("expected assistant")
  }
  inspect(items[3].content, content="answer")
}

///|
test "transcript mapping deduplicates the finished answer" {
  let events =
    #|{"sequence":1,"item":{"kind":"assistant","payload":{"content":"answer","tool_calls":[]}}},
    #|{"sequence":2,"item":{"kind":"terminal","payload":{"kind":"finished","message":"answer"}}}
  guard transcript_from_session_json(session_reply(events)) is Some(items) else {
    fail("expected transcript items")
  }
  inspect(items.length(), content="1")
}

///|
test "transcript mapping renders non-finished terminals as error bubbles" {
  let events =
    #|{"sequence":1,"item":{"kind":"terminal","payload":{"kind":"interrupted","message":""}}},
    #|{"sequence":2,"item":{"kind":"terminal","payload":{"kind":"aborted","message":"the agent gave up"}}},
    #|{"sequence":3,"item":{"kind":"terminal","payload":{"kind":"failed","message":"engine error"}}}
  guard transcript_from_session_json(session_reply(events)) is Some(items) else {
    fail("expected transcript items")
  }
  inspect(items.length(), content="3")
  guard items[0].kind is Assistant(is_danger=true) else {
    fail("expected error bubble")
  }
  inspect(items[0].content, content="cancelled")
  inspect(items[1].content, content="aborted: the agent gave up")
  inspect(items[2].content, content="engine error")
}

///|
test "transcript mapping keeps summaries and meaningful runtime notices" {
  let events =
    #|{"sequence":1,"item":{"kind":"summary","payload":{"content":"earlier turns compacted","from_sequence":1,"to_sequence":8}}},
    #|{"sequence":2,"item":{"kind":"runtime_notice","payload":{"content":"[moon_check update]\nstatus=failed\nmain.mbt:1 error"}}},
    #|{"sequence":3,"item":{"kind":"runtime_notice","payload":{"content":""}}}
  guard transcript_from_session_json(session_reply(events)) is Some(items) else {
    fail("expected transcript items")
  }
  inspect(items.length(), content="2")
  guard items[0].kind is Summary else { fail("expected summary") }
  guard items[1].kind is Tool(name="moon_check failed", is_error=false, ..) else {
    fail("expected runtime notice card")
  }
  inspect(items[1].content, content="main.mbt:1 error")
}

///|
test "transcript mapping replays a context checkpoint and yield guidance" {
  let events =
    #|{"sequence":1,"item":{"kind":"summary","payload":{"content":"checkpoint recap","from_sequence":1,"to_sequence":8}}},
    #|{"sequence":2,"item":{"kind":"terminal","payload":{"kind":"finished","message":"[context ceiling] continue in a new turn"}}}
  guard transcript_from_session_json(session_reply(events)) is Some(items) else {
    fail("expected transcript items")
  }
  inspect(items.length(), content="2")
  guard items[0].kind is Summary else { fail("expected checkpoint summary") }
  inspect(items[0].content, content="checkpoint recap")
  guard items[1].kind is Assistant(is_danger=false) else {
    fail("expected context-yield guidance")
  }
  inspect(items[1].content, content="[context ceiling] continue in a new turn")
}

///|
test "transcript mapping rejects structurally unusable replies" {
  assert_true(transcript_from_session_json("not json") is None)
  assert_true(transcript_from_session_json("{\"other\":1}") is None)
}
