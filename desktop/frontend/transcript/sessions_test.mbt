///|
/// The items half of `session_from_reply`.
fn transcript_from_session(
  reply : @desktop_protocol.LoadSessionReply,
) -> Array[@transcript.TranscriptItem] {
  @transcript.session_from_reply(reply).items
}

///|
test "session list projection preserves grouping and skips empty ids" {
  let items = @transcript.sessions_from_reply(
    {
      groups: [
        {
          workspace: "/home/user/first",
          name: "first",
          session_root: "/home/user/first/.openseek",
          error: "",
          sessions: [
            {
              id: "desktop-b",
              title: Some("newest"),
              updated_at_ms: Some(2.0),
            },
            { id: "", title: Some("no id"), updated_at_ms: None, },
          ],
        },
        {
          workspace: "/home/user/proj",
          name: "proj",
          session_root: "/home/user/proj/.openseek",
          error: "",
          sessions: [{ id: "tui-a", title: Some(""), updated_at_ms: None, }],
        },
      ],
    },
    @interop.ChannelId::Local,
  )
  inspect(items.length(), content="2")
  inspect(items[0].id, content="desktop-b")
  assert_true(items[0].title is Some("newest"))
  assert_true(items[0].updated_at_ms is Some(2.0))
  inspect(items[0].workspace.path, content="/home/user/first")
  inspect(items[1].id, content="tui-a")
  // The engine always writes `title`; "" is its value for a session with no
  // user message yet.
  assert_true(items[1].title is Some(""))
  inspect(items[1].workspace.path, content="/home/user/proj")
  inspect(items[1].workspace_name, content="proj")
}

///|
test "a group naming no readable workspace contributes no rows" {
  let items = @transcript.sessions_from_reply(
    {
      groups: [
        {
          workspace: "",
          name: "",
          session_root: "/home/user/.openseek",
          error: "",
          sessions: [
            { id: "desktop-b", title: Some("newest"), updated_at_ms: None, },
          ],
        },
      ],
    },
    @interop.ChannelId::Local,
  )
  assert_true(items.is_empty())
}

///|
test "a sub-run's progress routes by its child session, not its bare id" {
  // `sr-1` is only unique inside its parent engine, so the child session id
  // is what names the conversation a progress push belongs to.
  assert_eq(@transcript.subrun_parent("desktop-a-sr-1"), Some("desktop-a"))
  assert_eq(@transcript.subrun_parent("desktop-b-sr-1"), Some("desktop-b"))
  // An ordinary session is nobody's child, so nothing routes to it.
  assert_eq(@transcript.subrun_parent("desktop-a"), None)
}

///|
test "a sub-run brief names the child sessions its card links to" {
  // The stamp the review tool writes: `"<tool> sr-N (…)"`.
  assert_eq(
    @transcript.subrun_child_sessions(
      "review",
      "review sr-2 (2 finding(s), 7 step(s))",
      parent="run",
    ),
    ["run-sr-2"],
  )
  assert_eq(
    @transcript.subrun_child_sessions(
      "review",
      "review sr-11 (ok)",
      parent="desktop-a",
    ),
    ["desktop-a-sr-11"],
  )
  // Round-trips with the inverse: the id this yields is the id whose row is
  // labelled with the `sr-N` the brief carried.
  assert_eq(@transcript.subrun_label("run-sr-2"), Some("sr-2"))
  assert_eq(@transcript.subrun_parent("run-sr-2"), Some("run"))
}

