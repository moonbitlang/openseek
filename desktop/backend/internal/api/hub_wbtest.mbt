///|
/// Build the `agent.event` notification carrying one engine event.
fn approval_event(
  session : String,
  run_id : String?,
  event : @wire.Event,
) -> @protocol.Notification {
  AgentEvent({ run_id, session, event, })
}

///|
/// Two ways a question dies without an answer, both of which must stop it
/// being offered to the next client that looks.
test "a question does not outlive the engine that asked it" {
  let hub = Hub::Hub()
  let ask = approval_event(
    "s1",
    Some("r1"),
    ApprovalRequested(
      id="ap-1",
      tool_name="mbtx",
      detail="run with no sandbox policy",
      body=None,
    ),
  )
  // A run that ended without resolving its question: the engine settles its
  // own on the way out, so reaching here means one that could not — a killed
  // process emits no `approval_resolved`.
  hub.publish(
    AgentStarted(@json.from_json({ "run_id": "r1", "session": "s1" })),
  )
  hub.publish(ask)
  hub.publish(
    AgentFinished(
      @json.from_json({
        "run_id": "r1",
        "session": "s1",
        "status": "finished",
        "terminal": true,
      }),
    ),
  )
  guard hub.runs().approvals is [] else {
    fail("a question outlived the run it belonged to")
  }
  // A new engine process: the reply queue the question was blocking on died
  // with the old one, so replaying it would offer an answer with nowhere to
  // go.
  hub.publish(ask)
  hub.engine_connected({ stage: Serving, })
  guard hub.runs().approvals is [] else {
    fail("a question outlived the engine that asked it")
  }
}

///|
/// A resolution names both a session and an id. The id half matters because a
/// late one must not retire whatever has since taken that session's slot.
test "a resolution for a superseded id leaves the standing question" {
  let hub = Hub::Hub()
  hub.publish(
    approval_event(
      "s1",
      Some("r1"),
      ApprovalRequested(
        id="ap-7",
        tool_name="mbtx",
        detail="run with no sandbox policy",
        body=None,
      ),
    ),
  )
  hub.publish(
    approval_event(
      "s1",
      Some("r1"),
      ApprovalResolved(id="ap-1", outcome="allowed_once"),
    ),
  )
  guard hub.runs().approvals is [standing] else {
    fail("a resolution for another id retired the standing question")
  }
  assert_eq(standing.id, "ap-7")
}

///|
/// The hub retains a standing question the same way it retains an active run,
/// and for the same reason: it is live state a reloading client cannot rebuild
/// from anywhere else. The transcript comes back from the durable record; an
/// approval request was never in it.
test "a standing question is replayed until it is answered" {
  let hub = Hub::Hub()
  hub.publish(
    approval_event(
      "s1",
      Some("r1"),
      ApprovalRequested(
        id="ap-1",
        tool_name="mbtx",
        detail="run with no sandbox policy",
        body=Some("fn main { println(1) }"),
      ),
    ),
  )
  guard hub.runs().approvals is [pending] else {
    fail("the question was not retained")
  }
  // Everything a rejoining client needs to render it AND answer it — the id
  // above all, since a replay must address the question the engine is blocked
  // on rather than open a new one.
  assert_eq(pending.id, "ap-1")
  assert_eq(pending.session, "s1")
  assert_eq(pending.run_id, Some("r1"))
  assert_eq(pending.body, Some("fn main { println(1) }"))
  // Settled by whoever answered it — this client or another — and gone for
  // everyone at once.
  hub.publish(
    approval_event(
      "s1",
      Some("r1"),
      ApprovalResolved(id="ap-1", outcome="allowed_once"),
    ),
  )
  guard hub.runs().approvals is [] else {
    fail("an answered question was still replayed")
  }
}

///|
/// Two conversations blocked at once are two questions, and answering one
/// retires exactly one. The hub is host-wide while a question belongs to one
/// session's engine, so this is the isolation the session key buys.
test "questions from two engines are kept and retired independently" {
  let hub = Hub::Hub()
  for session in ["s1", "s2"] {
    hub.publish(
      approval_event(
        session,
        Some("r-" + session),
        ApprovalRequested(
          id="ap-" + session,
          tool_name="mbtx",
          detail="run with no sandbox policy",
          body=Some("// " + session),
        ),
      ),
    )
  }
  guard hub.runs().approvals is [first, second] else {
    fail("one of the two questions was lost")
  }
  assert_true(
    (first.session == "s1" && second.session == "s2") ||
    (first.session == "s2" && second.session == "s1"),
  )
  hub.publish(
    approval_event(
      "s1",
      Some("r-s1"),
      ApprovalResolved(id="ap-s1", outcome="allowed_once"),
    ),
  )
  guard hub.runs().approvals is [survivor] else {
    fail("resolving one question disturbed the other")
  }
  assert_eq(survivor.session, "s2")
  assert_eq(survivor.body, Some("// s2"))
}
