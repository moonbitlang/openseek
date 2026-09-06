///|
/// The auto-compaction trigger reads token usage from API responses, so a
/// mock server drives it with fabricated counts — no giant contexts needed.
/// The main loop always streams SSE while the checkpoint summary call is
/// plain JSON, so replies branch per request.
priv enum MockReply {
  Sse(String)
  Body(Json)
}

///|
async fn auto_compact_test_server(
  group : @async.TaskGroup[Unit],
  handle : (Json) -> MockReply raise,
) -> String? {
  guard bind_test_server(
      "local TCP bind unavailable; skipping auto-compaction test",
    )
    is Some(server) else {
    return None
  }
  group.spawn_bg(no_wait=true) <| () => {
    server.run_forever(
      (request, body, conn) => {
        assert_eq(request.path, "/chat/completions")
        match handle(@json.parse(body.read_all().text())) {
          Sse(payload) => {
            conn.send_response(200, "OK", extra_headers={
              "Content-Type": "text/event-stream",
            })
            conn.write("data: \{payload}\n\n")
            conn.write("data: [DONE]\n\n")
          }
          Body(json) => {
            conn.send_response(200, "OK", extra_headers={
              "Content-Type": "application/json",
            })
            conn.write(json.stringify())
          }
        }
      },
      max_connections=8,
    )
  }
  Some("http://127.0.0.1:\{server.addr.port()}/chat/completions")
}

///|
fn usage_json(total_tokens : Int) -> Json {
  {
    "prompt_tokens": total_tokens - 1_000,
    "completion_tokens": 1_000,
    "total_tokens": total_tokens,
  }
}

///|
fn sse_tool_call(id : String, name : String, total_tokens : Int) -> String {
  sse_tool_calls([(id, name)], total_tokens)
}

///|
fn sse_tool_calls(
  calls : Array[(String, String)],
  total_tokens : Int,
) -> String {
  let entries : Array[Json] = [
    for index, call in calls => {
      let (id, name) = call
      (
        {
          "index": index,
          "id": id,
          "type": "function",
          "function": { "name": name, "arguments": "{}" },
        } : Json)
    }
  ]
  (
    {
      "choices": [{ "delta": { "tool_calls": entries.to_json() } }],
      "usage": usage_json(total_tokens),
    } : Json).stringify()
}

///|
fn sse_final(content : String, total_tokens : Int) -> String {
  (
    {
      "choices": [{ "delta": { "content": content } }],
      "usage": usage_json(total_tokens),
    } : Json).stringify()
}

///|
fn sse_final_with_reasoning(
  content : String,
  reasoning : String,
  total_tokens : Int,
) -> String {
  (
    {
      "choices": [
        { "delta": { "content": content, "reasoning_content": reasoning } },
      ],
      "usage": usage_json(total_tokens),
    } : Json).stringify()
}

///|
fn checkpoint_body(summary : String) -> Json {
  { "choices": [{ "message": { "role": "assistant", "content": summary } }] }
}

///|
fn request_messages(request : Json) -> Array[Json] raise {
  guard request is { "messages": Array(messages), .. } else {
    fail("request without messages: \{request.stringify()}")
  }
  messages
}

///|
fn message_content(message : Json) -> String raise {
  match message {
    { "content": String(content), .. } => content
    // A tool-call-only assistant message goes out with content: null.
    { "content": Null, .. } => ""
    _ => fail("message without content: \{message.stringify()}")
  }
}

///|
/// The summary call is the only non-streaming request the loop makes; the
/// checkpoint prompt in the last message pins the classification.
fn is_checkpoint_request(request : Json) -> Bool raise {
  let messages = request_messages(request)
  !(request is { "stream": true, .. }) &&
  message_content(messages[messages.length() - 1]).contains(
    "CONTEXT CHECKPOINT COMPACTION",
  )
}

///|
/// The turn's final answer, failing the test unless the last event is a
/// finished terminal.
#callsite(autofill(loc))
fn finished_answer(
  result : @agent_session.Session,
  loc~ : SourceLoc,
) -> String raise {
  guard result.events().peek() is Some(last) &&
    last.item() is Terminal(Finished(answer)) else {
    fail("expected finished terminal", loc~)
  }
  answer
}

///|
/// The latest checkpoint summary before the terminal, failing the test when it
/// is missing. A no-tool final response is persisted between the two.
#callsite(autofill(loc))
fn summary_before_terminal(
  result : @agent_session.Session,
  loc~ : SourceLoc,
) -> @agent_session.SessionSummary raise {
  let events = result.events()
  let mut found = None
  for event in events {
    if event.item() is Summary(summary) {
      found = Some(summary)
    }
  }
  guard found is Some(summary) else {
    fail("expected the checkpoint summary before the terminal", loc~)
  }
  summary
}

///|
fn probe_tools(results : Array[String]) -> @agent_tool.Tools raise {
  let mut calls = 0
  Tools([
    AgentToolDefinition(
      name="probe",
      description="Probe tool.",
      schema=JsonSchema({ "type": "object" }),
      execute=Sync(_args => {
        calls += 1
        @agent_tool.respond(results[calls - 1])
      }),
    ),
  ])
}

///|
fn finish_definition() -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="finish",
    description="Finish tool.",
    schema=JsonSchema({ "type": "object" }),
    execute=Sync(_args => @agent_tool.ToolAction::finish("wrapped: all done")),
    control=true,
  )
}

///|
fn finish_and_probe_tools() -> @agent_tool.Tools raise {
  Tools([
    finish_definition(),
    AgentToolDefinition(
      name="probe",
      description="Probe tool.",
      schema=JsonSchema({ "type": "object" }),
      execute=Sync(_args => @agent_tool.respond("result-1")),
    ),
  ])
}

