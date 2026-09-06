///|
/// A server whose first `failures` responses are `status`, after which it
/// serves a minimal valid chat completion (or an SSE stream when `sse`).
/// Returns the endpoint URL and a counter of requests actually received.
async fn flaky_server(
  group : @async.TaskGroup[Unit],
  failures~ : Int,
  status~ : Int,
  sse? : Bool = false,
) -> (String, Ref[Int])? {
  guard bind_test_server("local TCP bind unavailable; skipping retry test")
    is Some(server) else {
    return None
  }
  let hits : Ref[Int] = { val: 0, }
  group.spawn_bg(no_wait=true) <| () => {
    server.run_forever(
      (_request, body, conn) => {
        let _ = body.read_all()
        hits.val += 1
        if hits.val <= failures {
          conn.send_response(status, "Error", extra_headers={
            "Content-Type": "text/plain",
          })
          conn.write("synthetic failure")
        } else if sse {
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          conn.write(
            "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\n",
          )
          conn.write("data: [DONE]\n\n")
        } else {
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          conn.write(
            "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"ok\"}}]}",
          )
        }
      },
      max_connections=8,
    )
  }
  Some(("http://127.0.0.1:\{server.addr.port()}/chat/completions", hits))
}

///|
/// The retrying client these tests drive: the fake key, the flaky server's
/// endpoint, and a 1ms backoff so a retry budget is exercised without real
/// sleeps. Only the attempt budget varies per test.
fn retry_client(url : String, attempts~ : Int) -> @client.Client {
  Client(
    api_key="test-key",
    api_url=url,
    retry_attempts=attempts,
    retry_backoff_ms=1,
  )
}

///|
async test "chat retries transient 5xx and succeeds" {
  @async.with_task_group() <| group => {
    guard flaky_server(group, failures=2, status=503) is Some((url, hits)) else {
      return
    }
    let client = retry_client(url, attempts=3)
    let response = client.chat([ChatMessage(User, content="hello")])
    assert_eq(response.content, "ok")
    assert_eq(hits.val, 3)
  }
}

///|
async test "chat gives up after the retry budget with the API error" {
  @async.with_task_group() <| group => {
    guard flaky_server(group, failures=99, status=500) is Some((url, hits)) else {
      return
    }
    let client = retry_client(url, attempts=2)
    let _ = client.chat([ChatMessage(User, content="hello")]) catch {
      error => {
        assert_true("\{error}".contains("DeepSeek API error 500"))
        assert_eq(hits.val, 2)
        return
      }
    }
    fail("expected exhausted retries")
  }
}

///|
async test "chat never retries a non-429 client error" {
  @async.with_task_group() <| group => {
    guard flaky_server(group, failures=99, status=400) is Some((url, hits)) else {
      return
    }
    let client = retry_client(url, attempts=3)
    let _ = client.chat([ChatMessage(User, content="hello")]) catch {
      error => {
        assert_true("\{error}".contains("DeepSeek API error 400"))
        assert_eq(hits.val, 1)
        return
      }
    }
    fail("expected immediate failure")
  }
}

///|
async test "streaming chat retries a pre-stream 429 and then streams" {
  @async.with_task_group() <| group => {
    guard flaky_server(group, failures=1, status=429, sse=true)
      is Some((url, hits)) else {
      return
    }
    let client = retry_client(url, attempts=3)
    let deltas : Array[String] = []
    let response = client.chat(
      [ChatMessage(User, content="hello")],
      stream=StreamHandler(on_content_delta=delta => deltas.push(delta)),
    )
    assert_eq(response.content, "ok")
    assert_eq(deltas.join("|"), "ok")
    assert_eq(hits.val, 2)
  }
}

