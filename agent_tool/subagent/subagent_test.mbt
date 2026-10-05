///|
/// Call one of the two tools on `store`'s session `p` and return what the
/// model would read, with whether it was an error.
async fn call(
  store : @store.SessionStore,
  name : String,
  arguments : Json,
) -> (String, Bool) {
  guard @subagent.definitions(session_root=store.root(), parent="p").filter(tool => {
      tool.name == name
    })
    is [tool] else {
    fail("no tool named \{name}")
  }
  let action = match tool.execute {
    Async(execute) => execute(arguments)
    Sync(_) => fail("\{name} should be async")
  }
  guard action is Respond(output) else { fail("expected a Respond action") }
  (output.content, output.is_error)
}

///|
/// Record a child of `p` the way a `run --kind` child does: its task first,
/// then whatever `items` it got to.
async fn record_child(
  store : @store.SessionStore,
  n : Int,
  task : String,
  items : Array[@agent_session.SessionItem],
) -> @agent_session.SessionId {
  let id = @agent_session.SessionId("p-sr-\{n}")
  let mut session = @agent_session.Session(id, system_prompt="scout")
  session = store.append(session, User(UserMessage(Content([Text(task)]))))
  for item in items {
    session = store.append(session, item)
  }
  id
}

///|
async test "an instruction is queued, then delivered, then seen" {
  let root = @fs.tmpdir(prefix="openseek-subagent-")
  defer @fs.rmdir(root, recursive=true)
  let store = @store.SessionStore(root)
  let (listing, _) = call(store, "subagent_status", {})
  assert_true(listing.contains("no subagents yet"))
  let scout = @agent_session.SessionId("p-sr-2")
  // The child opens its inbox before its first record.
  @inbox.open(store.inbox_path(scout))
  let (early, is_error) = call(store, "subagent_send", {
    "id": "sr-2",
    "message": "too early",
  })
  assert_true(is_error)
  assert_true(early.contains("no subagent sr-2 has recorded a step"))
  record_child(store, 2, "Who calls run_subrun?", [
    Assistant(
      AssistantMessage("Searching the callers.", tool_calls=[
        ToolCall(
          id="c1",
          name="mbtx",
          arguments="{\"description\":\"rg run_subrun\",\"source\":\"...\"}",
        ),
      ]),
    ),
    Tool(
      ToolResult(
        tool_call_id="c1",
        tool_name="mbtx",
        content=[Text("3 matches")],
        brief="mbtx (exit=0)",
      ),
    ),
  ])
  |> ignore
  let (listing, is_error) = call(store, "subagent_status", {})
  assert_false(is_error)
  assert_true(listing.contains("sr-2 — no end recorded, last activity"))
  assert_true(listing.contains("1 step(s)"))
  assert_true(listing.contains("Who calls run_subrun?"))
  let (sent, is_error) = call(store, "subagent_send", {
    "id": "sr-2",
    "message": "Only production callers; skip tests.",
  })
  assert_false(is_error)
  assert_true(sent.contains("queued instruction m"))
  guard @inbox.read(store.inbox_path(scout))
    is Some({ messages: [posted], unreadable: 0, }) else {
    fail("expected exactly the one posted instruction")
  }
  assert_eq(posted.from, "p")
  assert_true(sent.contains(posted.id))
  let (detail, _) = call(store, "subagent_status", { "id": "sr-2" })
  assert_true(detail.contains("1 instruction(s): 1 waiting"))
  assert_true(detail.contains("calls mbtx: rg run_subrun"))
  assert_true(detail.contains("result mbtx (exit=0)"))
  assert_true(detail.contains("[waiting] Only production callers; skip tests."))
  // The child takes it: a user item tagged with the message's receipt. A
  // user item without it is not a delivery, whatever its text — and neither
  // is one tagged with the bare id, which another sender could share.
  let session = store.append(
    store.load(scout),
    User(UserMessage(Content([Text("Only production callers; skip tests.")]))),
  )
  let session = store.append(
    session,
    User(
      UserMessage(Content([Text("someone else's")]), submission_id=posted.id),
    ),
  )
  // Nor is another sender's message with the SAME id: its receipt names it.
  let foreign : @inbox.Message = {
    id: posted.id,
    from: "q",
    text: "From another conversation.",
  }
  let session = store.append(
    session,
    User(
      UserMessage(
        Content([Text("From another conversation.")]),
        submission_id=foreign.receipt(),
      ),
    ),
  )
  let (detail, _) = call(store, "subagent_status", { "id": "sr-2" })
  assert_true(detail.contains("1 instruction(s): 1 waiting"))
  let session = store.append(
    session,
    User(
      UserMessage(
        Content([Text("[New instruction] Only production callers.")]),
        submission_id=posted.receipt(),
      ),
    ),
  )
  let (detail, _) = call(store, "subagent_status", { "id": "sr-2" })
  assert_true(detail.contains("1 instruction(s): 1 delivered"))
  assert_true(detail.contains("instruction delivered: [New instruction]"))
  assert_true(detail.contains("[delivered] Only production callers"))
  // Only a model request after it makes it seen.
  let session = store.append(session, Assistant(AssistantMessage("Narrowing.")))
  let (detail, _) = call(store, "subagent_status", { "id": "sr-2" })
  assert_true(detail.contains("1 instruction(s): 1 seen"))
  assert_false(detail.contains("[delivered]"))
  // A second one the child never gets to before it ends.
  let (_, is_error) = call(store, "subagent_send", {
    "id": "sr-2",
    "message": "Also check the desktop backend.",
  })
  assert_false(is_error)
  store.append(session, Terminal(Finished("explore answered"))) |> ignore
  let (detail, _) = call(store, "subagent_status", { "id": "sr-2" })
  assert_true(detail.contains("2 instruction(s): 1 seen, 1 never delivered"))
  assert_true(detail.contains("[never delivered] Also check the desktop"))
}