///|
test "a brief that does not name a sub-run yields no link" {
  // Not a sub-run tool, however the brief happens to read.
  assert_eq(
    @transcript.subrun_child_sessions("read", "read sr-2", parent="run"),
    [],
  )
  // The tool is right but the brief names no child.
  assert_eq(
    @transcript.subrun_child_sessions("review", "review", parent="run"),
    [],
  )
  assert_eq(
    @transcript.subrun_child_sessions(
      "review",
      "review (budget exhausted)",
      parent="run",
    ),
    [],
  )
  // `sr-` with nothing, or with something that is not an ordinal, is not a
  // sub-run id — linking on it would offer a session that cannot exist.
  assert_eq(
    @transcript.subrun_child_sessions("review", "review sr- (x)", parent="run"),
    [],
  )
  assert_eq(
    @transcript.subrun_child_sessions("review", "review sr-x (x)", parent="run"),
    [],
  )
  assert_eq(
    @transcript.subrun_child_sessions(
      "review",
      "review sr-2x (x)",
      parent="run",
    ),
    [],
  )
  // Bounded exactly as `split_child_session_id` bounds it, so this never
  // offers an id that parser refuses to read back.
  assert_eq(
    @transcript.subrun_child_sessions(
      "review",
      "review sr-1234567890 (x)",
      parent="run",
    ),
    [],
  )
  assert_eq(@transcript.subrun_parent("run-sr-1234567890"), None)
  // An unsaved conversation has no id to hang a child off.
  assert_eq(
    @transcript.subrun_child_sessions("review", "review sr-2 (x)", parent=""),
    [],
  )
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
  let reply = session_reply(events)
  let view = @transcript.session_from_reply(reply)
  inspect(view.watermark, content="4")
  inspect(view.items.length(), content="2")
}

///|
test "projected rows carry their event's stamp, tool rows the call's own" {
  let events =
    #|{"sequence":1,"ts":1781144351123,"item":{"kind":"user","payload":{"content":"question"}}},
    #|{"sequence":2,"ts":1781144352000,"item":{"kind":"assistant","payload":{"content":"answer","tool_calls":[{"id":"c1","name":"read","arguments":"{}"}]}}},
    #|{"sequence":3,"ts":1781144399000,"item":{"kind":"tool_result","payload":{"tool_call_id":"c1","tool_name":"read","content":"out","is_error":false}}}
  let items = @transcript.session_from_reply(session_reply(events)).items
  inspect(items.length(), content="2")
  assert_true(items[0].ts is Some(1781144351123))
  assert_true(items[0].sequence is Some(1))
  // The result filled the call inside its response; the response is dated
  // when the call was made, not when its output came back — and keeps that
  // event's sequence for the same reason.
  guard items[1].kind is @transcript.Assistant(calls=[call], ..) else {
    fail("expected the response with its one call")
  }
  assert_true(
    call.outcome is @transcript.Done(content=Content([Text("out")]), ..),
  )
  assert_true(items[1].ts is Some(1781144352000))
  assert_true(items[1].sequence is Some(2))
}

///|
test "rows from a store written without stamps stay undated" {
  let events =
    #|{"sequence":1,"item":{"kind":"user","payload":{"content":"question"}}}
  let items = @transcript.session_from_reply(session_reply(events)).items
  assert_true(items[0].ts is None)
  // The stamp is optional in old stores; the sequence never is.
  assert_true(items[0].sequence is Some(1))
}

///|
test "an explicit session watermark remains authoritative" {
  let event =
    #|{"sequence":9,"item":{"kind":"user","payload":{"content":"question"}}}
  let reply = session_reply(event)
  let view = @transcript.session_from_reply({ ..reply, watermark: Some(7), })
  inspect(view.watermark, content="7")
}

///|
test "session load keeps unknown items without hiding known transcript" {
  let events =
    #|{"sequence":1,"item":{"kind":"user","payload":{"content":"question"}}},
    #|{"sequence":2,"item":{"kind":"future_item","payload":{"value":42},"future_field":true}},
    #|{"sequence":3,"item":{"kind":"assistant","payload":{"content":"answer","tool_calls":[]}}}
  let reply = session_reply(events)
  let view = @transcript.session_from_reply(reply)
  inspect(view.watermark, content="3")
  inspect(view.items.length(), content="2")
  assert_eq(view.items[0].text(), Some("question"))
  assert_eq(view.items[1].text(), Some("answer"))
}

///|
test "a terminal payload this build cannot read projects no row" {
  let events =
    #|{"sequence":1,"item":{"kind":"user","payload":{"content":"question"}}},
    #|{"sequence":2,"item":{"kind":"terminal","payload":{"kind":"future_terminal","message":"later"}}}
  let view = @transcript.session_from_reply(session_reply(events))
  inspect(view.items.length(), content="1")
  // It is still durable content, so it still moves the watermark: the client
  // must not re-read the record looking for an event it already has.
  inspect(view.watermark, content="2")
}