///|
async test "pressure on a tool-call response yields immediately" {
  @async.with_task_group() <| group => {
    let checkpoint_requests : Array[Json] = []
    let mut main_step = 0
    let handle = request => {
      if is_checkpoint_request(request) {
        checkpoint_requests.push(request)
        Body(checkpoint_body("CEILING-SUMMARY"))
      } else {
        main_step += 1
        Sse(sse_tool_call("call_1", "probe", 900_000))
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let session = @agent_session.Session(
        SessionId("yield-tool-batch"),
        system_prompt="system",
      )
      .append(User(UserMessage("prior question")))
      .append(Terminal(Finished("prior answer")))
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="keep grinding",
      append_item=(session, item) => session.append(item),
      api_url=url,
      tools=probe_tools(["result-1"]),
    )
    // One model round plus the checkpoint call: the arming batch is closed
    // WITHOUT executing (its results could fill the remaining headroom),
    // then the turn ends Summary-then-Terminal so the last event stays a
    // terminal.
    assert_eq(main_step, 1)
    assert_eq(checkpoint_requests.length(), 1)
    assert_true(finished_answer(result).contains("[context ceiling]"))
    let events = result.events()
    let count = events.length()
    let summary = summary_before_terminal(result)
    assert_eq(summary.content(), "CEILING-SUMMARY")
    assert_eq(summary.from_sequence(), 1)
    // The summary covers everything before it, including the closed batch.
    assert_eq(summary.to_sequence(), count - 2)
    guard events[count - 3].item() is Tool(tool_result) else {
      fail("expected the batch closed before the summary")
    }
    assert_true(tool_result.is_error())
    assert_true(
      tool_result.content().contains("yielding at the context ceiling"),
    )
  }
}

///|
async test "a final answer at pressure checkpoints then finishes normally" {
  @async.with_task_group() <| group => {
    let checkpoint_requests : Array[Json] = []
    let mut main_requests = 0
    let handle = request => {
      if is_checkpoint_request(request) {
        checkpoint_requests.push(request)
        Body(checkpoint_body("FINISH-SUMMARY"))
      } else {
        main_requests += 1
        Sse(sse_final("really done", 900_000))
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let session = @agent_session.Session(
      SessionId("compact-on-finish"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="answer briefly",
      append_item=(session, item) => session.append(item),
      api_url=url,
    )
    // Compact-on-finish: the completed turn still leaves a checkpoint, but
    // stays a normal success — the terminal carries the REAL answer.
    assert_eq(main_requests, 1)
    assert_eq(checkpoint_requests.length(), 1)
    // The answer is not durable when the summary generates: it must not be
    // foldable into the checkpoint text (it projects verbatim after it).
    assert_false(checkpoint_requests[0].stringify().contains("really done"))
    assert_eq(finished_answer(result), "really done")
    let count = result.events().length()
    let summary = summary_before_terminal(result)
    assert_eq(summary.content(), "FINISH-SUMMARY")
    assert_eq(summary.from_sequence(), 1)
    assert_eq(summary.to_sequence(), count - 3)
  }
}

///|
async test "a steer during compact-on-finish continues the turn compacted" {
  @async.with_task_group() <| group => {
    let runtime = @agent_runtime.AgentRuntime()
    let main_requests : Array[Json] = []
    let checkpoint_requests : Array[Json] = []
    let handle = request => {
      if is_checkpoint_request(request) {
        checkpoint_requests.push(request)
        // The steer lands while the compact-on-finish summary is in flight.
        runtime.queue_steer(Prompt("late steer"))
        Body(checkpoint_body("FINISH-SUMMARY"))
      } else {
        main_requests.push(request)
        if main_requests.length() == 1 {
          Sse(
            sse_final_with_reasoning(
              "really done", "ceiling reasoning trace", 750_000,
            ),
          )
        } else {
          Sse(sse_final("done", 100_000))
        }
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let session = @agent_session.Session(
      SessionId("compact-finish-late-steer"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="answer briefly",
      append_item=(session, item) => session.append(item),
      api_url=url,
    )
    // Steer beats finish once more: the turn CONTINUES instead of sealing,
    // and the continuation request is built from the compacted projection —
    // summary in, covered history out.
    assert_eq(main_requests.length(), 2)
    assert_eq(checkpoint_requests.length(), 1)
    let continuation = main_requests[1].stringify()
    assert_true(continuation.contains("FINISH-SUMMARY"))
    assert_true(continuation.contains("late steer"))
    assert_true(continuation.contains("really done"))

    // The original task is covered by the checkpoint — not resent verbatim.
    assert_false(continuation.contains("answer briefly"))
    // Durable shape: the decided answer became an ordinary assistant
    // message, the steer follows it, and the real terminal is the second
    // answer.
    let mut summary_sequence = 0
    let mut answer_sequence = 0
    let mut steer_sequence = 0
    for event in result.events() {
      match event.item() {
        Summary(_) => summary_sequence = event.sequence()
        Assistant(message) if message.content() == "really done" => {
          answer_sequence = event.sequence()
          // The converted answer keeps its reasoning: Kimi requires
          // preserved reasoning_content on historical assistant messages
          // (the encoder sends it for Kimi models only — that per-provider
          // wire behavior is pinned by the deepseek encoder tests).
          assert_true(
            message.reasoning_content() is Some("ceiling reasoning trace"),
          )
        }
        User(message) if message.content() == "late steer" =>
          steer_sequence = event.sequence()
        _ => ()
      }
    }
    // Strict order: Summary, then the kept answer (uncovered — it projects
    // right after the checkpoint), then the steer heading the continuation.
    assert_true(summary_sequence > 0)
    assert_true(answer_sequence > summary_sequence)
    assert_true(steer_sequence > answer_sequence)
    assert_eq(finished_answer(result), "done")
  }
}

///|
async test "a failed checkpoint with a late steer yields instead of continuing" {
  @async.with_task_group() <| group => {
    let runtime = @agent_runtime.AgentRuntime()
    let checkpoint_requests : Array[Json] = []
    let mut main_requests = 0
    let handle = request => {
      if is_checkpoint_request(request) {
        checkpoint_requests.push(request)
        // The steer lands during the summary request — which then FAILS.
        runtime.queue_steer(Prompt("late steer"))
        // Empty summary fails generation client-side without HTTP retries.
        Body(checkpoint_body(""))
      } else {
        main_requests += 1
        Sse(sse_final("really done", 750_000))
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let session = @agent_session.Session(
      SessionId("failed-checkpoint-late-steer"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="answer briefly",
      append_item=(session, item) => session.append(item),
      api_url=url,
    )
    // Continuing would rebuild the next request from the same pressured,
    // uncheckpointed history — so the turn yields fail-open instead. The
    // answer and the steer are durable and head the next turn.
    assert_eq(main_requests, 1)
    assert_eq(checkpoint_requests.length(), 1)
    let mut answer_kept = false
    let mut steer_kept = false
    for event in result.events() {
      assert_false(event.item() is Summary(_))
      match event.item() {
        Assistant(message) if message.content() == "really done" =>
          answer_kept = true
        User(message) if message.content() == "late steer" => steer_kept = true
        _ => ()
      }
    }
    assert_true(answer_kept)
    assert_true(steer_kept)
    let answer = finished_answer(result)
    assert_true(answer.contains("[context ceiling]"))
    assert_true(answer.contains("checkpoint attempt failed"))
  }
}

///|
async test "a non-control finish shadow is skip-closed at the ceiling" {
  @async.with_task_group() <| group => {
    let checkpoint_requests : Array[Json] = []
    let mut main_requests = 0
    let handle = request => {
      if is_checkpoint_request(request) {
        checkpoint_requests.push(request)
        Body(checkpoint_body("CEILING-SUMMARY"))
      } else {
        main_requests += 1
        Sse(sse_tool_calls([("call_1", "finish")], 900_000))
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    // A custom registry shadowing the built-in name WITHOUT declaring
    // control: salvage must not execute it — running arbitrary tool work
    // at the ceiling is exactly what the guard prevents.
    let tools : @agent_tool.Tools = Tools([
      AgentToolDefinition(
        name="finish",
        description="Not a completion.",
        schema=JsonSchema({ "type": "object" }),
        execute=Sync(_args => @agent_tool.respond("shadow ran anyway")),
      ),
    ])
    let session = @agent_session.Session(
      SessionId("finish-shadow"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="keep grinding",
      append_item=(session, item) => session.append(item),
      api_url=url,
      tools~,
    )
    assert_eq(main_requests, 1)
    assert_eq(checkpoint_requests.length(), 1)
    for event in result.events() {
      if event.item() is Tool(tool_result) {
        // Never executed: the only result is the ceiling skip note.
        assert_true(tool_result.content() != "shadow ran anyway")
        assert_true(tool_result.is_error())
        assert_true(
          tool_result.content().contains("yielding at the context ceiling"),
        )
      }
    }
    assert_true(finished_answer(result).contains("[context ceiling]"))
  }
}

///|
async test "a pressured finish batch salvages the completion" {
  @async.with_task_group() <| group => {
    let checkpoint_requests : Array[Json] = []
    let mut main_requests = 0
    let handle = request => {
      if is_checkpoint_request(request) {
        checkpoint_requests.push(request)
        Body(checkpoint_body("FINISH-SUMMARY"))
      } else {
        main_requests += 1
        Sse(
          sse_tool_calls(
            [("call_1", "probe"), ("call_2", "finish"), ("call_3", "probe")],
            900_000,
          ),
        )
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let session = @agent_session.Session(
      SessionId("finish-tool-pressure"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="wrap it up",
      append_item=(session, item) => session.append(item),
      api_url=url,
      tools=finish_and_probe_tools(),
    )
    assert_eq(main_requests, 1)
    assert_eq(checkpoint_requests.length(), 1)
    // A completed task, not a yield: the finish tool's answer verbatim.
    assert_eq(finished_answer(result), "wrapped: all done")
    // The leftover call was closed BEFORE the checkpoint, so the summary
    // range covers it — no projection repair text can leak into summaries.
    assert_eq(
      summary_before_terminal(result).to_sequence(),
      result.events().length() - 2,
    )
    let mut finish_result = false
    let mut prefix_skipped = false
    let mut leftover_closed = false
    for event in result.events() {
      if event.item() is Tool(tool_result) {
        // Neither probe may execute: their results could grow the
        // checkpoint request and cannot change the decided answer.
        assert_true(tool_result.content() != "result-1")
        if tool_result.content().contains("finished: wrapped: all done") {
          finish_result = true
        }
        if tool_result.is_error() &&
          tool_result.content().contains("yielding at the context ceiling") {
          prefix_skipped = true
        }
        if tool_result.is_error() &&
          tool_result.content().contains("finish tool call ended the batch") {
          leftover_closed = true
        }
      }
    }
    assert_true(finish_result)
    assert_true(prefix_skipped)
    assert_true(leftover_closed)
  }
}

///|
/// A completion tool under a custom name: control-declared, seals via
/// Control(Finish) exactly like the built-in `finish` — the salvage matches
/// the control declaration, not the name (a sub-run's submit tool is the
/// production shape).
async test "a pressured custom control completion is salvaged at the ceiling" {
  @async.with_task_group() <| group => {
    let checkpoint_requests : Array[Json] = []
    let mut main_requests = 0
    let handle = request => {
      if is_checkpoint_request(request) {
        checkpoint_requests.push(request)
        Body(checkpoint_body("SUBMIT-SUMMARY"))
      } else {
        main_requests += 1
        Sse(
          sse_tool_calls(
            [("call_1", "probe"), ("call_2", "submit_report")],
            900_000,
          ),
        )
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let tools : @agent_tool.Tools = Tools([
      AgentToolDefinition(
        name="submit_report",
        description="Submit the final report.",
        schema=JsonSchema({ "type": "object" }),
        execute=Sync(_args => @agent_tool.ToolAction::finish("report captured")),
        control=true,
      ),
      AgentToolDefinition(
        name="probe",
        description="Probe tool.",
        schema=JsonSchema({ "type": "object" }),
        execute=Sync(_args => @agent_tool.respond("result-1")),
      ),
    ])
    let session = @agent_session.Session(
      SessionId("custom-completion-pressure"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="wrap it up",
      append_item=(session, item) => session.append(item),
      api_url=url,
      tools~,
    )
    assert_eq(main_requests, 1)
    assert_eq(checkpoint_requests.length(), 1)
    // A completed task, not a yield: the custom completion's answer verbatim.
    assert_eq(finished_answer(result), "report captured")
    let mut completion_recorded = false
    for event in result.events() {
      if event.item() is Tool(tool_result) {
        // The probe may not execute: its result could grow the checkpoint
        // request and cannot change the decided answer.
        assert_true(tool_result.content() != "result-1")
        if tool_result.tool_name() == "submit_report" {
          completion_recorded = true
        }
      }
    }
    assert_true(completion_recorded)
  }
}

///|
/// Control calls without any sealing completion still execute at the
/// ceiling — skip-closing a durable verdict (the goal(met) shape) would
/// discard completed work — and the turn then yields as usual.
async test "a lone control verdict without a finish executes then yields" {
  @async.with_task_group() <| group => {
    let checkpoint_requests : Array[Json] = []
    let mut main_requests = 0
    let handle = request => {
      if is_checkpoint_request(request) {
        checkpoint_requests.push(request)
        Body(checkpoint_body("VERDICT-SUMMARY"))
      } else {
        main_requests += 1
        Sse(
          sse_tool_calls([("call_1", "record"), ("call_2", "probe")], 900_000),
        )
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let tools : @agent_tool.Tools = Tools([
      AgentToolDefinition(
        name="record",
        description="Record a verdict.",
        schema=JsonSchema({ "type": "object" }),
        execute=Sync(_args => @agent_tool.respond("verdict recorded")),
        control=true,
      ),
      AgentToolDefinition(
        name="probe",
        description="Probe tool.",
        schema=JsonSchema({ "type": "object" }),
        execute=Sync(_args => @agent_tool.respond("result-1")),
      ),
    ])
    let session = @agent_session.Session(
      SessionId("control-verdict-pressure"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="keep grinding",
      append_item=(session, item) => session.append(item),
      api_url=url,
      tools~,
    )
    assert_eq(main_requests, 1)
    assert_eq(checkpoint_requests.length(), 1)
    let mut verdict_recorded = false
    let mut probe_skipped = false
    for event in result.events() {
      if event.item() is Tool(tool_result) {
        assert_true(tool_result.content() != "result-1")
        if tool_result.content() == "verdict recorded" {
          assert_false(tool_result.is_error())
          verdict_recorded = true
        }
        if tool_result.is_error() &&
          tool_result.content().contains("yielding at the context ceiling") {
          probe_skipped = true
        }
      }
    }
    assert_true(verdict_recorded)
    assert_true(probe_skipped)
    assert_true(finished_answer(result).contains("[context ceiling]"))
  }
}

///|
async test "a pressured finish tool losing to a steer yields instead" {
  @async.with_task_group() <| group => {
    let runtime = @agent_runtime.AgentRuntime()
    let checkpoint_requests : Array[Json] = []
    let mut main_requests = 0
    let handle = request => {
      if is_checkpoint_request(request) {
        checkpoint_requests.push(request)
        Body(checkpoint_body("CEILING-SUMMARY"))
      } else {
        main_requests += 1
        // The steer lands while the pressured finish response is in flight.
        runtime.queue_steer(Prompt("user redirection"))
        Sse(sse_tool_calls([("call_1", "finish")], 900_000))
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let session = @agent_session.Session(
      SessionId("finish-steer-pressure"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="wrap it up",
      append_item=(session, item) => session.append(item),
      api_url=url,
      tools=finish_and_probe_tools(),
    )
    // Steer beats finish, but is never answered in a starved context: the
    // turn yields and the steer survives the checkpoint verbatim.
    assert_eq(main_requests, 1)
    assert_eq(checkpoint_requests.length(), 1)
    assert_false(
      checkpoint_requests[0].stringify().contains("user redirection"),
    )
    let mut steer_sequence = 0
    let mut summary_to = -1
    for event in result.events() {
      match event.item() {
        User(message) if message.content() == "user redirection" =>
          steer_sequence = event.sequence()
        Summary(summary) => summary_to = summary.to_sequence()
        _ => ()
      }
    }
    assert_true(steer_sequence > 0)
    assert_true(summary_to > 0)
    assert_true(summary_to < steer_sequence)
    assert_true(finished_answer(result).contains("[context ceiling]"))
  }
}

///|
async test "a failing checkpoint on a pressured finish keeps the real answer" {
  @async.with_task_group() <| group => {
    let checkpoint_requests : Array[Json] = []
    let handle = request => {
      if is_checkpoint_request(request) {
        checkpoint_requests.push(request)
        // Empty summary fails generation client-side without HTTP retries.
        Body(checkpoint_body(""))
      } else {
        Sse(sse_final("really done", 900_000))
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let session = @agent_session.Session(
      SessionId("compact-on-finish-fail-open"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="answer briefly",
      append_item=(session, item) => session.append(item),
      api_url=url,
    )
    // Fail-open: the turn still finishes as a normal success, uncompacted.
    assert_eq(checkpoint_requests.length(), 1)
    assert_eq(finished_answer(result), "really done")
    for event in result.events() {
      assert_false(event.item() is Summary(_))
    }
  }
}

///|
async test "below the soft ceiling nothing yields" {
  @async.with_task_group() <| group => {
    let mut requests = 0
    let handle = request => {
      requests += 1
      assert_false(is_checkpoint_request(request))
      if requests == 1 {
        // Below 70% of the 1M window with enough margin that the batch's
        // own small result cannot cross the boundary (post-batch growth
        // counts): the turn continues normally.
        Sse(sse_tool_call("call_1", "probe", 699_900))
      } else {
        Sse(sse_final("done", 699_900))
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let session = @agent_session.Session(
      SessionId("yield-quiet"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="do a thing",
      append_item=(session, item) => session.append(item),
      api_url=url,
      tools=probe_tools(["result-1"]),
    )
    assert_eq(requests, 2)
    assert_eq(finished_answer(result), "done")
  }
}

///|
async test "a failed checkpoint still yields fail-open" {
  @async.with_task_group() <| group => {
    let runtime = @agent_runtime.AgentRuntime()
    let checkpoint_requests : Array[Json] = []
    let handle = request => {
      if is_checkpoint_request(request) {
        checkpoint_requests.push(request)
        // Empty summary fails generation client-side without HTTP retries.
        Body(checkpoint_body(""))
      } else {
        runtime.queue_steer(Prompt("user redirection"))
        Sse(sse_tool_call("call_1", "probe", 900_000))
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let session = @agent_session.Session(
      SessionId("yield-fail-open"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="keep grinding",
      append_item=(session, item) => session.append(item),
      api_url=url,
      tools=probe_tools(["result-1"]),
    )
    // The turn still ends at the ceiling — uncompacted — so the next turn's
    // pressure retries the checkpoint instead of stranding this one.
    assert_eq(checkpoint_requests.length(), 1)
    let answer = finished_answer(result)
    assert_true(answer.contains("[context ceiling]"))
    // Honest fail-open: the terminal must not claim a checkpoint exists.
    assert_true(answer.contains("checkpoint attempt failed"))
    // No summary — but the drained steer is durable regardless of the
    // checkpoint request's fate.
    let mut steer_persisted = false
    for event in result.events() {
      assert_false(event.item() is Summary(_))
      if event.item() is User(message) &&
        message.content() == "user redirection" {
        steer_persisted = true
      }
    }
    assert_true(steer_persisted)
  }
}

///|
async test "a steer arriving under pressure survives the checkpoint verbatim" {
  @async.with_task_group() <| group => {
    let runtime = @agent_runtime.AgentRuntime()
    let checkpoint_requests : Array[Json] = []
    let mut main_step = 0
    let handle = request => {
      if is_checkpoint_request(request) {
        checkpoint_requests.push(request)
        Body(checkpoint_body("CEILING-SUMMARY"))
      } else {
        main_step += 1
        // The steer lands while the pressured response is in flight.
        runtime.queue_steer(Prompt("user redirection"))
        Sse(sse_tool_call("call_1", "probe", 900_000))
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let session = @agent_session.Session(
      SessionId("yield-steer-preserved"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="keep grinding",
      append_item=(session, item) => session.append(item),
      api_url=url,
      tools=probe_tools(["result-1"]),
    )
    // The yield proceeds regardless of the steer: one model round plus the
    // checkpoint. The steer is appended AFTER the summary range is captured,
    // so it survives verbatim — uncovered — and heads the next turn.
    assert_eq(main_step, 1)
    assert_eq(checkpoint_requests.length(), 1)
    // The summary is generated from the pre-steer session: the checkpoint
    // request must not see the steer, or its content would be folded into
    // the summary AND replayed verbatim — duplicated next turn.
    assert_false(
      checkpoint_requests[0].stringify().contains("user redirection"),
    )
    let mut steer_sequence = 0
    let mut summary_sequence = 0
    let mut summary_to = -1
    for event in result.events() {
      match event.item() {
        User(message) if message.content() == "user redirection" =>
          steer_sequence = event.sequence()
        Summary(summary) => {
          summary_sequence = event.sequence()
          summary_to = summary.to_sequence()
        }
        _ => ()
      }
    }
    assert_true(steer_sequence > 0)
    assert_true(summary_to > 0)
    // Uncovered: the checkpoint folds everything BEFORE the steer only.
    assert_true(summary_to < steer_sequence)
    // Durable order: the steer persists BEFORE the summary is appended (and
    // before the summary request is even sent — a cancellation mid-request
    // must not lose already-drained input).
    assert_true(steer_sequence < summary_sequence)
    assert_true(finished_answer(result).contains("[context ceiling]"))
  }
}

///|
async test "pressure on the last allowed step yields at the ceiling not as exhaustion" {
  @async.with_task_group() <| group => {
    let checkpoint_requests : Array[Json] = []
    let handle = request => {
      if is_checkpoint_request(request) {
        checkpoint_requests.push(request)
        Body(checkpoint_body("LAST-STEP-SUMMARY"))
      } else {
        Sse(sse_tool_call("call_1", "probe", 900_000))
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let session = @agent_session.Session(
      SessionId("yield-exhaustion"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="one pressured step",
      append_item=(session, item) => session.append(item),
      max_steps=1,
      api_url=url,
      tools=probe_tools(["result-1"]),
    )
    // Context beats steps: the pressured response yields in its own
    // iteration, so the step bound is never the one to end the turn.
    assert_eq(checkpoint_requests.length(), 1)
    assert_true(finished_answer(result).contains("[context ceiling]"))
  }
}

///|
async test "an explicit single-step bound still exhausts without pressure" {
  @async.with_task_group() <| group => {
    let mut main_step = 0
    let handle = request => {
      assert_false(is_checkpoint_request(request))
      main_step += 1
      Sse(sse_tool_call("call_1", "probe", 5_000))
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let session = @agent_session.Session(
      SessionId("bounded-one"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="one step only",
      append_item=(session, item) => session.append(item),
      max_steps=1,
      api_url=url,
      tools=probe_tools(["result-1"]),
    )
    assert_eq(main_step, 1)
    guard result.events().peek() is Some(last) &&
      last.item() is Terminal(Failed(message)) else {
      fail("expected exhaustion terminal")
    }
    assert_true(message.contains("max steps exhausted"))
  }
}

///|
async test "a soft-ceiling batch executes then yields gracefully" {
  @async.with_task_group() <| group => {
    let checkpoint_requests : Array[Json] = []
    let mut main_requests = 0
    let handle = request => {
      if is_checkpoint_request(request) {
        checkpoint_requests.push(request)
        Body(checkpoint_body("SOFT-SUMMARY"))
      } else {
        main_requests += 1
        // 70% of the 1M window exactly: the soft boundary is inclusive.
        Sse(sse_tool_call("call_1", "probe", 700_000))
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let session = @agent_session.Session(
      SessionId("soft-graceful"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="keep grinding",
      append_item=(session, item) => session.append(item),
      api_url=url,
      tools=probe_tools(["result-1"]),
    )
    // The batch EXECUTED — its real result is durable, nothing was skipped —
    // and the turn still ended at the boundary with a checkpoint.
    assert_eq(main_requests, 1)
    assert_eq(checkpoint_requests.length(), 1)
    assert_true(finished_answer(result).contains("[context ceiling]"))
    let summary = summary_before_terminal(result)
    assert_eq(summary.content(), "SOFT-SUMMARY")
    // The executed result is inside the covered range.
    assert_eq(summary.to_sequence(), result.events().length() - 2)
    let mut executed = false
    for event in result.events() {
      if event.item() is Tool(tool_result) {
        assert_false(tool_result.is_error())
        if tool_result.content() == "result-1" {
          executed = true
        }
      }
    }
    assert_true(executed)
  }
}

///|
fn flood_definition(chars : Int) -> @agent_tool.AgentToolDefinition {
  let content = "y".repeat(chars)
  AgentToolDefinition(
    name="flood",
    description="Flood tool.",
    schema=JsonSchema({ "type": "object" }),
    execute=Sync(_args => @agent_tool.respond(content)),
  )
}

///|
fn flood_tools(chars : Int) -> @agent_tool.Tools raise {
  Tools([flood_definition(chars)])
}

///|
fn flood_batch(count : Int) -> Array[(String, String)] {
  [
    for index in 0..<count => ("call_\{index + 1}", "flood")
  ]
}

///|
fn flood_and_finish_tools(chars : Int) -> @agent_tool.Tools raise {
  Tools([flood_definition(chars), finish_definition()])
}

///|
async test "a budget trip salvages a finish in the remainder" {
  @async.with_task_group() <| group => {
    let checkpoint_requests : Array[Json] = []
    let mut main_requests = 0
    let handle = request => {
      if is_checkpoint_request(request) {
        checkpoint_requests.push(request)
        Body(checkpoint_body("BUDGET-SUMMARY"))
      } else {
        main_requests += 1
        // Four floods then a finish at 750K: the budget trips before the
        // fourth flood, but the finish is a completion — a few bytes — and
        // must be honored, not skip-closed into a context yield.
        Sse(
          sse_tool_calls(
            [
              ("call_1", "flood"),
              ("call_2", "flood"),
              ("call_3", "flood"),
              ("call_4", "flood"),
              ("call_5", "finish"),
            ],
            750_000,
          ),
        )
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let session = @agent_session.Session(
      SessionId("budget-salvage"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="keep grinding",
      append_item=(session, item) => session.append(item),
      api_url=url,
      tools=flood_and_finish_tools(59_000),
    )
    assert_eq(main_requests, 1)
    assert_eq(checkpoint_requests.length(), 1)
    // A completed task, not a yield: the salvaged finish's answer.
    assert_eq(finished_answer(result), "wrapped: all done")
    ignore(summary_before_terminal(result))
    let mut executed_floods = 0
    let mut skipped = 0
    let mut finish_result = false
    for event in result.events() {
      if event.item() is Tool(tool_result) {
        if tool_result.content().length() == 59_000 {
          executed_floods += 1
        }
        if tool_result.is_error() &&
          tool_result.content().contains("yielding at the context ceiling") {
          skipped += 1
        }
        if tool_result.content().contains("finished: wrapped: all done") {
          finish_result = true
        }
      }
    }
    // Three floods fit the budget, the fourth was skip-closed, the finish ran.
    assert_eq(executed_floods, 3)
    assert_eq(skipped, 1)
    assert_true(finish_result)
  }
}

///|
async test "the running budget stops an overflowing batch mid-way" {
  @async.with_task_group() <| group => {
    let checkpoint_requests : Array[Json] = []
    let mut main_requests = 0
    let handle = request => {
      if is_checkpoint_request(request) {
        checkpoint_requests.push(request)
        Body(checkpoint_body("BUDGET-SUMMARY"))
      } else {
        main_requests += 1
        // Six calls at 750K whose ACTUAL results are ~59K chars each: after
        // three, the next call's worst case (60K cap + checkpoint reserve)
        // no longer fits under the 1M window — execution stops there.
        Sse(sse_tool_calls(flood_batch(6), 750_000))
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let session = @agent_session.Session(
      SessionId("budget-midway"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="keep grinding",
      append_item=(session, item) => session.append(item),
      api_url=url,
      tools=flood_tools(59_000),
    )
    assert_eq(main_requests, 1)
    assert_eq(checkpoint_requests.length(), 1)
    let mut executed = 0
    let mut skipped = 0
    for event in result.events() {
      if event.item() is Tool(tool_result) {
        if tool_result.is_error() &&
          tool_result.content().contains("yielding at the context ceiling") {
          skipped += 1
        } else {
          assert_eq(tool_result.content().length(), 59_000)
          executed += 1
        }
      }
    }
    // The executed prefix is covered by the checkpoint; the rest waits.
    assert_eq(executed, 3)
    assert_eq(skipped, 3)
    assert_true(finished_answer(result).contains("[context ceiling]"))
  }
}

///|
async test "a below-soft batch with huge results yields instead of overflowing" {
  @async.with_task_group() <| group => {
    let checkpoint_requests : Array[Json] = []
    let mut main_requests = 0
    let handle = request => {
      if is_checkpoint_request(request) {
        checkpoint_requests.push(request)
        Body(checkpoint_body("BUDGET-SUMMARY"))
      } else {
        main_requests += 1
        // One token BELOW the soft ceiling: no tier fires on the response,
        // yet six ~59K results would push the next request past the window.
        // The running budget is what saves it — at every usage level.
        Sse(sse_tool_calls(flood_batch(6), 699_999))
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let session = @agent_session.Session(
      SessionId("budget-below-soft"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="keep grinding",
      append_item=(session, item) => session.append(item),
      api_url=url,
      tools=flood_tools(59_000),
    )
    // The turn yields at the checkpoint instead of sending a doomed second
    // request: one model round only.
    assert_eq(main_requests, 1)
    assert_eq(checkpoint_requests.length(), 1)
    let mut executed = 0
    let mut skipped = 0
    for event in result.events() {
      if event.item() is Tool(tool_result) {
        if tool_result.is_error() &&
          tool_result.content().contains("yielding at the context ceiling") {
          skipped += 1
        } else {
          executed += 1
        }
      }
    }
    assert_eq(executed, 4)
    assert_eq(skipped, 2)
    assert_true(finished_answer(result).contains("[context ceiling]"))
  }
}

///|
async test "a finish tool in the soft band compacts and finishes normally" {
  @async.with_task_group() <| group => {
    let checkpoint_requests : Array[Json] = []
    let mut main_requests = 0
    let handle = request => {
      if is_checkpoint_request(request) {
        checkpoint_requests.push(request)
        Body(checkpoint_body("SOFT-SUMMARY"))
      } else {
        main_requests += 1
        Sse(sse_tool_calls([("call_1", "finish")], 750_000))
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let session = @agent_session.Session(
      SessionId("soft-finish"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="wrap it up",
      append_item=(session, item) => session.append(item),
      api_url=url,
      tools=finish_and_probe_tools(),
    )
    // The finish ran through the NORMAL path (no salvage needed in the
    // soft band) and compact-on-finish still checkpointed the session.
    assert_eq(main_requests, 1)
    assert_eq(checkpoint_requests.length(), 1)
    assert_eq(finished_answer(result), "wrapped: all done")
    ignore(summary_before_terminal(result))
  }
}

///|
async test "a failing checkpoint after a soft batch keeps its results" {
  @async.with_task_group() <| group => {
    let checkpoint_requests : Array[Json] = []
    let handle = request => {
      if is_checkpoint_request(request) {
        checkpoint_requests.push(request)
        // Empty summary fails generation client-side without HTTP retries.
        Body(checkpoint_body(""))
      } else {
        Sse(sse_tool_call("call_1", "probe", 750_000))
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let session = @agent_session.Session(
      SessionId("soft-fail-open"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="keep grinding",
      append_item=(session, item) => session.append(item),
      api_url=url,
      tools=probe_tools(["result-1"]),
    )
    // Fail-open: the executed result stays durable, the turn still yields.
    assert_eq(checkpoint_requests.length(), 1)
    let mut executed = false
    for event in result.events() {
      assert_false(event.item() is Summary(_))
      if event.item() is Tool(tool_result) &&
        tool_result.content() == "result-1" {
        executed = true
      }
    }
    assert_true(executed)
    let answer = finished_answer(result)
    assert_true(answer.contains("[context ceiling]"))
    assert_true(answer.contains("checkpoint attempt failed"))
  }
}

///|
async test "a steer arriving during the checkpoint request is preserved" {
  @async.with_task_group() <| group => {
    let runtime = @agent_runtime.AgentRuntime()
    let checkpoint_requests : Array[Json] = []
    let handle = request => {
      if is_checkpoint_request(request) {
        checkpoint_requests.push(request)
        // The steer lands while the summary request is being served — after
        // the one-time drain, seconds before the terminal.
        runtime.queue_steer(Prompt("late steer"))
        Body(checkpoint_body("CEILING-SUMMARY"))
      } else {
        Sse(sse_tool_call("call_1", "probe", 900_000))
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let session = @agent_session.Session(
      SessionId("late-steer"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="keep grinding",
      append_item=(session, item) => session.append(item),
      api_url=url,
      tools=probe_tools(["result-1"]),
    )
    // The second drain persists it — uncovered, after the summary — instead
    // of letting the turn-end drain drop it.
    let mut steer_sequence = 0
    let mut summary_sequence = 0
    for event in result.events() {
      match event.item() {
        User(message) if message.content() == "late steer" =>
          steer_sequence = event.sequence()
        Summary(_) => summary_sequence = event.sequence()
        _ => ()
      }
    }
    assert_true(summary_sequence > 0)
    assert_true(steer_sequence > summary_sequence)
    assert_true(finished_answer(result).contains("[context ceiling]"))
  }
}

///|
fn flood_then_finish_calls() -> Array[(String, String)] {
  let calls = flood_batch(6)
  calls.push(("call_7", "finish"))
  calls
}

///|
async test "a budget-tripped salvaged finish still checkpoints" {
  @async.with_task_group() <| group => {
    let checkpoint_requests : Array[Json] = []
    let mut main_requests = 0
    let handle = request => {
      if is_checkpoint_request(request) {
        checkpoint_requests.push(request)
        Body(checkpoint_body("SALVAGE-SUMMARY"))
      } else {
        main_requests += 1
        // Below the soft ceiling, but the executed prefix's growth (4 x ~59K)
        // trips the running budget before the finish call; the salvage must
        // carry that growth so the sealed turn is still checkpointed.
        Sse(sse_tool_calls(flood_then_finish_calls(), 699_900))
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let session = @agent_session.Session(
      SessionId("salvage-budget-checkpoint"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="wrap it up",
      append_item=(session, item) => session.append(item),
      api_url=url,
      tools=flood_and_finish_tools(59_000),
    )
    assert_eq(main_requests, 1)
    assert_eq(checkpoint_requests.length(), 1)
    // A real completion — with the checkpoint the fat prefix demands.
    assert_eq(finished_answer(result), "wrapped: all done")
    assert_eq(summary_before_terminal(result).content(), "SALVAGE-SUMMARY")
    let mut executed = 0
    let mut skipped = 0
    for event in result.events() {
      if event.item() is Tool(tool_result) {
        if tool_result.is_error() {
          skipped += 1
        } else if tool_result.content().length() == 59_000 {
          executed += 1
        }
      }
    }
    assert_eq(executed, 4)
    assert_eq(skipped, 2)
  }
}

///|
async test "a steer during a salvaged finish's checkpoint continues once" {
  @async.with_task_group() <| group => {
    let runtime = @agent_runtime.AgentRuntime()
    let checkpoint_requests : Array[Json] = []
    let mut main_requests = 0
    let handle = request => {
      if is_checkpoint_request(request) {
        checkpoint_requests.push(request)
        // The steer lands while the salvaged finish's checkpoint is in
        // flight: the finish converts into a continuation — the remainder is
        // already closed, so it must NOT be closed again or summarized twice.
        runtime.queue_steer(Prompt("late steer"))
        Body(checkpoint_body("SALVAGE-SUMMARY"))
      } else {
        main_requests += 1
        if main_requests == 1 {
          Sse(sse_tool_calls(flood_then_finish_calls(), 699_900))
        } else {
          Sse(sse_final("done", 100_000))
        }
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let session = @agent_session.Session(
      SessionId("salvage-late-steer"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="wrap it up",
      append_item=(session, item) => session.append(item),
      api_url=url,
      tools=flood_and_finish_tools(59_000),
    )
    assert_eq(main_requests, 2)
    assert_eq(checkpoint_requests.length(), 1)
    let mut summaries = 0
    let mut skip_notes = 0
    let mut steer_present = false
    let mut replayed_finish_answers = 0
    for event in result.events() {
      match event.item() {
        Summary(_) => summaries += 1
        Assistant(message) if message.content() == "wrapped: all done" => {
          assert_true(message.is_replay())
          replayed_finish_answers += 1
        }
        Tool(tool_result) =>
          if tool_result.is_error() &&
            tool_result.content().contains("yielding at the context ceiling") {
            skip_notes += 1
          }
        User(message) if message.content() == "late steer" =>
          steer_present = true
        _ => ()
      }
    }
    // Exactly one checkpoint, the two budget-skipped calls closed exactly
    // once, and the steer survives as the continuation's input.
    assert_eq(summaries, 1)
    assert_eq(skip_notes, 2)
    assert_eq(replayed_finish_answers, 1)
    assert_true(steer_present)
    assert_eq(finished_answer(result), "done")
  }
}

///|
async test "an oversized tool result is clamped at the loop" {
  @async.with_task_group() <| group => {
    let mut requests = 0
    let handle = request => {
      requests += 1
      assert_false(is_checkpoint_request(request))
      if requests == 1 {
        Sse(sse_tool_call("call_1", "flood", 100_000))
      } else {
        Sse(sse_final("done", 100_000))
      }
    }
    guard auto_compact_test_server(group, handle) is Some(url) else { return }
    let session = @agent_session.Session(
      SessionId("clamp"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime=AgentRuntime(),
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="flood me",
      append_item=(session, item) => session.append(item),
      api_url=url,
      tools=flood_tools(70_000),
    )
    let mut clamped = false
    for event in result.events() {
      if event.item() is Tool(tool_result) {
        // The 70K result was clamped to AT MOST the 60K cap — marker
        // included — so the bound the soft-tier batch budget relies on is
        // exact for EVERY tool, not just the self-clamping in-tree ones.
        assert_true(tool_result.content().length() <= 60_000)
        assert_true(tool_result.content().contains("[truncated:"))
        clamped = true
      }
    }
    assert_true(clamped)
  }
}
