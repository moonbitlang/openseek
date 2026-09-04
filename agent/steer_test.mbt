///|
/// A one-request DeepSeek stand-in for steering tests: asserts the request
/// carries both the original task and the steered text as user messages, then
/// streams a plain content answer so the turn finishes without tool calls.
async fn steer_test_server(group : @async.TaskGroup[Unit]) -> String? {
  guard bind_test_server("local TCP bind unavailable; skipping steer test")
    is Some(server) else {
    return None
  }
  group.spawn_bg(no_wait=true) <| () => {
    server.run_forever(
      (request, body, conn) => {
        assert_eq(request.path, "/chat/completions")
        let request_body = body.read_all().text()
        assert_true(request_body.contains("do the task"))
        assert_true(request_body.contains("also rename the file"))
        // The prebuilt registry reached the request: the standard tools ride
        // along even though the caller, not the turn, constructed them.
        assert_true(request_body.contains("\"name\":\"mbtx\""))
        conn.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        conn.write("data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\n")
        conn.write("data: [DONE]\n\n")
      },
      max_connections=1,
    )
  }
  Some("http://127.0.0.1:\{server.addr.port()}/chat/completions")
}

///|
async test "queued steering is folded in at the next step boundary" {
  @async.with_task_group() <| group => {
    guard steer_test_server(group) is Some(url) else { return }
    let runtime = @agent_runtime.AgentRuntime()
    let scope = @agent_runtime.AgentTaskScope(group)
    // Steer before the turn starts: the loop drains the steering queue at
    // its first step boundary, so the steered text must reach the model
    // alongside the task (the mock server asserts both are in the body).
    runtime.queue_steer(Prompt("also rename the file"))
    let session = @agent_session.Session(
      SessionId("steer-test"),
      system_prompt="system",
    )
    // The registry is built once by the caller, the way a serve-mode engine
    // shares it across turns.
    let tools = @agent.build_tools(runtime, scope)
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope~,
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="do the task",
      append_item=(session, item) => session.append(item),
      max_steps=2,
      api_url=url,
      tools~,
    )
    // The steered text is durably part of the conversation: task, steer,
    // final response, then the terminal seal.
    let events = result.events()
    assert_eq(events.length(), 4)
    guard events[0].item() is User(task) else { fail("expected task event") }
    assert_eq(task.content(), "do the task")
    guard events[1].item() is User(steer) else { fail("expected steer event") }
    assert_eq(steer.content(), "also rename the file")
    guard events[2].item() is Assistant(response) else {
      fail("expected durable final response")
    }
    assert_eq(response.content(), "ok")
    guard events[3].item() is Terminal(Finished(answer)) else {
      fail("expected finished terminal")
    }
    assert_eq(answer, "ok")
  }
}

///|
/// A two-request stand-in for the override path: while handling the first
/// request it steers the running turn, then answers content-only — which
/// without the pending steer would have finished the turn. The second
/// request must carry the steer and gets the real final answer.
async fn override_test_server(
  group : @async.TaskGroup[Unit],
  runtime : @agent_runtime.AgentRuntime,
) -> String? {
  guard bind_test_server("local TCP bind unavailable; skipping override test")
    is Some(server) else {
    return None
  }
  let mut requests = 0
  group.spawn_bg(no_wait=true) <| () => {
    server.run_forever(
      (_request, body, conn) => {
        requests += 1
        let request_body = body.read_all().text()
        conn.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        if requests == 1 {
          // The steer arrives while this "final" call is in flight.
          runtime.queue_steer(Prompt("actually, make it rhyme"))
          conn.write(
            "data: {\"choices\":[{\"delta\":{\"content\":\"draft answer\"}}]}\n\n",
          )
        } else {
          assert_true(request_body.contains("actually, make it rhyme"))
          assert_true(request_body.contains("draft answer"))
          conn.write(
            "data: {\"choices\":[{\"delta\":{\"content\":\"rhymed answer\"}}]}\n\n",
          )
        }
        conn.write("data: [DONE]\n\n")
      },
      max_connections=2,
    )
  }
  Some("http://127.0.0.1:\{server.addr.port()}/chat/completions")
}

