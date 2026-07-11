///|
fn batch_session() -> @agent_session.Session {
  @agent_session.Session(
    // 1 User, 2 Assistant(calls a+b), 3 Tool(a), 4 Tool(b), 5 Terminal.
    SessionId("cut-batch"),
    system_prompt="system",
  )
  .append(User(UserMessage("task")))
  .append(
    Assistant(
      AssistantMessage("running two probes", tool_calls=[
        ToolCall(id="call_a", name="probe", arguments="{}"),
        ToolCall(id="call_b", name="probe", arguments="{}"),
      ]),
    ),
  )
  .append(
    Tool(ToolResult(tool_call_id="call_a", tool_name="probe", content="ra")),
  )
  .append(
    Tool(ToolResult(tool_call_id="call_b", tool_name="probe", content="rb")),
  )
  .append(Terminal(Finished("done")))
}

///|
test "boundaries exist exactly where no tool call is pending" {
  let session = batch_session()
  assert_eq(session.checkpoint_cut(requested_to=5), Some(5))
  assert_eq(session.checkpoint_cut(requested_to=4), Some(4))
  // Sequences 2 and 3 sit inside the batch: the planner clamps to the
  // boundary before it.
  assert_eq(session.checkpoint_cut(requested_to=3), Some(1))
  assert_eq(session.checkpoint_cut(requested_to=2), Some(1))
  assert_eq(session.checkpoint_cut(requested_to=1), Some(1))
  assert_eq(session.checkpoint_cut(requested_to=0), None)
  // Beyond the last sequence is unconstraining.
  assert_eq(session.checkpoint_cut(requested_to=100), Some(5))
}

///|
test "result order inside a batch does not matter" {
  // Results arrive b-then-a: the batch closes only once both landed.
  let session = @agent_session.Session(
      SessionId("cut-interleaved"),
      system_prompt="system",
    )
    .append(User(UserMessage("task")))
    .append(
      Assistant(
        AssistantMessage("two calls", tool_calls=[
          ToolCall(id="call_a", name="probe", arguments="{}"),
          ToolCall(id="call_b", name="probe", arguments="{}"),
        ]),
      ),
    )
    .append(
      Tool(ToolResult(tool_call_id="call_b", tool_name="probe", content="rb")),
    )
    .append(
      Tool(ToolResult(tool_call_id="call_a", tool_name="probe", content="ra")),
    )
  assert_eq(session.checkpoint_cut(requested_to=3), Some(1))
  assert_eq(session.checkpoint_cut(requested_to=4), Some(4))
}

///|
test "an open batch at the log edge clamps the boundary below it" {
  let session = @agent_session.Session(
      SessionId("cut-open-tail"),
      system_prompt="system",
    )
    .append(User(UserMessage("task")))
    .append(
      Assistant(
        AssistantMessage("crashed mid-batch", tool_calls=[
          ToolCall(id="call_a", name="probe", arguments="{}"),
        ]),
      ),
    )
  assert_eq(session.checkpoint_cut(requested_to=2), Some(1))
}

///|
test "a mid-log dangling call pins every later boundary" {
  // The unanswered call at sequence 2 stays pending forever, so even the
  // clean events after it never become boundaries.
  let session = @agent_session.Session(
      SessionId("cut-dangling"),
      system_prompt="system",
    )
    .append(User(UserMessage("task")))
    .append(
      Assistant(
        AssistantMessage("never answered", tool_calls=[
          ToolCall(id="call_lost", name="probe", arguments="{}"),
        ]),
      ),
    )
    .append(User(UserMessage("resumed after a crash")))
    .append(Assistant(AssistantMessage("plain answer")))
    .append(Terminal(Finished("done")))
  assert_eq(session.checkpoint_cut(requested_to=5), Some(1))
}

///|
test "an orphaned tool result neither opens nor closes a batch" {
  let session = @agent_session.Session(
      SessionId("cut-orphan"),
      system_prompt="system",
    )
    .append(User(UserMessage("task")))
    .append(
      Tool(
        ToolResult(
          tool_call_id="call_unknown",
          tool_name="probe",
          content="orphan",
        ),
      ),
    )
    .append(Terminal(Finished("done")))
  assert_eq(session.checkpoint_cut(requested_to=3), Some(3))
}

///|
/// The property the planner exists for: prefix coverage to a boundary
/// leaves every uncovered event standing verbatim, while covering INSIDE a
/// batch silently drops the batch's uncovered sibling result — the covered
/// call never enters the projection's pending set, so pairing discards the
/// result, and the summary does not stand in for it (it was only asked to
/// cover the prefix).
test "planner boundaries keep uncovered events; split cuts lose them" {
  let session = batch_session()
  let clean = session.compact(
    content="checkpoint stand-in",
    from_sequence=1,
    to_sequence=4,
    unix_ms=0,
  )
  let clean_projected = clean
    .chat_messages()
    .map(message => message.content)
    .join("\n")
  // The uncovered terminal survives verbatim next to the summary.
  assert_true(clean_projected.contains("checkpoint stand-in"))
  assert_true(clean_projected.contains("done"))
  // Negative control: sequence 3 splits the batch between call_a's result
  // and call_b's. rb (sequence 4) is NOT covered, yet it vanishes.
  let split = session.compact(
    content="checkpoint stand-in",
    from_sequence=1,
    to_sequence=3,
    unix_ms=0,
  )
  let split_projected = split
    .chat_messages()
    .map(message => message.content)
    .join("\n")
  assert_true(split_projected.contains("done"))
  assert_false(
    split_projected.contains("rb"),
    msg="split cut must drop the uncovered sibling result",
  )
}