///|
/// The transcript records responses, not requests: an instruction that was
/// recorded just before the subagent was cut off may or may not have reached
/// the model, and the status must not claim either.
async test "a delivery with no response after it is not called seen" {
  let root = @fs.tmpdir(prefix="openseek-subagent-")
  defer @fs.rmdir(root, recursive=true)
  let store = @store.SessionStore(root)
  let scout = @agent_session.SessionId("p-sr-1")
  @inbox.open(store.inbox_path(scout))
  record_child(store, 1, "Where is X?", []) |> ignore
  let (_, is_error) = call(store, "subagent_send", {
    "id": "sr-1",
    "message": "Stop and report.",
  })
  assert_false(is_error)
  guard @inbox.read(store.inbox_path(scout)) is Some({ messages: [posted], .. }) else {
    fail("expected the posted instruction")
  }
  let session = store.append(
    store.load(scout),
    User(
      UserMessage(
        Content([Text("Stop and report.")]),
        submission_id=posted.receipt(),
      ),
    ),
  )
  store.append(session, Terminal(Interrupted("stdin closed"))) |> ignore
  let (detail, _) = call(store, "subagent_status", { "id": "sr-1" })
  assert_true(
    detail.contains(
      "1 instruction(s): 1 delivered, with no response recorded after it",
    ),
  )
}