///|
async test "streaming Kimi chat retries a pre-stream 502 and then streams" {
  @async.with_task_group() <| group => {
    guard flaky_server(group, failures=1, status=502, sse=true)
      is Some((url, hits)) else {
      return
    }
    let client = @client.Client(
      api_key="test-key",
      model=Kimi(K27Code),
      api_url=url,
      retry_attempts=3,
      retry_backoff_ms=1,
    )
    let deltas : Array[String] = []
    let response = client.chat(
      [ChatMessage(User, content="hello")],
      stream=StreamHandler(on_content_delta=delta => deltas.push(delta)),
    )
    assert_eq(response.content, "ok")
    assert_eq(deltas.join("|"), "ok")
    assert_eq(hits.val, 2)
  }
}

///|
/// A 2xx connection that dies before any event is transport-shaped: with no
/// delta delivered, the stream call retries and the second connection
/// serves the full stream.
async test "streaming chat retries a pre-delta stream drop" {
  @async.with_task_group() <| group => {
    guard bind_test_server("local TCP bind unavailable; skipping retry test")
      is Some(server) else {
      return
    }
    let hits : Ref[Int] = { val: 0, }
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, conn) => {
          let _ = body.read_all()
          hits.val += 1
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          if hits.val > 1 {
            conn.write(
              "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\n",
            )
            conn.write("data: [DONE]\n\n")
          }
        },
        max_connections=8,
      )
    }
    let url = "http://127.0.0.1:\{server.addr.port()}/chat/completions"
    let client = retry_client(url, attempts=3)
    let response = client.chat(
      [ChatMessage(User, content="hello")],
      stream=StreamHandler(on_content_delta=_ => ()),
    )
    assert_eq(response.content, "ok")
    assert_eq(hits.val, 2)
  }
}

///|
/// Once a delta has been delivered, a failure must surface instead of
/// retrying — replaying the stream would hand the consumer duplicate
/// content. The server streams one delta then ends without [DONE] on every
/// request, so a retry (if one wrongly happened) would be observable as a
/// second hit.
async test "streaming chat never retries after the first delta" {
  @async.with_task_group() <| group => {
    guard bind_test_server("local TCP bind unavailable; skipping retry test")
      is Some(server) else {
      return
    }
    let hits : Ref[Int] = { val: 0, }
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, conn) => {
          let _ = body.read_all()
          hits.val += 1
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          conn.write(
            "data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n",
          )
        },
        max_connections=8,
      )
    }
    let url = "http://127.0.0.1:\{server.addr.port()}/chat/completions"
    let client = retry_client(url, attempts=3)
    let deltas : Array[String] = []
    let _ = client.chat(
      [ChatMessage(User, content="hello")],
      stream=StreamHandler(on_content_delta=delta => deltas.push(delta)),
    ) catch {
      error => {
        assert_true("\{error}".contains("ended before [DONE]"))
        assert_eq(deltas.join("|"), "partial")
        assert_eq(hits.val, 1)
        return
      }
    }
    fail("expected truncated stream error")
  }
}

///|
/// Tool-call deltas carry no text, so the content callbacks never fire —
/// but they are model output all the same. A stream that emits only a
/// tool-call delta and then drops must surface the failure rather than
/// retry: a replay could generate (and bill) a different call. (Codex
/// review: the bail flag used to track callback-delivered text only.)
async test "streaming chat never retries after a tool-call-only delta" {
  @async.with_task_group() <| group => {
    guard bind_test_server("local TCP bind unavailable; skipping retry test")
      is Some(server) else {
      return
    }
    let hits : Ref[Int] = { val: 0, }
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (_request, body, conn) => {
          let _ = body.read_all()
          hits.val += 1
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "text/event-stream",
          })
          conn.write(
            "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"function\":{\"name\":\"read\",\"arguments\":\"{}\"}}]}}]}\n\n",
          )
        },
        max_connections=8,
      )
    }
    let url = "http://127.0.0.1:\{server.addr.port()}/chat/completions"
    let client = retry_client(url, attempts=3)
    let _ = client.chat(
      [ChatMessage(User, content="hello")],
      stream=StreamHandler(on_content_delta=_ => ()),
    ) catch {
      error => {
        assert_true("\{error}".contains("ended before [DONE]"))
        assert_eq(hits.val, 1)
        return
      }
    }
    fail("expected truncated stream error")
  }
}
