///|
/// A canned Anthropic-style Messages response body: two searched sources, one
/// carrying a citation excerpt in a separate text block.
fn sample_response_body() -> String {
  (
    {
      "content": [
        {
          "type": "server_tool_use",
          "id": "srvtoolu_1",
          "name": "web_search",
          "input": { "query": "moonbit language" },
        },
        {
          "type": "web_search_tool_result",
          "tool_use_id": "srvtoolu_1",
          "content": [
            {
              "type": "web_search_result",
              "url": "https://example.com/a",
              "title": "Example A",
              "page_age": "January 5, 2026",
            },
            { "type": "web_search_result", "url": "https://example.org/b" },
          ],
        },
        {
          "type": "text",
          "text": "According to Example A, MoonBit is fast.",
          "citations": [
            {
              "type": "citations_web_search_result_location",
              "url": "https://example.com/a",
              "cited_text": "MoonBit is a fast language.",
            },
          ],
        },
      ],
    } : Json).stringify()
}

///|
/// Bind a localhost mock server for one test, or report the skip and return
/// `None` where the sandbox forbids TCP binds.
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
async test "web_search executes end-to-end against a mock messages endpoint" {
  @async.with_task_group(group => {
    guard bind_test_server(
        "local TCP bind unavailable; skipping web_search test",
      )
      is Some(server) else {
      return
    }
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, conn) => {
          let _ = body.read_all()
          assert_eq(request.path, "/anthropic/v1/messages")
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          conn.write(sample_response_body())
        },
        max_connections=4,
      )
    }
    let tool = @web_search.definition(
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/anthropic/v1",
    )
    assert_eq(tool.name, "web_search")
    guard tool.execute is Async(execute) else {
      fail("expected async executor")
    }
    let action = execute({ "query": "moonbit language" })
    guard action is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_true(output.content.contains("[Example A](https://example.com/a)"))
    assert_true(
      output.content.contains("- [example.org](https://example.org/b)"),
    )
    assert_true(output.content.contains("Cite the relevant URLs"))
    guard output.brief is Some(brief) else { fail("expected a brief") }
    assert_true(brief.contains("web_search"))
  })
}

///|
async test "web_search surfaces a provider error as a recoverable tool error" {
  @async.with_task_group(group => {
    guard bind_test_server(
        "local TCP bind unavailable; skipping web_search test",
      )
      is Some(server) else {
      return
    }
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, conn) => {
          let _ = body.read_all()
          conn.send_response(401, "Unauthorized", extra_headers={
            "Content-Type": "application/json",
          })
          conn.write(
            "{\"error\":{\"type\":\"authentication_error\",\"message\":\"invalid x-api-key\"}}",
          )
        },
        max_connections=4,
      )
    }
    let tool = @web_search.definition(
      api_key="bad-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/anthropic/v1",
    )
    guard tool.execute is Async(execute) else {
      fail("expected async executor")
    }
    let action = execute({ "query": "moonbit language" })
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("401"))
    assert_true(output.content.contains("invalid x-api-key"))
  })
}

///|
async test "web_search rejects blank and oversized queries locally" {
  guard @web_search.definition(api_key="k").execute is Async(execute) else {
    fail("expected async executor")
  }
  guard execute({ "query": "   " }) is Respond(blank) else {
    fail("expected Respond")
  }
  assert_true(blank.is_error)
  assert_true(blank.content.contains("non-empty string `query`"))
  // One past the tool's documented 2000-char query cap.
  guard execute({ "query": "q".repeat(2001).to_json() }) is Respond(oversized) else {
    fail("expected Respond")
  }
  assert_true(oversized.is_error)
  assert_true(oversized.content.contains("exceeds"))
}