///|
async test "a post is refused where nothing would read it" {
  let root = @fs.tmpdir(prefix="openseek-subagent-")
  defer @fs.rmdir(root, recursive=true)
  let store = @store.SessionStore(root)
  // A reviewer: recorded, but it never opens an inbox.
  let reviewer = record_child(store, 1, "Audit the goal.", [])
  let (refused, is_error) = call(store, "subagent_send", {
    "id": "sr-1",
    "message": "Ignore the failing test.",
  })
  assert_true(is_error)
  assert_true(refused.contains("takes no instructions"))
  assert_false(@fs.exists(store.inbox_path(reviewer)))
  // A scout that already reported.
  let done = @agent_session.SessionId("p-sr-3")
  @inbox.open(store.inbox_path(done))
  record_child(store, 3, "Where is X?", [
    Terminal(Finished("explore answered (2 citation(s))")),
  ])
  |> ignore
  let (refused, is_error) = call(store, "subagent_send", {
    "id": "sr-3",
    "message": "Also check Y.",
  })
  assert_true(is_error)
  assert_true(
    refused.contains("sr-3 already ended (finished: explore answered"),
  )
  assert_true(
    @inbox.read(store.inbox_path(done))
    is Some({ messages: [], unreadable: 0, }),
  )
  // One that never existed, ids that are not ids, and a message too long.
  let (missing, is_error) = call(store, "subagent_send", {
    "id": "sr-9",
    "message": "hello",
  })
  assert_true(is_error)
  assert_true(missing.contains("no subagent sr-9"))
  for bad in ["../p", "sr-", "sr-1-sr-2", "p-sr-1", "sr-x"] {
    let (refused, is_error) = call(store, "subagent_status", { "id": bad })
    assert_true(is_error)
    assert_true(refused.contains("is not a subagent id"))
  }
  let (long, is_error) = call(store, "subagent_send", {
    "id": "sr-1",
    "message": "x".repeat(8_001),
  })
  assert_true(is_error)
  assert_true(long.contains("at most 8000"))
  // Another conversation's child is not this one's.
  let other = @agent_session.SessionId("q-sr-1")
  store.append(
    Session(other, system_prompt="scout"),
    User(UserMessage(Content([Text("not yours")]))),
  )
  |> ignore
  let (listing, _) = call(store, "subagent_status", {})
  assert_false(listing.contains("not yours"))
  assert_true(listing.contains("sr-1 — "))
  assert_true(listing.contains("sr-3 — finished"))
}

///|
async test "a subagent that is not reading stops being sent to" {
  let root = @fs.tmpdir(prefix="openseek-subagent-")
  defer @fs.rmdir(root, recursive=true)
  let store = @store.SessionStore(root)
  @inbox.open(store.inbox_path(SessionId("p-sr-1")))
  record_child(store, 1, "Where is X?", []) |> ignore
  for n in 1..<=8 {
    let (_, is_error) = call(store, "subagent_send", {
      "id": "sr-1",
      "message": "instruction \{n}",
    })
    assert_false(is_error)
  }
  let (refused, is_error) = call(store, "subagent_send", {
    "id": "sr-1",
    "message": "one too many",
  })
  assert_true(is_error)
  assert_true(refused.contains("has not taken the last 8 instructions"))
  let (listing, _) = call(store, "subagent_status", {})
  assert_true(listing.contains("8 instruction(s): 8 waiting"))
}

