///|
/// Mock-endpoint harness for `run_review`, which runs the review in this
/// process exactly as `openseek run --kind review` with a `base` does.
async fn review_test_server(
  group : @async.TaskGroup[Unit],
  handle : (Json) -> String raise,
) -> String? {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0")) catch {
    error if "\{error}".contains("Operation not permitted") => {
      println("local TCP bind unavailable; skipping review test")
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
fn sse_submit_review() -> String {
  let report : Json = {
    "schema_version": 1,
    "scope": { "base": "origin/main", "head": "HEAD", "files": ["a.mbt"] },
    "findings": [
      {
        "file": "a.mbt",
        "line": 3,
        "severity": "blocker",
        "category": "correctness",
        "title": "wrong bound",
        "detail": "moon test fails on the new case",
      },
    ],
    "summary": "one blocker",
    "stats": {
      "files_reviewed": 1,
      "findings": 1,
      "build": "pass",
      "tests": "fail",
    },
  }
  sse_delta({
    "tool_calls": [
      {
        "index": 0,
        "id": "call_1",
        "type": "function",
        "function": { "name": "submit_review", "arguments": report.stringify() },
      },
    ],
  })
}

///|
async test "run_review forwards the model and base, records the turn, and returns the report" {
  @async.with_task_group() <| group => {
    let requests : Array[Json] = []
    let handle : (Json) -> String raise = request => {
      requests.push(request)
      sse_submit_review()
    }
    guard review_test_server(group, handle) is Some(url) else { return }
    let mut recorded = 0
    let report = @agent_review.run_review(
      base="origin/main",
      api_key="test-key",
      model=Deepseek(V4Flash),
      max_steps=4,
      api_url=url,
      append_item=(session, item) => {
        recorded += 1
        session.append(item)
      },
    )
    guard report is Some(report) else { fail("expected a report") }
    assert_true(report.has_blockers())
    assert_true(recorded > 0)
    guard requests is [{ "model": String(model), "messages": messages, .. }, ..] else {
      fail("expected a chat request")
    }
    assert_eq(model, @deepseek.Model::Deepseek(V4Flash).to_string())
    assert_true(messages.stringify().contains("between origin/main and HEAD"))
  }
}

///|
async test "run_review returns None when the reviewer never submits" {
  @async.with_task_group() <| group => {
    let handle : (Json) -> String raise = _request => {
      sse_delta({ "content": "looks fine to me" })
    }
    guard review_test_server(group, handle) is Some(url) else { return }
    let report = @agent_review.run_review(
      base="origin/main",
      api_key="test-key",
      model=Deepseek(V4Flash),
      max_steps=2,
      api_url=url,
    )
    assert_true(report is None)
  }
}
