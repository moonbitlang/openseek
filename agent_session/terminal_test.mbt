///|
/// The stored payload of `terminal`, as a session log line carries it.
fn terminal_payload(terminal : @agent_session.TurnTerminal) -> Json raise {
  let event = @agent_session.Session(SessionId("s"), system_prompt="")
    .append(Terminal(terminal))
    .events()[0]
  guard @json.to_json(event) is { "item": { "payload": payload, .. }, .. } else {
    fail("expected a terminal payload")
  }
  payload
}

///|
test "new terminal kinds round-trip through their own storage kinds" {
  let notice = @agent_session.ContextYieldAnswerPrefix + " checkpointed"
  let yielded = terminal_payload(ContextYield(notice))
  assert_eq(yielded, { "kind": "context_yield", "message": notice })
  assert_eq(
    (@json.from_json(yielded) : @agent_session.TurnTerminal),
    ContextYield(notice),
  )
  let exhausted = terminal_payload(MaxStepsExhausted)
  assert_eq(exhausted, { "kind": "max_steps_exhausted" })
  assert_eq(
    (@json.from_json(exhausted) : @agent_session.TurnTerminal),
    MaxStepsExhausted,
  )
}

///|
test "older terminal encodings decode to the dedicated variants" {
  let legacy_yield : Json = {
    "kind": "finished",
    "message": "[context ceiling] checkpointed",
  }
  assert_eq(
    (@json.from_json(legacy_yield) : @agent_session.TurnTerminal),
    ContextYield("[context ceiling] checkpointed"),
  )
  let legacy_exhausted : Json = {
    "kind": "failed",
    "message": "max steps exhausted",
  }
  assert_eq(
    (@json.from_json(legacy_exhausted) : @agent_session.TurnTerminal),
    MaxStepsExhausted,
  )
  // Other `finished` and `failed` messages keep their variants.
  let failed : Json = { "kind": "failed", "message": "agent failed: boom" }
  assert_eq(
    (@json.from_json(failed) : @agent_session.TurnTerminal),
    Failed("agent failed: boom"),
  )
}

///|
test "terminal decoding still rejects unknown kinds and missing messages" {
  let rejected : Array[Json] = [
    { "kind": "vanished", "message": "" },
    { "kind": "failed" },
    { "kind": "context_yield" },
    { "kind": "finished", "message": "done", "verbatim": "yes" },
  ]
  for json in rejected {
    let decoded : @agent_session.TurnTerminal? = Some(@json.from_json(json)) catch {
      _ => None
    }
    assert_eq(decoded, None)
  }
}

///|
test "Session::last_terminal reads only the latest turn" {
  let empty = @agent_session.Session(SessionId("s"), system_prompt="")
  assert_eq(empty.last_terminal(), None)
  let finished = empty
    .append(User(UserMessage(Content([Text("hi")]))))
    .append(Terminal(Finished("first")))
  assert_eq(finished.last_terminal(), Some(Finished("first")))
  // Items after a terminal that do not open a turn leave it the latest.
  let noted = finished
    .append(Runtime(RuntimeNotice("[goal] ship it")))
    .append(
      Summary(SessionSummary(content="s", from_sequence=1, to_sequence=2)),
    )
  assert_eq(noted.last_terminal(), Some(Finished("first")))
  // A later turn without a terminal must not report the earlier one.
  let cut_off = noted.append(User(UserMessage(Content([Text("again")]))))
  assert_eq(cut_off.last_terminal(), None)
  let resealed = cut_off.append(Terminal(MaxStepsExhausted))
  assert_eq(resealed.last_terminal(), Some(MaxStepsExhausted))
}

///|
test "a current answer or failure that reads like an older encoding stays itself" {
  let echoed = @agent_session.ContextYieldAnswerPrefix + " echoed on request"
  let answer = terminal_payload(Finished(echoed))
  assert_eq(answer, { "kind": "finished", "message": echoed, "verbatim": true })
  assert_eq(
    (@json.from_json(answer) : @agent_session.TurnTerminal),
    Finished(echoed),
  )
  let failure = terminal_payload(Failed("max steps exhausted"))
  assert_eq(failure, {
    "kind": "failed",
    "message": "max steps exhausted",
    "verbatim": true,
  })
  assert_eq(
    (@json.from_json(failure) : @agent_session.TurnTerminal),
    Failed("max steps exhausted"),
  )
  // Only colliding texts carry the mark.
  assert_eq(terminal_payload(Finished("done")), {
    "kind": "finished",
    "message": "done",
  })
}