///|
/// What the workflow run itself recorded refines the listing: the script's
/// label, which run, and an end the child never got to write down.
async test "the workflow's own record names, places and closes a child" {
  let root = @fs.tmpdir(prefix="openseek-subagent-")
  defer @fs.rmdir(root, recursive=true)
  let store = @store.SessionStore(root)
  @fs.mkdir("\{root}/p-wf-33", recursive=true)
  @fs.write_file(
    "\{root}/p-wf-33/events.jsonl",
    (
      #|{"event":"agent_started","child":"p-sr-33","kind":"explore","label":"scout:callers"}
      #|{"event":"agent_started","child":"p-sr-34","kind":"explore","label":"scout:tests"}
      #|{"event":"agent_started","child":"p-sr-35","kind":"explore","label":"scout:late"}
      #|{"event":"agent_started","child":"q-sr-36","kind":"explore","label":"not ours"}
      #|{"event":"agent_finished","child":"p-sr-34","status":"timed_out","steps":0,"tokens":0}
      #|not a record
      #|
    ),
    create_mode=CreateNew,
  )
  // Another conversation's run directory is not read at all.
  @fs.mkdir("\{root}/q-wf-1", recursive=true)
  @fs.write_file(
    "\{root}/q-wf-1/events.jsonl",
    (
      #|{"event":"agent_started","child":"p-sr-99","kind":"explore","label":"planted"}
      #|
    ),
    create_mode=CreateNew,
  )
  for n in [33, 34] {
    @inbox.open(store.inbox_path(SessionId("p-sr-\{n}")))
    record_child(store, n, "Question \{n}", []) |> ignore
  }
  // One the engine launched itself: no workflow knows it.
  record_child(store, 2, "Audit the goal.", []) |> ignore
  let (listing, is_error) = call(store, "subagent_status", {})
  assert_false(is_error)
  let lines = listing.split("\n").map(line => line.to_owned()).collect()
  assert_eq(lines.length(), 5)
  assert_true(lines[0].has_prefix("sr-2 — no end recorded, last activity"))
  assert_true(
    lines[1].has_prefix(
      "sr-33 [scout:callers · explore · wf-33] — running per the workflow's record, last activity",
    ),
  )
  assert_true(
    lines[2].has_prefix(
      "sr-34 [scout:tests · explore · wf-33] — no end in its transcript; the workflow recorded it as timed_out",
    ),
  )
  assert_eq(
    lines[3],
    "sr-35 [scout:late · explore · wf-33] — launched per the workflow's record; nothing recorded yet",
  )
  // The line that is not a record is said, not passed over.
  assert_true(
    lines[4].has_prefix("(1 line(s) in a workflow record are damaged:"),
  )
  assert_false(listing.contains("planted"))
  assert_false(listing.contains("not ours"))
  // The detail view carries the same tag and state.
  let (detail, _) = call(store, "subagent_status", { "id": "sr-34" })
  assert_true(
    detail.has_prefix(
      "sr-34 [scout:tests · explore · wf-33] — no end in its transcript; the workflow recorded it as timed_out",
    ),
  )
  // A child the workflow says is over is not posted to; a running one is.
  let (refused, is_error) = call(store, "subagent_send", {
    "id": "sr-34",
    "message": "Report what you have.",
  })
  assert_true(is_error)
  assert_true(refused.contains("the workflow recorded it as timed_out"))
  assert_true(
    @inbox.read(store.inbox_path(SessionId("p-sr-34")))
    is Some({ messages: [], unreadable: 0, }),
  )
  let (_, is_error) = call(store, "subagent_send", {
    "id": "sr-33",
    "message": "Only production callers.",
  })
  assert_false(is_error)
  // A launch on record is not a transcript: nothing to post to yet.
  let (early, is_error) = call(store, "subagent_send", {
    "id": "sr-35",
    "message": "hello",
  })
  assert_true(is_error)
  assert_true(early.contains("no subagent sr-35 has recorded a step"))
}

///|
/// The start and finish records are written independently. A finish whose
/// start never made it to disk still says the child is over.
async test "a finish with no start record still closes the child" {
  let root = @fs.tmpdir(prefix="openseek-subagent-")
  defer @fs.rmdir(root, recursive=true)
  let store = @store.SessionStore(root)
  @fs.mkdir("\{root}/p-wf-40", recursive=true)
  @fs.write_file(
    "\{root}/p-wf-40/events.jsonl",
    (
      #|{"event":"agent_finished","child":"p-sr-40","status":"timed_out","steps":0,"tokens":0}
      #|
    ),
    create_mode=CreateNew,
  )
  @inbox.open(store.inbox_path(SessionId("p-sr-40")))
  record_child(store, 40, "Where is X?", []) |> ignore
  let (listing, _) = call(store, "subagent_status", {})
  assert_true(
    listing.has_prefix(
      "sr-40 [wf-40] — no end in its transcript; the workflow recorded it as timed_out",
    ),
  )
  let (refused, is_error) = call(store, "subagent_send", {
    "id": "sr-40",
    "message": "Report what you have.",
  })
  assert_true(is_error)
  assert_true(refused.contains("the workflow recorded it as timed_out"))
}

