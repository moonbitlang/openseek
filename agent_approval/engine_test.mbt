///|
/// Mock-endpoint harness for `run_approval_review`, which runs the review in
/// this process exactly as `openseek run --kind approval` does.
async fn approval_test_server(
  group : @async.TaskGroup[Unit],
  handle : (Json) -> String raise,
) -> String? {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0")) catch {
    error if "\{error}".contains("Operation not permitted") => {
      println("local TCP bind unavailable; skipping approval review test")
      return None
    }
    error => raise error
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
fn sse_delta(delta : Json) -> String {
  (
    {
      "choices": [{ "delta": delta }],
      "usage": {
        "prompt_tokens": 1_000,
        "completion_tokens": 100,
        "total_tokens": 1_100,
      },
    } : Json).stringify()
}

///|
fn sse_submit_verdict(verdict : Json) -> String {
  sse_delta({
    "tool_calls": [
      {
        "index": 0,
        "id": "call_1",
        "type": "function",
        "function": {
          "name": "submit_verdict",
          "arguments": verdict.stringify(),
        },
      },
    ],
  })
}

///|
fn deletion_request() -> @agent_approval.ReviewRequest {
  ReviewRequest(
    {
      tool_name: "remove",
      detail: "notes/ (deletion requires approval)",
      body: Some("{\"path\": \"notes/\"}"),
    },
    intent=["delete the notes directory"],
  )
}

///|
async test "the reviewer sees the operation and the user's words, and its verdict comes back" {
  @async.with_task_group() <| group => {
    let requests : Array[Json] = []
    let handle : (Json) -> String raise = request => {
      requests.push(request)
      sse_submit_verdict({
        "decision": "allow",
        "reason": "the user asked to delete notes/, which is committed",
      })
    }
    guard approval_test_server(group, handle) is Some(url) else { return }
    let verdict = @agent_approval.run_approval_review(
      request=deletion_request(),
      api_key="test-key",
      model=Deepseek(V4Flash),
      max_steps=4,
      api_url=url,
    )
    guard verdict is Some(verdict) else { fail("expected a verdict") }
    assert_eq(verdict.decision(), Allow)
    guard requests is [{ "messages": messages, "tools": tools, .. }, ..] else {
      fail("expected a chat request with tools")
    }
    let messages = messages.stringify()
    assert_true(messages.contains("delete the notes directory"))
    assert_true(messages.contains("notes/ (deletion requires approval)"))
    // Read-only by construction: the reviewer can inspect and submit, and
    // has nothing that edits, writes, or removes.
    let tools = tools.stringify()
    assert_true(tools.contains("submit_verdict"))
    assert_true(tools.contains("mbtx"))
    for name in ["\"remove\"", "\"write\"", "\"edit\""] {
      assert_false(tools.contains(name))
    }
  }
}

///|
async test "a reviewer that never submits yields no verdict" {
  @async.with_task_group() <| group => {
    let handle : (Json) -> String raise = _request => {
      sse_delta({ "content": "seems fine" })
    }
    guard approval_test_server(group, handle) is Some(url) else { return }
    let verdict = @agent_approval.run_approval_review(
      request=deletion_request(),
      api_key="test-key",
      model=Deepseek(V4Flash),
      max_steps=2,
      api_url=url,
    )
    assert_true(verdict is None)
  }
}