///|
test "transcript mapping replays a finished conversation" {
  let events =
    #|{"sequence":1,"item":{"kind":"user","payload":{"content":"  question  "}}},
    #|{"sequence":2,"item":{"kind":"tool_result","payload":{"tool_call_id":"c1","tool_name":"shell","content":"output","is_error":true,"brief":"ran ls → exit 1"}}},
    #|{"sequence":3,"ts":1000,"item":{"kind":"assistant","payload":{"content":"answer","tool_calls":[],"reasoning_content":"thought"}}},
    #|{"sequence":4,"ts":2000,"item":{"kind":"terminal","payload":{"kind":"finished","message":"answer"}}}
  let items = transcript_from_session(session_reply(events))
  // The result at sequence 2 answers no recorded call and is dropped.
  inspect(items.length(), content="2")
  guard items[0].kind is @transcript.User(..) else {
    fail("expected user item")
  }
  assert_eq(items[0].text(), Some("question"))
  guard items[1].kind
    is @transcript.Assistant(
      reasoning=Some(thought),
      prose=Some(_),
      calls=[],
      replay=false,
      finished=true
    ) else {
    fail("expected the terminal-confirmed answer with its reasoning")
  }
  inspect(thought, content="thought")
  assert_eq(items[1].text(), Some("answer"))
  // The confirming terminal leaves the response its own stamp and sequence.
  assert_true(items[1].ts is Some(1000))
  assert_true(items[1].sequence is Some(3))
}

///|
test "a finished turn marks only its last assistant message as final" {
  let events =
    #|{"sequence":1,"item":{"kind":"user","payload":{"content":"question"}}},
    #|{"sequence":2,"ts":1000,"item":{"kind":"assistant","payload":{"content":"I will inspect it.","tool_calls":[{"id":"c1","name":"read","arguments":"{}"}]}}},
    #|{"sequence":3,"item":{"kind":"tool_result","payload":{"tool_call_id":"c1","tool_name":"read","content":"result","is_error":false}}},
    #|{"sequence":4,"ts":2000,"item":{"kind":"assistant","payload":{"content":"Done.","tool_calls":[]}}},
    #|{"sequence":5,"ts":3000,"item":{"kind":"terminal","payload":{"kind":"finished","message":"Done."}}}
  let items = transcript_from_session(session_reply(events))
  inspect(items.length(), content="3")
  guard items[1].kind is @transcript.Assistant(calls=[call], finished=false, ..) else {
    fail("expected tool-prefacing narration to stay non-final")
  }
  assert_eq(items[1].text(), Some("I will inspect it."))
  assert_true(call.outcome is @transcript.Done(..))
  guard items[2].kind is @transcript.Assistant(calls=[], finished=true, ..) else {
    fail("expected only the last answer to be terminal-confirmed")
  }
  assert_eq(items[2].text(), Some("Done."))
  assert_true(items[2].ts is Some(2000))
}

///|
test "checkpoint assistant provenance projects without duplicate reasoning" {
  let events =
    #|{"sequence":1,"item":{"kind":"assistant","payload":{"content":"kept answer","tool_calls":[],"reasoning_content":"old thought","is_replay":true}}}
  let items = transcript_from_session(session_reply(events))
  inspect(items.length(), content="1")
  guard items[0].kind is @transcript.Assistant(reasoning=None, replay=true, ..) else {
    fail("expected a checkpoint replay without its reasoning")
  }
  assert_eq(items[0].text(), Some("kept answer"))
}

///|
test "tool results fill calls by id without changing call order" {
  let events =
    #|{"sequence":1,"item":{"kind":"assistant","payload":{"content":"","tool_calls":[{"id":"c1","name":"read","arguments":"{\"path\":\"moon.mod\"}"},{"id":"c2","name":"shell","arguments":"{\"cmd\":\"moon test\"}"}]}}},
    #|{"sequence":2,"item":{"kind":"tool_result","payload":{"tool_call_id":"c2","tool_name":"shell","content":"tests passed","is_error":false,"brief":"ran moon test"}}},
    #|{"sequence":3,"item":{"kind":"tool_result","payload":{"tool_call_id":"c1","tool_name":"","content":"module contents","is_error":false,"brief":"read moon.mod"}}}
  let view = @transcript.session_from_reply(session_reply(events))
  let items = view.items
  inspect(items.length(), content="1")
  guard items[0].kind is @transcript.Assistant(calls=[read, shell], ..) else {
    fail("expected one response carrying both calls in order")
  }
  inspect(read.call_id, content="c1")
  inspect(read.name, content="read")
  assert_true(read.arguments is Some("{\"path\":\"moon.mod\"}"))
  assert_true(
    read.outcome
    is @transcript.Done(
      content=Content([Text("module contents")]),
      is_error=false,
      brief=Some("read moon.mod")
    ),
  )
  inspect(shell.call_id, content="c2")
  inspect(shell.name, content="shell")
  assert_true(shell.arguments is Some("{\"cmd\":\"moon test\"}"))
  assert_true(
    shell.outcome
    is @transcript.Done(
      content=Content([Text("tests passed")]),
      is_error=false,
      brief=Some("ran moon test")
    ),
  )
}