///|
/// A workflow record is a view. One that is damaged, or cannot be read at
/// all, costs its own labels and nothing else: every child is still listed
/// from its transcript and a healthy one can still be posted to.
async test "a damaged workflow record does not take the tools down" {
  let root = @fs.tmpdir(prefix="openseek-subagent-")
  defer @fs.rmdir(root, recursive=true)
  let store = @store.SessionStore(root)
  // A record cut off inside a multi-byte character, after one whole line.
  @fs.mkdir("\{root}/p-wf-1", recursive=true)
  let file = @fs.open(
    "\{root}/p-wf-1/events.jsonl",
    mode=WriteOnly,
    create_mode=CreateNew,
  )
  file.write(
    b"{\"event\":\"agent_started\",\"child\":\"p-sr-1\",\"kind\":\"explore\",\"label\":\"scout:a\"}\n{\"event\":\"agent_started\",\"child\":\"p-sr-2\",\"label\":\"caf\xc3",
  )
  file.close()
  // A record that is not a file at all.
  @fs.mkdir("\{root}/p-wf-33/events.jsonl", recursive=true)
  for n in [1, 2] {
    @inbox.open(store.inbox_path(SessionId("p-sr-\{n}")))
    record_child(store, n, "Question \{n}", []) |> ignore
  }
  let (listing, is_error) = call(store, "subagent_status", {})
  assert_false(is_error, msg=listing)
  let lines = listing.split("\n").map(line => line.to_owned()).collect()
  assert_eq(lines.length(), 3)
  assert_true(
    lines[0].has_prefix("sr-1 [scout:a · explore · wf-1] — running"),
  )
  // The torn line told us nothing about sr-2; its transcript still does.
  assert_true(lines[1].has_prefix("sr-2 — no end recorded, last activity"))
  // Both kinds of loss are said: the record that is not a file, and the
  // line cut off inside a character.
  assert_true(
    lines[2].has_prefix(
      "(1 workflow record(s) could not be read and 1 line(s) in a workflow record are damaged:",
    ),
  )
  let (detail, is_error) = call(store, "subagent_status", { "id": "sr-2" })
  assert_false(is_error, msg=detail)
  assert_true(detail.contains("(1 workflow record(s) could not be read"))
  let (sent, is_error) = call(store, "subagent_send", {
    "id": "sr-2",
    "message": "Only production callers.",
  })
  assert_false(is_error, msg=sent)
}

///|
/// A finish that was damaged in the writing is lost, and the child it was
/// about then reads as running. Nothing can say which child that is, so the
/// status says the record is incomplete — on its own, with every file
/// readable — and what is intact stays usable.
async test "a damaged line in a workflow record is said, not skipped" {
  let root = @fs.tmpdir(prefix="openseek-subagent-")
  defer @fs.rmdir(root, recursive=true)
  let store = @store.SessionStore(root)
  @fs.mkdir("\{root}/p-wf-1", recursive=true)
  @fs.write_file(
    "\{root}/p-wf-1/events.jsonl",
    (
      #|{"event":"agent_started","child":"p-sr-1","kind":"explore","label":"scout:a"}
      #|{"event":"agent_finished","child":"p-sr-1","status":"timed_o
      #|{"event":"phase_started","phase":"an event from a newer library"}
      #|
      #|{"event":"agent_finished","child":"p-sr-2"}
      #|
    ),
    create_mode=CreateNew,
  )
  @inbox.open(store.inbox_path(SessionId("p-sr-1")))
  record_child(store, 1, "Question 1", []) |> ignore
  let (listing, is_error) = call(store, "subagent_status", {})
  assert_false(is_error, msg=listing)
  let lines = listing.split("\n").map(line => line.to_owned()).collect()
  assert_eq(lines.length(), 2)
  // The start survived, so the child is still named — and still "running",
  // which is exactly why the next line has to be there.
  assert_true(
    lines[0].has_prefix(
      "sr-1 [scout:a · explore · wf-1] — running per the workflow's record",
    ),
  )
  // The cut-off finish and the finish with no status; not the unknown event
  // and not the blank line.
  assert_eq(
    lines[1],
    "(2 line(s) in a workflow record are damaged: a label or an end may be missing above, so a subagent shown as running may already be over)",
  )
  let (detail, _) = call(store, "subagent_status", { "id": "sr-1" })
  assert_true(detail.contains("(2 line(s) in a workflow record are damaged"))
  let (sent, is_error) = call(store, "subagent_send", {
    "id": "sr-1",
    "message": "Report what you have.",
  })
  assert_false(is_error, msg=sent)
}

