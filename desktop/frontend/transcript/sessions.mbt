// Projection of typed host session replies into sidebar and transcript view
// models. JSON decoding belongs to the engine or WebSocket adapter; this
// package never handles an open-ended durable-session object.

///|
/// Project a `list_sessions` reply into sidebar entries: the host groups
/// sessions by workspace store, and each entry carries its group's workspace
/// so the sidebar can section them. Failed groups remain empty; invalid engine
/// rows have already been dropped at the process adapter.
pub fn sessions_from_reply(
  reply : @desktop_protocol.SessionsReply,
) -> Array[SessionListItem] {
  let items : Array[SessionListItem] = []
  for group in reply.groups {
    for entry in group.sessions {
      guard !entry.id.is_empty() else { continue }
      items.push({
        id: entry.id,
        title: entry.title,
        workspace: group.workspace,
        workspace_name: group.name,
      })
    }
  }
  items
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
/// Project a `load_session` reply into transcript
/// items plus its watermark, reconstructing what the live transcript showed
/// while the conversation was running: reasoning before the answer, tool
/// cards, runtime updates, and error bubbles for turns that did not finish.
pub fn session_from_reply(
  reply : @desktop_protocol.LoadSessionReply,
) -> SessionLoadView {
  let items : Array[TranscriptItem] = []
  let event_boundaries : Array[(Int, Bool, Int)] = []
  let mut derived_watermark = 0
  for event in reply.session.events.unwrap_or([]) {
    // Old desktop hosts return the store JSON verbatim without a top-level
    // watermark, but every stored event already carries its sequence. Derive
    // the same frontier from those entries so reconnecting through an older
    // host cannot roll a newer client's watermark back to zero.
    if event.sequence > derived_watermark {
      derived_watermark = event.sequence
    }
    apply_session_item(items, event.item)
    event_boundaries.push(
      (
        event.sequence,
        event.item is @desktop_protocol.Terminal(_),
        items.length(),
      ),
    )
  }
  {
    items,
    watermark: reply.watermark.unwrap_or(derived_watermark),
    event_boundaries,
  }
}

///|
/// The items half of `session_from_reply`.
pub fn transcript_from_session(
  reply : @desktop_protocol.LoadSessionReply,
) -> Array[TranscriptItem] {
  session_from_reply(reply).items
}

///|
/// Project one durable session item — a `session.event` commit's
/// `{kind, payload}` — onto the transcript, appending the 0..N items it
/// renders as. The same projector `transcript_from_session_json` replays a
/// whole snapshot through, so a transcript built incrementally from commits
/// and one rebuilt from the next snapshot agree by construction.
pub fn apply_session_item(
  items : Array[TranscriptItem],
  item : @desktop_protocol.SessionItem,
) -> Unit {
  match item {
    @desktop_protocol.User(payload) => {
      let content = payload.content.trim().to_owned()
      if !content.is_empty() {
        items.push({ kind: User, content })
      }
    }
    @desktop_protocol.Assistant(payload) => {
      // Thinking-mode turns store the reasoning alongside the answer (the
      // store omits the field entirely otherwise); the live transcript
      // showed it first, so replay does too.
      if payload.reasoning_content is Some(reasoning) {
        let reasoning = reasoning.trim().to_owned()
        if !reasoning.is_empty() {
          items.push({ kind: Reasoning, content: reasoning })
        }
      }
      let content = payload.content.trim().to_owned()
      if !content.is_empty() {
        items.push({ kind: Assistant(is_danger=false), content })
      }
    }
    @desktop_protocol.ToolResult(payload) =>
      items.push({
        kind: Tool(
          name=if payload.tool_name.trim().is_empty() {
            "tool"
          } else {
            payload.tool_name
          },
          is_error=payload.is_error,
          brief=payload.brief,
        ),
        content: payload.content,
      })
    @desktop_protocol.RuntimeNotice(payload) =>
      // Goal-family notices are transport (set/clear/block markers, the
      // baseline pairing record) or model-directed text — never display
      // cards. Local prefix check: this js-only package cannot depend on
      // agent_session's parsers.
      if !payload.content.trim().is_empty() &&
        !payload.content.has_prefix("[goal") {
        let update = parse_runtime_update(payload.content)
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
    @desktop_protocol.Summary(payload) => {
      let content = payload.content.trim().to_owned()
      if !content.is_empty() {
        items.push({ kind: Summary, content })
      }
    }
    @desktop_protocol.Terminal(terminal) =>
      SessionTerminalProjection(terminal).append_to(items)
  }
}

///|
/// One typed terminal item projected into its optional final/error bubble.
priv struct SessionTerminalProjection(@desktop_protocol.SessionTerminal)

///|
fn SessionTerminalProjection::append_to(
  self : SessionTerminalProjection,
  items : Array[TranscriptItem],
) -> Unit {
  let (kind, message) = match self.0 {
    @desktop_protocol.Finished(message) => ("finished", message)
    @desktop_protocol.Aborted(message) => ("aborted", message)
    @desktop_protocol.Interrupted(message) => ("interrupted", message)
    @desktop_protocol.Failed(message) => ("failed", message)
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
test "session list projection preserves grouping and skips empty ids" {
  let items = sessions_from_reply({
    groups: [
      {
        workspace: "",
        name: "",
        session_root: "/home/user/.openseek",
        error: "",
        sessions: [
          { id: "desktop-b", title: Some("newest") },
          { id: "", title: Some("no id") },
        ],
      },
      {
        workspace: "/home/user/proj",
        name: "proj",
        session_root: "/home/user/proj/.openseek",
        error: "",
        sessions: [{ id: "tui-a", title: Some("") }],
      },
    ],
  })
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
fn session_reply(
  events_json : String,
) -> @desktop_protocol.LoadSessionReply raise {
  let prefix =
    #|{"session":{"version":1,"id":"desktop-x","system_prompt":"system","events":[
  let suffix =
    #|]}}
  @json.from_json(@json.parse(prefix + events_json + suffix))
}

///|
test "session load derives an old host's missing watermark from event sequences" {
  let events =
    #|{"sequence":1,"item":{"kind":"user","payload":{"content":"question"}}},
    #|{"sequence":4,"item":{"kind":"terminal","payload":{"kind":"finished","message":"answer"}}}
  let view = session_from_reply(session_reply(events))
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
  let event =
    #|{"sequence":9,"item":{"kind":"user","payload":{"content":"question"}}}
  let reply = session_reply(event)
  let view = session_from_reply({ ..reply, watermark: Some(7) })
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
  let items = transcript_from_session(session_reply(events))
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
  let items = transcript_from_session(session_reply(events))
  inspect(items.length(), content="1")
}

///|
test "transcript mapping renders non-finished terminals as error bubbles" {
  let events =
    #|{"sequence":1,"item":{"kind":"terminal","payload":{"kind":"interrupted","message":""}}},
    #|{"sequence":2,"item":{"kind":"terminal","payload":{"kind":"aborted","message":"the agent gave up"}}},
    #|{"sequence":3,"item":{"kind":"terminal","payload":{"kind":"failed","message":"engine error"}}}
  let items = transcript_from_session(session_reply(events))
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
  let items = transcript_from_session(session_reply(events))
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
  let items = transcript_from_session(session_reply(events))
  inspect(items.length(), content="2")
  guard items[0].kind is Summary else { fail("expected checkpoint summary") }
  inspect(items[0].content, content="checkpoint recap")
  guard items[1].kind is Assistant(is_danger=false) else {
    fail("expected context-yield guidance")
  }
  inspect(items[1].content, content="[context ceiling] continue in a new turn")
}