///|
test "a result no recorded call is waiting for changes nothing" {
  let events =
    #|{"sequence":1,"item":{"kind":"assistant","payload":{"content":"","tool_calls":[{"id":"d","name":"read","arguments":"{\"path\":\"x\"}"}]}}},
    #|{"sequence":2,"item":{"kind":"tool_result","payload":{"tool_call_id":"d","tool_name":"read","content":"one","is_error":false}}},
    #|{"sequence":3,"item":{"kind":"tool_result","payload":{"tool_call_id":"d","tool_name":"read","content":"two","is_error":false}}}
  let view = @transcript.session_from_reply(session_reply(events))
  let items = view.items
  inspect(items.length(), content="1")
  // The first result fills the call; the second answers nothing pending, so
  // it is dropped rather than shown as a call the model never made.
  guard items[0].kind is @transcript.Assistant(calls=[call], ..) else {
    fail("expected the recorded call with its first result")
  }
  assert_true(
    call.outcome is @transcript.Done(content=Content([Text("one")]), ..),
  )
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
  guard items[0].kind is @transcript.Failure(_) else {
    fail("expected error bubble")
  }
  assert_eq(items[0].text(), Some("cancelled"))
  assert_eq(items[1].text(), Some("aborted: the agent gave up"))
  assert_eq(items[2].text(), Some("engine error"))
}

///|
test "transcript mapping keeps summaries and background notices" {
  let events =
    #|{"sequence":1,"item":{"kind":"summary","payload":{"content":"earlier turns compacted","from_sequence":1,"to_sequence":8}}},
    #|{"sequence":2,"item":{"kind":"runtime_notice","payload":{"content":"background job bg-1 finished (exit=0)"}}},
    #|{"sequence":3,"item":{"kind":"runtime_notice","payload":{"content":""}}}
  let items = transcript_from_session(session_reply(events))
  inspect(items.length(), content="2")
  guard items[0].kind is @transcript.Summary(_) else {
    fail("expected summary")
  }
  guard items[1].kind
    is @transcript.Notice(
      label="runtime notice",
      brief=None,
      is_error=false,
      ..
    ) else {
    fail("expected runtime notice row")
  }
  assert_eq(items[1].text(), Some("background job bg-1 finished (exit=0)"))
}

///|
test "transcript mapping renders goal markers as cards and reduces the standing goal" {
  let events =
    #|{"sequence":1,"item":{"kind":"runtime_notice","payload":{"content":"[goal baseline] sha=abc dirty=false"}}},
    #|{"sequence":2,"item":{"kind":"runtime_notice","payload":{"content":"[goal]\nship the feature"}}},
    #|{"sequence":3,"item":{"kind":"runtime_notice","payload":{"content":"[goal reminder]\nThe standing goal for this session:"}}},
    #|{"sequence":4,"item":{"kind":"runtime_notice","payload":{"content":"[goal blocked]\nneeds a decision"}}}
  let view = @transcript.session_from_reply(session_reply(events))
  inspect(view.items.length(), content="2")
  guard view.items[0].kind
    is @transcript.Notice(
      label="goal",
      is_error=false,
      brief=Some(set_brief),
      ..
    ) else {
    fail("expected the set card")
  }
  inspect(set_brief, content="Goal set: ship the feature")
  // A single-line goal is fully carried by its brief; no expandable body.
  assert_true(view.items[0].text() is None)
  guard view.items[1].kind
    is @transcript.Notice(
      label="goal",
      is_error=true,
      brief=Some(blocked_brief),
      ..
    ) else {
    fail("expected the blocked card")
  }
  inspect(blocked_brief, content="Goal blocked: needs a decision")
  assert_true(
    view.goal
    is Some({ text: "ship the feature", blocked: Some("needs a decision"), }),
  )
  // Every goal marker, with its sequence — not just the newest. A client
  // waiting on that set has to be able to find it here even though a block
  // has moved the standing goal on since; keeping only the last one would
  // hand it the block and nothing else.
  inspect(view.goal_markers.length(), content="2")
  assert_true(
    view.goal_markers[0] == (2, @transcript.GoalSet("ship the feature")),
  )
  assert_true(
    view.goal_markers[1] == (4, @transcript.GoalBlocked("needs a decision")),
  )
  // The goal-family notices that are not markers stay out of it.
  assert_true(view.goal_markers.all(entry => entry.0 != 1 && entry.0 != 3))
}

