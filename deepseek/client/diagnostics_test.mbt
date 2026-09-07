///|
async test "stream failure diagnostics preserve HTTP error payload after exhausted retries" {
  @async.with_task_group() <| group => {
    guard flaky_server(group, failures=99, status=503, sse=true)
      is Some((url, hits)) else {
      return
    }
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
      Failure(message) => assert_true(message.contains("synthetic failure"))
      error => raise error
    } noraise {
      _ => fail("expected failure")
    }
    assert_eq(hits.val, 2)
  }
}

///|
async test "stream never retries a non-retryable HTTP error" {
  @async.with_task_group() <| group => {
    guard flaky_server(group, failures=99, status=400, sse=true)
      is Some((url, hits)) else {
      return
    }
    try
      @client.Client(api_key="test", api_url=url).chat(
        [ChatMessage(User, content="hello")],
        stream=StreamHandler(on_content_delta=_ => ()),
      )
    catch {
      Failure(_) => ()
      error => raise error
    } noraise {
      _ => fail("expected failure")
    }
    assert_eq(hits.val, 1)
  }
}

///|
async test "idle stream delivers partial output once without retrying" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let mut hits = 0
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever((_request, body, conn) => {
        ignore(body.read_all())
        hits += 1
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
    let deltas : Array[String] = []
    try
      @client.Client(
        api_key="test",
        api_url="http://127.0.0.1:\{server.addr.port()}/",
        idle_timeout_ms=100,
      ).chat(
        [ChatMessage(User, content="hello")],
        stream=StreamHandler(on_content_delta=delta => deltas.push(delta)),
      )
    catch {
      Failure(_) => ()
      error => raise error
    } noraise {
      _ => fail("expected timeout")
    }
    assert_eq(hits, 1)
    assert_eq(deltas, ["partial"])
  }
}

///|
async test "a thrown body read after a buffered data line cannot replay the request" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let mut hits = 0
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, conn) => {
          ignore(body.read_all())
          hits += 1
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
      Failure(_) => ()
      error => raise error
    } noraise {
      _ => fail("expected body read failure")
    }
    assert_eq(hits, 1)
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
async test "idle flush preserves malformed response payload without retrying" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let mut hits = 0
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever((_request, body, conn) => {
        ignore(body.read_all())
        hits += 1
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
      Failure(message) => assert_true(message.contains("private-invalid-json"))
      error => raise error
    } noraise {
      _ => fail("expected invalid response")
    }
    assert_eq(hits, 1)
  }
}

///|
suberror StreamCallbackError {
  StreamCallbackError(String)
} derive(Debug)

///|
async test "fallback diagnostics preserve the original error payload" {
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
      Failure(message) =>
        assert_true(message.contains("callback error payload"))
      error => raise error
    } noraise {
      _ => fail("expected callback failure")
    }
    assert_eq(hits.val, 1)
  }
}
