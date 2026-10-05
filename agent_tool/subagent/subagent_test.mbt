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
  assert_true(listing.contains("sr-2 — working, last activity"))
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
