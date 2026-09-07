///|
async test "stream failure diagnostics preserve HTTP error payload after exhausted retries" {
  @async.with_task_group() <| group => {
    guard flaky_server(group, failures=99, status=503, sse=true)
      is Some((url, hits)) else {
      return
    }
    let failures : Array[String] = []
    let client = @client.Client(
      api_key="private-key",
      api_url=url,
      retry_attempts=2,
      retry_backoff_ms=1,
    )
    try
      client.chat(
        [ChatMessage(User, content="private prompt")],
        stream=StreamHandler(on_content_delta=_ => ()),
      )
    catch {
      Failure(message) => failures.push(message)
      error => raise error
    } noraise {
      _ => fail("expected failure")
    }
    assert_eq(hits.val, 2)
    assert_eq(failures.length(), 1)
    let text = failures[0]
    assert_true(text.contains("attempts: 2/2"))
    assert_true(text.contains("HTTP 503"))
    assert_true(text.contains("The retry limit was reached."))
    assert_true(text.contains("stage: response_body"))
    assert_false(text.contains("last event:"))
    assert_false(text.contains("stream events:"))
    assert_false(text.contains("buffered event:"))
    assert_false(text.contains("private"))
    assert_true(text.contains("synthetic failure"))
    assert_false(text.contains(url))
  }
}

///|
async test "stream diagnostics distinguish non-retryable HTTP errors" {
  @async.with_task_group() <| group => {
    guard flaky_server(group, failures=99, status=400, sse=true)
      is Some((url, hits)) else {
      return
    }
    let failures : Array[String] = []
    try
      @client.Client(api_key="test", api_url=url).chat(
        [ChatMessage(User, content="hello")],
        stream=StreamHandler(on_content_delta=_ => ()),
      )
    catch {
      Failure(message) => failures.push(message)
      error => raise error
    } noraise {
      _ => fail("expected failure")
    }
    assert_eq(hits.val, 1)
    assert_eq(failures.length(), 1)
    assert_true(
      failures[0].contains("This error cannot be retried automatically."),
    )
  }
}

///|
async test "idle stream diagnostics report partial output without retrying" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let hits = Ref(0)
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever((_request, body, conn) => {
        ignore(body.read_all())
        hits.val += 1
        conn.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        conn.write(
          "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n",
        )
        conn.flush()
        @async.sleep(3000)
      })
    }
    let failures : Array[String] = []
    try
      @client.Client(
        api_key="test",
        api_url="http://127.0.0.1:\{server.addr.port()}/",
        idle_timeout_ms=100,
      ).chat(
        [ChatMessage(User, content="hello")],
        stream=StreamHandler(on_content_delta=_ => ()),
      )
    catch {
      Failure(message) => failures.push(message)
      error => raise error
    } noraise {
      _ => fail("expected timeout")
    }
    assert_eq(hits.val, 1)
    assert_eq(failures.length(), 1)
    let text = failures[0]
    assert_true(text.contains("Request idle for 100 ms"))
    assert_true(text.contains("stage: sse_read"))
    assert_true(text.contains("stream events: 1"))
    assert_true(
      text.contains("Not retried because response data was already received."),
    )
    assert_true(text.contains("last event:"))
    assert_true(text.contains("elapsed:"))
  }
}

///|
async test "a thrown body read after a buffered data line cannot replay the request" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let hits = Ref(0)
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, conn) => {
          ignore(body.read_all())
          hits.val += 1
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
            "Content-Length": "10000",
          })
          conn.write(
            "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n",
          )
          conn.flush()
          conn.close()
        },
        allow_failure=true,
      )
    }
    let failures : Array[String] = []
    try
      @client.Client(
        api_key="test",
        api_url="http://127.0.0.1:\{server.addr.port()}/",
        retry_backoff_ms=1,
      ).chat(
        [ChatMessage(User, content="hello")],
        stream=StreamHandler(on_content_delta=_ => ()),
      )
    catch {
      Failure(message) => failures.push(message)
      error => raise error
    } noraise {
      _ => fail("expected body read failure")
    }
    assert_eq(hits.val, 1)
    assert_eq(failures.length(), 1)
    assert_true(
      failures[0].contains(
        "Not retried because response data was already received.",
      ),
    )
  }
}

///|
async test "cancellation is not wrapped as a request failure" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever((_request, body, _conn) => {
        ignore(body.read_all())
        @async.sleep(3000)
      })
    }
    let result = @async.with_timeout_opt(100, () => {
      @client.Client(
        api_key="test",
        api_url="http://127.0.0.1:\{server.addr.port()}/",
      ).chat(
        [ChatMessage(User, content="hello")],
        stream=StreamHandler(on_content_delta=_ => ()),
      )
    })
    assert_true(result is None)
  }
}

///|
async test "malformed buffered response is not mislabeled as the idle timeout that flushed it" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let hits = Ref(0)
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever((_request, body, conn) => {
        ignore(body.read_all())
        hits.val += 1
        conn.send_response(200, "OK", extra_headers={
          "Content-Type": "text/event-stream",
        })
        // No blank-line terminator. The idle handler will flush this payload;
        // its parse error, not the timeout, is the actual failure cause.
        conn.write("data: private-invalid-json\n")
        conn.flush()
        @async.sleep(3000)
      })
    }
    let failures : Array[String] = []
    try
      @client.Client(
        api_key="test",
        api_url="http://127.0.0.1:\{server.addr.port()}/",
        idle_timeout_ms=100,
      ).chat(
        [ChatMessage(User, content="hello")],
        stream=StreamHandler(on_content_delta=_ => ()),
      )
    catch {
      Failure(message) => failures.push(message)
      error => raise error
    } noraise {
      _ => fail("expected invalid response")
    }
    assert_eq(hits.val, 1)
    assert_eq(failures.length(), 1)
    let text = failures[0]
    assert_true(text.contains("DeepSeek stream decode error"))
    assert_true(
      text.contains("Not retried because response data was already received."),
    )
    assert_true(text.contains("stream events: 1"))
    assert_false(text.contains("Request idle"))
    assert_true(text.contains("private-invalid-json"))
  }
}

///|
suberror StreamCallbackError {
  StreamCallbackError(String)
} derive(Debug)

///|
async test "fallback diagnostics preserve error representation and payload" {
  @async.with_task_group() <| group => {
    guard flaky_server(group, failures=0, status=200, sse=true)
      is Some((url, hits)) else {
      return
    }
    try
      @client.Client(api_key="test", api_url=url).chat(
        [ChatMessage(User, content="hello")],
        stream=StreamHandler(on_content_delta=_ => {
          raise StreamCallbackError("callback error payload")
        }),
      )
    catch {
      Failure(message) => {
        assert_true(message.contains("StreamCallbackError"))
        assert_true(message.contains("callback error payload"))
        assert_false(message.contains("omitted"))
      }
      error => raise error
    } noraise {
      _ => fail("expected callback failure")
    }
    assert_eq(hits.val, 1)
  }
}