///|
async test "a steer racing the final call keeps the turn alive" {
  @async.with_task_group() <| group => {
    let runtime = @agent_runtime.AgentRuntime()
    guard override_test_server(group, runtime) is Some(url) else { return }
    let scope = @agent_runtime.AgentTaskScope(group)
    let session = @agent_session.Session(
      SessionId("steer-override"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope~,
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="write a poem",
      append_item=(session, item) => session.append(item),
      max_steps=3,
      api_url=url,
    )
    // User input beat the model's completion: the draft stayed an ordinary
    // assistant message, the steer follows it, and the turn finished on the
    // second answer.
    let events = result.events()
    assert_eq(events.length(), 5)
    assert_true(events[0].item() is User(_))
    guard events[1].item() is Assistant(draft) else {
      fail("expected the draft as an assistant message")
    }
    assert_eq(draft.content(), "draft answer")
    guard events[2].item() is User(steer) else { fail("expected steer event") }
    assert_eq(steer.content(), "actually, make it rhyme")
    guard events[3].item() is Assistant(response) else {
      fail("expected durable final response")
    }
    assert_eq(response.content(), "rhymed answer")
    guard events[4].item() is Terminal(Finished(answer)) else {
      fail("expected finished terminal")
    }
    assert_eq(answer, "rhymed answer")
  }
}

///|
async fn inject_override_test_server(
  group : @async.TaskGroup[Unit],
  runtime : @agent_runtime.AgentRuntime,
  context : String,
) -> String? {
  guard bind_test_server("local TCP bind unavailable; skipping inject test")
    is Some(server) else {
    return None
  }
  let mut requests = 0
  group.spawn_bg(no_wait=true) <| () => {
    server.run_forever(
      (_request, body, conn) => {
        requests += 1
        let request_body = body.read_all().text()
        conn.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        if requests == 1 {
          runtime.queue_steer(Command(context))
          conn.write(
            "data: {\"choices\":[{\"delta\":{\"content\":\"draft answer\"}}]}\n\n",
          )
        } else {
          assert_true(request_body.contains("<user_shell_command>"))
          assert_true(request_body.contains("<command>"))
          assert_true(request_body.contains("exit=0"))
          assert_true(request_body.contains("_build"))
          assert_true(request_body.contains("draft answer"))
          conn.write(
            "data: {\"choices\":[{\"delta\":{\"content\":\"contextual answer\"}}]}\n\n",
          )
        }
        conn.write("data: [DONE]\n\n")
      },
      max_connections=2,
    )
  }
  Some("http://127.0.0.1:\{server.addr.port()}/chat/completions")
}

///|
async test "inject racing the final call keeps the turn alive" {
  @async.with_task_group() <| group => {
    let runtime = @agent_runtime.AgentRuntime()
    let context =
      #|<user_shell_command>
      #|<command>
      #|ls
      #|</command>
      #|<result>
      #|exit=0
      #|_build
      #|</result>
      #|</user_shell_command>
    guard inject_override_test_server(group, runtime, context) is Some(url) else {
      return
    }
    let scope = @agent_runtime.AgentTaskScope(group)
    let session = @agent_session.Session(
      SessionId("inject-override"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope~,
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="inspect files",
      append_item=(session, item) => session.append(item),
      max_steps=3,
      api_url=url,
    )
    let events = result.events()
    assert_eq(events.length(), 5)
    assert_true(events[0].item() is User(_))
    guard events[1].item() is Assistant(draft) else {
      fail("expected the draft as an assistant message")
    }
    assert_eq(draft.content(), "draft answer")
    guard events[2].item() is User(inject_message) else {
      fail("expected inject")
    }
    assert_eq(inject_message.content(), context)
    guard events[3].item() is Assistant(response) else {
      fail("expected durable final response")
    }
    assert_eq(response.content(), "contextual answer")
    guard events[4].item() is Terminal(Finished(answer)) else {
      fail("expected finished terminal")
    }
    assert_eq(answer, "contextual answer")
  }
}

///|
async test "blank steering input is dropped at the boundary" {
  @async.with_task_group() <| group => {
    guard steer_test_server(group) is Some(url) else { return }
    let runtime = @agent_runtime.AgentRuntime()
    let scope = @agent_runtime.AgentTaskScope(group)
    runtime.queue_steer(Prompt("   "))
    runtime.queue_steer(Prompt("also rename the file"))
    let session = @agent_session.Session(
      SessionId("steer-blank"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope~,
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="do the task",
      append_item=(session, item) => session.append(item),
      max_steps=2,
      api_url=url,
    )
    // The blank steer left no trace; only the real one was applied.
    assert_eq(result.events().length(), 4)
  }
}

///|
/// Every line the in-process protocol sink is holding, popped and parsed as
/// JSON. The engine writes only valid JSON, so an unparsable line fails the
/// test. (`poll_line` is the sink's in-process read side, live only between
/// `open` and `close`; the CLI drains to stdout instead, so a process uses
/// only one.)
fn drain_emitted() -> Array[Json] raise {
  let entries = []
  while @emit.poll_line() is Some(line) {
    entries.push(@json.parse(line))
  }
  entries
}

///|
fn log_event(entry : Json) -> String {
  match entry {
    Object(object) =>
      match object.get("event") {
        Some(String(event)) => event
        _ => ""
      }
    _ => ""
  }
}

///|
async fn reasoning_log_test_server(group : @async.TaskGroup[Unit]) -> String? {
  guard bind_test_server(
      "local TCP bind unavailable; skipping reasoning log test",
    )
    is Some(server) else {
    return None
  }
  group.spawn_bg(no_wait=true) <| () => {
    server.run_forever(
      (_request, body, conn) => {
        let _ = body.read_all()
        conn.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        conn.write(
          "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"I\"}}]}\n\n",
        )
        conn.write(
          "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\" think\"}}]}\n\n",
        )
        conn.write(
          "data: {\"choices\":[{\"delta\":{\"content\":\"done\"}}],\"usage\":{\"prompt_tokens\":3,\"completion_tokens\":5,\"total_tokens\":8,\"prompt_cache_hit_tokens\":1,\"prompt_cache_miss_tokens\":2}}\n\n",
        )
        conn.write("data: [DONE]\n\n")
      },
      max_connections=1,
    )
  }
  Some("http://127.0.0.1:\{server.addr.port()}/chat/completions")
}

///|
async test "streaming reasoning deltas are always emitted and stay transient" {
  @async.with_task_group() <| group => {
    guard reasoning_log_test_server(group) is Some(url) else { return }
    // The sink is process-global and drops events until opened: open it for
    // this turn and close it after, so the other tests in this binary never
    // accumulate lines. Drop whatever an earlier open left, so the capture
    // below is exactly this turn's events.
    @emit.open()
    defer @emit.close()
    ignore(drain_emitted())
    let session = @agent_session.Session(
      SessionId("reasoning-log-test"),
      system_prompt="system",
    )
    let result = @agent.run_turn_with_append(
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="do the task",
      append_item=(session, item) => session.append(item),
      max_steps=1,
      api_url=url,
    )
    let events = result.events()
    assert_eq(events.length(), 3)
    assert_true(events[0].item() is User(_))
    guard events[1].item() is Assistant(message) else {
      fail("expected a durable reasoning-bearing assistant response")
    }
    assert_eq(message.content(), "done")
    assert_eq(message.reasoning_content(), Some("I think"))
    guard events[2].item() is Terminal(Finished("done")) else {
      fail("expected a completed one-step turn")
    }
    // The events this turn reported, read back off the protocol sink.
    let entries = drain_emitted()
    let event_names = entries.map(log_event)
    assert_true(event_names.contains("reasoning_message"))
    assert_true(event_names.contains("assistant_delta"))
    assert_true(event_names.contains("assistant_message"))
    let reasoning_deltas : Array[String] = []
    for entry in entries {
      if entry
        is {
          "event": String("reasoning_delta"),
          "content": String(content),
          ..
        } {
        reasoning_deltas.push(content)
      }
    }
    assert_eq(reasoning_deltas.join(""), "I think")
  }
}

///|
async fn notice_test_server(
  group : @async.TaskGroup[Unit],
  runtime : @agent_runtime.AgentRuntime,
  notice : String,
  finish_first? : Bool = false,
) -> String? {
  guard bind_test_server("local TCP bind unavailable; skipping notice test")
    is Some(server) else {
    return None
  }
  let mut requests = 0
  group.spawn_bg(no_wait=true) <| () => {
    server.run_forever(
      (_request, body, conn) => {
        requests += 1
        let request_body = body.read_all().text()
        conn.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        if requests == 1 {
          // A background job finishes mid-turn and pushes a notice.
          runtime.queue_steer(Notice(notice))
          if finish_first {
            conn.write(
              "data: \{sse_tool_call("call_finish", "finish_test", 100_000)}\n\n",
            )
          } else {
            conn.write(
              "data: {\"choices\":[{\"delta\":{\"content\":\"draft\"}}]}\n\n",
            )
          }
        } else {
          // The notice was delivered to the model as user-role content.
          assert_true(request_body.contains(notice))
          conn.write(
            "data: {\"choices\":[{\"delta\":{\"content\":\"done\"}}]}\n\n",
          )
        }
        conn.write("data: [DONE]\n\n")
      },
      max_connections=2,
    )
  }
  Some("http://127.0.0.1:\{server.addr.port()}/chat/completions")
}

///|
async test "a background notice steer is applied as a runtime notice" {
  @async.with_task_group() <| group => {
    let runtime = @agent_runtime.AgentRuntime()
    let notice = "background job bg-1 finished (exit=0): `ls`"
    guard notice_test_server(group, runtime, notice) is Some(url) else {
      return
    }
    let scope = @agent_runtime.AgentTaskScope(group)
    let session = @agent_session.Session(
      SessionId("notice"),
      system_prompt="system",
    )
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope~,
      api_key="test-key",
      model=Deepseek(V4Flash),
      session~,
      task="do a task",
      append_item=(session, item) => session.append(item),
      max_steps=10,
      api_url=url,
    )
    // The notice persists as a RuntimeNotice (not a user message), so on resume
    // it renders as a system notice rather than user input.
    let notices = [
      for event in result.events() if event.item() is Runtime(n) &&
      n.content() == notice => n.content()
    ]
    assert_eq(notices.length(), 1)
    let finals = [
      for event in result.events() if event.item() is Assistant(message) &&
      message.content() == "done" => message
    ]
    // Runtime notices have no durable User boundary, so the response they
    // trigger is kept explicitly instead of existing only as a terminal.
    assert_eq(finals.length(), 1)
    assert_false(finals[0].is_replay())
  }
}

///|
async test "a runtime notice after a completion preserves the follow-up step" {
  @async.with_task_group() <| group => {
    let runtime = @agent_runtime.AgentRuntime()
    let notice = "background job bg-2 finished (exit=0): `moon test`"
    guard notice_test_server(group, runtime, notice, finish_first=true)
      is Some(url) else {
      return
    }
    let tools = @agent_tool.Tools([
      AgentToolDefinition(
        name="finish_test",
        description="Finish stand-in.",
        schema=JsonSchema({ "type": "object" }),
        execute=Sync(_args => @agent_tool.ToolAction::finish("first answer")),
      ),
    ])
    let result = @agent.run_turn_in_scope(
      runtime~,
      scope=AgentTaskScope(group),
      api_key="test-key",
      model=Deepseek(V4Flash),
      session=Session(
        SessionId("notice-after-completion"),
        system_prompt="system",
      ),
      task="do a task",
      append_item=(session, item) => session.append(item),
      max_steps=3,
      api_url=url,
      tools~,
    )
    let events = result.events()
    let mut completions = 0
    for event in events {
      if event.item() is Tool(tool) && tool.tool_name() == "finish_test" {
        completions += 1
      }
    }
    assert_eq(completions, 1)
    guard events[events.length() - 2].item() is Assistant(message) else {
      fail("expected explicit follow-up step before its terminal")
    }
    assert_eq(message.content(), "done")
    assert_false(message.is_replay())
    assert_true(
      events.peek() is Some(last) && last.item() is Terminal(Finished("done")),
    )
  }
}
