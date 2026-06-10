///|
async fn stream_test_server(
  group : @async.TaskGroup[Unit],
  finish? : Bool = true,
) -> String? {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0")) catch {
    error => {
      let message = "\{error}"
      if message.contains("Operation not permitted") {
        println("local TCP bind unavailable; skipping stream test: \{message}")
        return None
      }
      raise error
    }
  }
  group.spawn_bg(no_wait=true) <| () => {
    server.run_forever(
      (request, body, conn) => {
        assert_eq(request.path, "/chat/completions")
        // The streaming request pins the identity encoding: a gzip-compressing
        // intermediary would buffer compression blocks and re-batch the SSE
        // deltas.
        assert_true(request.headers.get("accept-encoding") is Some("identity"))
        let request_body = body.read_all().text()
        assert_true(request_body.contains("\"stream\":true"))
        assert_true(request_body.contains("\"include_usage\":true"))
        assert_false(request_body.contains("\"response_format\""))
        conn.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        conn.write(
          "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n",
        )
        conn.flush()
        conn.write(
          "data: {\"choices\":[{\"delta\":{\"content\":\" world\",\"reasoning_content\":\"hidden\",\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"read\",\"arguments\":\"{\\\"path\\\"\"}}]}}]}\n\n",
        )
        conn.write(
          "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\":\\\"moon.mod\\\"}\"}}]}}],\"usage\":{\"prompt_tokens\":3,\"completion_tokens\":5,\"total_tokens\":8,\"prompt_cache_hit_tokens\":1,\"prompt_cache_miss_tokens\":2}}\n\n",
        )
        if finish {
          conn.write("data: [DONE]\n\n")
        }
      },
      max_connections=1,
    )
  }
  Some("http://127.0.0.1:\{server.addr.port()}/chat/completions")
}

///|
async test "chat_stream accumulates SSE content, tool calls, and usage" {
  @async.with_task_group() <| group => {
    guard stream_test_server(group) is Some(url) else { return }
    let client = @client.Client(api_key="test-key", api_url=url)
    let deltas : Array[String] = []
    let reasoning_deltas : Array[String] = []
    let response = client.chat_stream(
      [ChatMessage(User, content="hello")],
      on_content_delta=delta => deltas.push(delta),
      on_reasoning_delta=delta => reasoning_deltas.push(delta),
    )
    assert_eq(deltas.join("|"), "Hello| world")
    assert_eq(reasoning_deltas.join("|"), "hidden")
    assert_eq(response.content, "Hello world")
    assert_eq(response.reasoning_content, "hidden")
    assert_eq(response.tool_calls.length(), 1)
    assert_eq(response.tool_calls[0].id, "call_1")
    assert_eq(response.tool_calls[0].name, "read")
    assert_eq(response.tool_calls[0].arguments, "{\"path\":\"moon.mod\"}")
    assert_eq(response.usage.prompt_tokens, 3)
    assert_eq(response.usage.completion_tokens, 5)
    assert_eq(response.usage.total_tokens, 8)
    assert_eq(response.usage.prompt_cache_hit_tokens, 1)
    assert_eq(response.usage.prompt_cache_miss_tokens, 2)
  }
}

///|
async test "chat_stream rejects EOF before done" {
  @async.with_task_group() <| group => {
    guard stream_test_server(group, finish=false) is Some(url) else { return }
    let client = @client.Client(api_key="test-key", api_url=url)
    try {
      let _ = client.chat_stream([ChatMessage(User, content="hello")], on_content_delta=_ => {
        ()
      })
      fail("expected truncated stream to fail")
    } catch {
      error => assert_true("\{error}".contains("ended before [DONE]"))
    }
  }
}
