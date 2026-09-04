///|
/// Mock-endpoint harness for the child-side executor: `execute_kind` runs
/// the kind's turn in THIS process, exactly as the `openseek subrun` child
/// mode does — so the full internal lifecycle (capture, reject-retry,
/// ceiling salvage) is unit-testable without spawning anything.
priv enum MockReply {
  Sse(String)
  Body(Json)
}

///|
async fn bind_test_server(skip_message : String) -> @http.Server? {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0")) catch {
    error if "\{error}".contains("Operation not permitted") => {
      println(skip_message)
      return None
    }
    error => raise error
  }
  Some(server)
}

///|
async fn child_test_server(
  group : @async.TaskGroup[Unit],
  handle : (Json) -> MockReply raise,
) -> String? {
  guard bind_test_server("local TCP bind unavailable; skipping child test")
    is Some(server) else {
    return None
  }
  group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
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
fn sse_tool_calls(
  calls : Array[(String, String, String)],
  total_tokens : Int,
) -> String {
  let entries : Array[Json] = [
    for index, call in calls => {
      let (id, name, arguments) = call
      (
        {
          "index": index,
          "id": id,
          "type": "function",
          "function": { "name": name, "arguments": arguments },
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
fn is_checkpoint_request(request : Json) -> Bool {
  guard request is { "messages": Array(messages), .. } &&
    messages.last() is Some({ "content": String(content), .. }) else {
    return false
  }
  !(request is { "stream": True, .. }) &&
  content.contains("CONTEXT CHECKPOINT COMPACTION")
}

///|
/// The standard kind under test: one `submit` capture tool expecting
/// `{"answer": <string>}`, plus a plain probe tool.
async fn run_answer_kind(
  url : String,
  session_id : String,
  max_steps? : Int = 8,
) -> String? {
  @agent_subrun.execute_kind(
    session_id~,
    system_prompt="You are a test subagent.",
    task="Answer via the submit tool.",
    tools=captured => {
      @agent_tool.Tools([
        @agent_subrun.capture_tool(
          name="submit",
          description="Submit the final answer.",
          schema=JsonSchema({ "type": "object" }),
          parse=args => {
            match args {
              { "answer": String(answer), .. } => Ok(answer)
              _ => Err(["answer must be a string"])
            }
          },
          captured,
        ),
        AgentToolDefinition(
          name="probe",
          description="Probe tool.",
          schema=JsonSchema({ "type": "object" }),
          execute=Sync(_args => @agent_tool.respond("result-1")),
        ),
      ])
    },
    max_steps~,
    api_key="test-key",
    model=Deepseek(V4Flash),
    api_url=url,
  )
}

///|
async test "a valid submission is captured" {
  @async.with_task_group() <| group => {
    let handle : (Json) -> MockReply raise = _request => {
      Sse(
        sse_tool_calls(
          [("call_1", "submit", "{\"answer\": \"forty-two\"}")],
          100_000,
        ),
      )
    }
    guard child_test_server(group, handle) is Some(url) else { return }
    assert_true(run_answer_kind(url, "capture") is Some("forty-two"))
  }
}

///|
async test "a rejected submission is retried and then captured" {
  @async.with_task_group() <| group => {
    let mut step = 0
    let handle : (Json) -> MockReply raise = _request => {
      step += 1
      if step == 1 {
        Sse(sse_tool_calls([("call_1", "submit", "{\"answer\": 7}")], 100_000))
      } else {
        Sse(
          sse_tool_calls(
            [("call_2", "submit", "{\"answer\": \"second try\"}")],
            110_000,
          ),
        )
      }
    }
    guard child_test_server(group, handle) is Some(url) else { return }
    assert_true(run_answer_kind(url, "retry") is Some("second try"))
  }
}

///|
async test "a run that never captures returns None" {
  @async.with_task_group() <| group => {
    let handle : (Json) -> MockReply raise = _request => {
      Sse(sse_final("plain answer, no submit", 100_000))
    }
    guard child_test_server(group, handle) is Some(url) else { return }
    assert_true(run_answer_kind(url, "no-report") is None)
  }
}

///|
async test "step exhaustion without a capture returns None" {
  @async.with_task_group() <| group => {
    let mut step = 0
    let handle : (Json) -> MockReply raise = _request => {
      step += 1
      Sse(sse_tool_calls([("call_\{step}", "probe", "{}")], 100_000))
    }
    guard child_test_server(group, handle) is Some(url) else { return }
    assert_true(run_answer_kind(url, "max-steps", max_steps=2) is None)
  }
}

///|
/// The A1 interlock: at the context ceiling a pending capture call is
/// salvaged (control-declared), so the child seals with its report instead
/// of losing it to a skip-close.
async test "a capture at the context ceiling is salvaged" {
  @async.with_task_group() <| group => {
    let handle : (Json) -> MockReply raise = request => {
      if is_checkpoint_request(request) {
        Body({
          "choices": [
            { "message": { "role": "assistant", "content": "SUMMARY" } },
          ],
        })
      } else {
        Sse(
          sse_tool_calls(
            [
              ("call_1", "probe", "{}"),
              ("call_2", "submit", "{\"answer\": \"under pressure\"}"),
            ],
            900_000,
          ),
        )
      }
    }
    guard child_test_server(group, handle) is Some(url) else { return }
    assert_true(
      run_answer_kind(url, "ceiling-capture") is Some("under pressure"),
    )
  }
}

///|
/// `append_item` makes the child's transcript durable: with a store-backed
/// append the session file materializes as the turn runs, holding the same
/// items an in-memory child accumulates — system prompt, task, tool
/// round-trip, terminal.
async test "a store-backed append_item persists the child transcript" {
  @async.with_task_group() <| group => {
    let handle : (Json) -> MockReply raise = _request => {
      Sse(
        sse_tool_calls(
          [("call_1", "submit", "{\"answer\": \"persisted\"}")],
          100_000,
        ),
      )
    }
    guard child_test_server(group, handle) is Some(url) else { return }
    let store = @store.SessionStore(@fs.tmpdir(prefix="openseek-subrun-child-"))
    defer @fs.rmdir(store.root(), recursive=true)
    let value = @agent_subrun.execute_kind(
      session_id="parent-sr-1",
      system_prompt="You are a test subagent.",
      task="Answer via the submit tool.",
      tools=captured => {
        @agent_tool.Tools([
          @agent_subrun.capture_tool(
            name="submit",
            description="Submit the final answer.",
            schema=JsonSchema({ "type": "object" }),
            parse=args => {
              match args {
                { "answer": String(answer), .. } => Ok(answer)
                _ => Err(["answer must be a string"])
              }
            },
            captured,
          ),
        ])
      },
      max_steps=8,
      api_key="test-key",
      model=Deepseek(V4Flash),
      api_url=url,
      append_item=(session, item) => store.append(session, item),
    )
    assert_true(value is Some("persisted"))
    let loaded = store.load(@agent_session.SessionId("parent-sr-1"))
    assert_eq(loaded.system_prompt(), "You are a test subagent.")
    // The durable transcript holds the whole turn, not just a header.
    assert_true(loaded.events().length() >= 3)
  }
}
