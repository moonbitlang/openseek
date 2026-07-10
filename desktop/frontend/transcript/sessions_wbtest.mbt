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
  guard items[3].kind is Assistant(false) else { fail("expected assistant") }
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
  guard items[0].kind is Assistant(true) else { fail("expected error bubble") }
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
  guard items[1].kind is Assistant(false) else {
    fail("expected context-yield guidance")
  }
  inspect(
    items[1].content,
    content="[context ceiling] continue in a new turn",
  )
}

///|
test "transcript mapping rejects structurally unusable replies" {
  assert_true(transcript_from_session_json("not json") is None)
  assert_true(transcript_from_session_json("{\"other\":1}") is None)
}
