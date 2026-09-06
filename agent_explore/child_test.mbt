///|
/// Mock-endpoint harness for the CHILD-side kind execution (`run_child`
/// runs the scout's turn in this process, exactly as `openseek subrun
/// explore` will in a child process). The parent-side spawn/reap path is
/// covered by the runner's own tests with scripted children.
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
async fn explore_test_server(
  group : @async.TaskGroup[Unit],
  handle : (Json) -> String raise,
) -> String? {
  guard bind_test_server("local TCP bind unavailable; skipping explore test")
    is Some(server) else {
    return None
  }
  group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
    server.run_forever(
      (request, body, conn) => {
        assert_eq(request.path, "/chat/completions")
        let payload = handle(@json.parse(body.read_all().text()))
        conn.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        conn.write("data: \{payload}\n\n")
        conn.write("data: [DONE]\n\n")
      },
      max_connections=8,
    )
  }
  Some("http://127.0.0.1:\{server.addr.port()}/chat/completions")
}

///|
fn sse_submit_answer(answer : String, total_tokens : Int) -> String {
  let report : Json = {
    "schema_version": 1,
    "answer": answer,
    "citations": [{ "file": "protocol/event.mbt", "line": 14 }],
  }
  (
    {
      "choices": [
        {
          "delta": {
            "tool_calls": [
              {
                "index": 0,
                "id": "call_1",
                "type": "function",
                "function": {
                  "name": "submit_answer",
                  "arguments": report.stringify(),
                },
              },
            ],
          },
        },
      ],
      "usage": {
        "prompt_tokens": total_tokens - 1_000,
        "completion_tokens": 1_000,
        "total_tokens": total_tokens,
      },
    } : Json).stringify()
}

///|
fn sse_plain(content : String, total_tokens : Int) -> String {
  (
    {
      "choices": [{ "delta": { "content": content } }],
      "usage": {
        "prompt_tokens": total_tokens - 1_000,
        "completion_tokens": 1_000,
        "total_tokens": total_tokens,
      },
    } : Json).stringify()
}

///|
async test "run_child answers a well-formed input with a cited report" {
  @async.with_task_group() <| group => {
    let handle : (Json) -> String raise = _request => {
      sse_submit_answer("The Event enum lives in protocol/event.mbt.", 100_000)
    }
    guard explore_test_server(group, handle) is Some(url) else { return }
    let report = @agent_explore.run_child(
      { "query": "Where is the Event enum defined?", "hints": "protocol/" },
      api_key="test-key",
      model=Deepseek(V4Flash),
      max_steps=8,
      api_url=url,
    )
    guard report is Some(report) else { fail("expected a report") }
    assert_true(report.answer.contains("Event enum lives"))
    assert_eq(report.citations.length(), 1)
  }
}

///|
async test "run_child returns None when the scout never submits" {
  @async.with_task_group() <| group => {
    let handle : (Json) -> String raise = _request => {
      sse_plain("plain text, no submit", 100_000)
    }
    guard explore_test_server(group, handle) is Some(url) else { return }
    let report = @agent_explore.run_child(
      { "query": "unanswerable" },
      api_key="test-key",
      model=Deepseek(V4Flash),
      max_steps=2,
      api_url=url,
    )
    assert_true(report is None)
  }
}

///|
async test "run_child rejects malformed input without a model call" {
  let report = @agent_explore.run_child(
    { "not_query": 1 },
    api_key="unused",
    model=Deepseek(V4Flash),
    max_steps=2,
    api_url="http://127.0.0.1:1/unused",
  )
  assert_true(report is None)
}