///|
/// A record whose child id is not a child id was about some child and cannot
/// say which — damage, unlike a well-formed id under another parent.
async test "a record with a malformed child id is damage, a foreign one is not" {
  let root = @fs.tmpdir(prefix="openseek-subagent-")
  defer @fs.rmdir(root, recursive=true)
  let store = @store.SessionStore(root)
  @fs.mkdir("\{root}/p-wf-1", recursive=true)
  @fs.write_file(
    "\{root}/p-wf-1/events.jsonl",
    (
      #|{"event":"agent_started","child":"p-sr-1","kind":"explore","label":"scout:a"}
      #|{"event":"agent_finished","child":"p-sr-x","status":"timed_out"}
      #|{"event":"agent_finished","child":"q-sr-7","status":"captured"}
      #|
    ),
    create_mode=CreateNew,
  )
  @inbox.open(store.inbox_path(SessionId("p-sr-1")))
  record_child(store, 1, "Question 1", []) |> ignore
  let (listing, is_error) = call(store, "subagent_status", {})
  assert_false(is_error, msg=listing)
  let lines = listing.split("\n").map(line => line.to_owned()).collect()
  assert_eq(lines.length(), 2)
  assert_true(
    lines[0].has_prefix(
      "sr-1 [scout:a · explore · wf-1] — running per the workflow's record",
    ),
  )
  assert_true(
    lines[1].has_prefix("(1 line(s) in a workflow record are damaged:"),
  )
  let (sent, is_error) = call(store, "subagent_send", {
    "id": "sr-1",
    "message": "Report what you have.",
  })
  assert_false(is_error, msg=sent)
}

///|
test "a snippet may call both tools" {
  for tool in @subagent.definitions(session_root="/store", parent="p") {
    assert_true(tool.is_program_callable())
  }
}

///|
/// The real thing, end to end: a compiled snippet lists the subagents and
/// posts to one through `@tools.call`. Its own policy would not let it write
/// the inbox; the host tool does it for the snippet.
async test "a running snippet watches and posts through @tools.call" {
  let root = @fs.tmpdir(prefix="openseek-subagent-")
  defer @fs.rmdir(root, recursive=true)
  let store = @store.SessionStore("\{root}/store")
  let scout = @agent_session.SessionId("p-sr-1")
  @inbox.open(store.inbox_path(scout))
  record_child(store, 1, "Who calls run_subrun?", []) |> ignore
  let workspace = "\{root}/ws"
  @fs.mkdir(workspace, recursive=true)
  @async.with_task_group(group => {
    let service = @ptc.Service::start(
      group,
      Tools(@subagent.definitions(session_root=store.root(), parent="p")),
    )
    let tool = @mbtx.definition(
      workspace_root=workspace,
      program_service=service,
    )
    let action = match tool.execute {
      Async(execute) =>
        execute({
          "ptc": true,
          "source": (
            #|///|
            #|import { "moonbitlang/openseek_tools@0.2.0" @tools, "moonbitlang/async" }
            #|async fn main {
            #|  let listing = @tools.call("subagent_status", {})
            #|  if listing.is_error { fail("status failed: \{listing.content}") }
            #|  println(listing.content)
            #|  if listing.content.contains("sr-1 ") {
            #|    let sent = @tools.call("subagent_send", { "id": "sr-1", "message": "Only production callers." })
            #|    if sent.is_error { fail("send failed: \{sent.content}") }
            #|    println(sent.content)
            #|  }
            #|}
          ),
        })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error, msg=output.content)
    assert_true(output.content.contains("sr-1 — no end recorded"))
    assert_true(output.content.contains("queued instruction m"))
  })
  guard @inbox.read(store.inbox_path(scout))
    is Some({ messages: [posted], unreadable: 0, }) else {
    fail("the snippet's instruction should be in the inbox")
  }
  assert_eq(posted.from, "p")
  assert_eq(posted.text, "Only production callers.")
}