///|
test "transcript mapping drops the plan reminder instead of carding it" {
  // The reminder is durable model-directed text, so without an explicit
  // exclusion it would surface as a notice card. The live path drops the
  // matching `plan_reminder` event.
  let events =
    #|{"sequence":1,"item":{"kind":"runtime_notice","payload":{"content":"[plan reminder]\nUpdate the plan before continuing."}}},
    #|{"sequence":2,"item":{"kind":"runtime_notice","payload":{"content":"background job bg-2 finished (exit=1)"}}}
  let items = transcript_from_session(session_reply(events))
  inspect(items.length(), content="1")
  guard items[0].kind
    is @transcript.Notice(
      label="runtime notice",
      brief=None,
      is_error=false,
      ..
    ) else {
    fail("expected only the runtime notice row")
  }
  assert_eq(items[0].text(), Some("background job bg-2 finished (exit=1)"))
}

///|
test "a cleared goal leaves cards but no standing goal" {
  let events =
    #|{"sequence":1,"item":{"kind":"runtime_notice","payload":{"content":"[goal]\nline one\nline two"}}},
    #|{"sequence":2,"item":{"kind":"runtime_notice","payload":{"content":"[goal cleared]"}}}
  let view = @transcript.session_from_reply(session_reply(events))
  inspect(view.items.length(), content="2")
  guard view.items[0].kind
    is @transcript.Notice(label="goal", brief=Some(set_brief), ..) else {
    fail("expected the set card")
  }
  // A multi-line goal folds to its first line and expands to the full text.
  inspect(set_brief, content="Goal set: line one …")
  guard view.items[0].text() is Some(body) else {
    fail("expected the full goal text as the card's body")
  }
  inspect(
    body,
    content=(
      #|line one
      #|line two
    ),
  )
  guard view.items[1].kind
    is @transcript.Notice(label="goal", brief=Some(cleared), ..) else {
    fail("expected the cleared card")
  }
  inspect(cleared, content="Goal cleared")
  assert_true(view.goal is None)
}

///|
test "transcript mapping replays a context checkpoint and yield guidance" {
  let events =
    #|{"sequence":1,"item":{"kind":"summary","payload":{"content":"checkpoint recap","from_sequence":1,"to_sequence":8}}},
    #|{"sequence":2,"item":{"kind":"terminal","payload":{"kind":"finished","message":"[context ceiling] continue in a new turn"}}}
  let items = transcript_from_session(session_reply(events))
  inspect(items.length(), content="2")
  guard items[0].kind is @transcript.Summary(_) else {
    fail("expected checkpoint summary")
  }
  assert_eq(items[0].text(), Some("checkpoint recap"))
  guard items[1].kind is @transcript.Answer(_) else {
    fail("expected context-yield guidance")
  }
  assert_eq(items[1].text(), Some("[context ceiling] continue in a new turn"))
}

///|
test "transcript mapping renders the dedicated terminal kinds like their older forms" {
  // Newer engines save a yield and step exhaustion as their own kinds; the
  // transcript reads the same as for the `finished`/`failed` forms above.
  let events =
    #|{"sequence":1,"item":{"kind":"terminal","payload":{"kind":"context_yield","message":"[context ceiling] continue in a new turn"}}},
    #|{"sequence":2,"item":{"kind":"terminal","payload":{"kind":"max_steps_exhausted"}}}
  let items = transcript_from_session(session_reply(events))
  inspect(items.length(), content="2")
  guard items[0].kind is @transcript.Answer(_) else {
    fail("expected context-yield guidance")
  }
  assert_eq(items[0].text(), Some("[context ceiling] continue in a new turn"))
  guard items[1].kind is @transcript.Failure(_) else {
    fail("expected error bubble")
  }
  assert_eq(items[1].text(), Some("max steps exhausted"))
}

///|
/// The store `listed` rows belong to. Valid by construction; a total fixture
/// keeps the tree tests free of a synthetic error effect.
fn listed_workspace(path : String) -> @common.Uri {
  match @resource.of_path(@interop.ChannelId::Local, path) {
    Some(root) => root
    None => @common.Uri::file(path)
  }
}

///|
/// Sidebar entries for `session_tree` tests: only the id distinguishes them.
fn listed(ids : Array[String]) -> Array[@transcript.SessionListItem] {
  ids.map(id => {
    id,
    title: None,
    workspace: listed_workspace("/work"),
    workspace_name: "work",
    updated_at_ms: None,
  })
}

///|
/// A tree as `parent[child, …]` rows, so a case reads as the sidebar renders.
fn tree_shape(rows : Array[@transcript.SessionTreeRow]) -> String {
  rows
  .map(row => {
    if row.children.is_empty() {
      row.item.id
    } else {
      "\{row.item.id}[\{row.children.map(child => child.id).join(", ")}]"
    }
  })
  .join(" ")
}

///|
test "sub-run transcripts fold under the conversation that launched them" {
  inspect(
    tree_shape(
      @transcript.session_tree(
        listed(["desktop-a", "desktop-a-sr-1", "desktop-a-sr-2", "desktop-b"]),
      ),
    ),
    content="desktop-a[desktop-a-sr-1, desktop-a-sr-2] desktop-b",
  )
}

///|
test "session trees never fold children across stores" {
  guard @resource.of_path(@interop.ChannelId::Local, "/project")
    is Some(project) else {
    fail("test project path was invalid")
  }
  let other_parent = listed(["same"])[0]
  let project_parent : @transcript.SessionListItem = {
    ..other_parent,
    workspace: project,
    workspace_name: "project",
  }
  let project_child : @transcript.SessionListItem = {
    ..project_parent,
    id: "same-sr-1",
  }
  let rows = @transcript.session_tree([
    other_parent, project_parent, project_child,
  ])
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].item.workspace, other_parent.workspace)
  assert_true(rows[0].children.is_empty())
  assert_eq(rows[1].item.workspace, project)
  assert_eq(rows[1].children.length(), 1)
  assert_eq(rows[1].children[0].id, project_child.id)
  assert_eq(rows[1].children[0].workspace, project_child.workspace)
}

///|
test "children sort by sub-run ordinal, not by id text" {
  // Listed out of order and past `sr-9`, where a lexicographic sort would
  // put `sr-10` between `sr-1` and `sr-2`.
  inspect(
    tree_shape(
      @transcript.session_tree(listed(["a-sr-10", "a-sr-2", "a", "a-sr-1"])),
    ),
    content="a[a-sr-1, a-sr-2, a-sr-10]",
  )
}

///|
test "a child whose parent is not listed keeps its own row" {
  // The parent is archived (the archived twin is a separate reply), so its
  // children are all this group holds — they stay visible, in place.
  inspect(
    tree_shape(@transcript.session_tree(listed(["a-sr-1", "b", "a-sr-2"]))),
    content="a-sr-1 b a-sr-2",
  )
}

///|
test "a grandchild folds under the outermost listed ancestor" {
  inspect(
    tree_shape(@transcript.session_tree(listed(["a", "a-sr-1", "a-sr-1-sr-2"]))),
    content="a[a-sr-1, a-sr-1-sr-2]",
  )
  // The walk is link by link: with the middle generation missing from the
  // group, the grandchild keeps a row rather than jumping a gap.
  inspect(
    tree_shape(@transcript.session_tree(listed(["a", "a-sr-1-sr-2"]))),
    content="a a-sr-1-sr-2",
  )
}

///|
test "an id that merely looks like a child keeps its row" {
  inspect(
    tree_shape(@transcript.session_tree(listed(["a", "a-sr-x", "a-sr-"]))),
    content="a a-sr-x a-sr-",
  )
}
