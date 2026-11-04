///|
test "missing malformed and incompatible capabilities fail before I/O" {
  for
    raw in [
      None,
      Some("not JSON"),
      Some("{}"),
      Some("{\"version\":2,\"url\":\"http://localhost\",\"token\":\"secret\"}"),
    ] {
    let rejected = try {
      ignore(decode_handoff(raw))
      false
    } catch {
      TransportError(_) => true
    }
    assert_true(rejected)
  }
}

///|
test "tool errors remain values, absent data stays absent, images decode in order" {
  let result = decode_reply({
    "version": 1,
    "content": "invalid",
    "is_error": true,
  })
  assert_true(result.is_error)
  assert_eq(result.content, "invalid")
  assert_true(result.data is None)
  assert_eq(result.images, [])
  let result = decode_reply({
    "version": 1,
    "content": "shot",
    "is_error": false,
    "data": { "ok": true },
    "images": ["/tmp/a.png", "/tmp/b.png"],
  })
  assert_false(result.is_error)
  assert_true(result.data is Some({ "ok": true, .. }))
  assert_eq(result.images, ["/tmp/a.png", "/tmp/b.png"])
}

///|
test "invalid response envelopes are transport errors" {
  for
    json in [
      ({ "version": 2, "content": "ok", "is_error": false } : Json),
      { "version": 1, "content": "ok", "is_error": "false" },
      { "version": 1, "is_error": false },
      { "version": 1, "content": "ok", "is_error": false, "images": "a.png" },
      { "version": 1, "content": "ok", "is_error": false, "images": [1] },
    ] {
    let rejected = try {
      ignore(decode_reply(json))
      false
    } catch {
      TransportError(_) => true
    }
    assert_true(rejected, msg=json.stringify())
  }
}

///|
async test "HTTP failures are not retried" {
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let seen = Ref(0)
    let worker = group.spawn(no_wait=true, () => {
      server.run_forever((_, conn) => {
        defer conn.close()
        seen.val += 1
        conn.send_response(503, "Unavailable")
        conn.text.write("not JSON")
        conn.end_response()
      })
    })
    defer {
      worker.cancel()
      @async.protect_from_cancel(() => worker.wait() catch { _ => () })
    }
    let rejected = try {
      ignore(
        post("http://127.0.0.1:\{server.addr.port()}/call", "test-capability", {}),
      )
      false
    } catch {
      TransportError(message) => {
        assert_true(message.contains("HTTP 503"), msg=message)
        true
      }
    }
    assert_true(rejected)
    assert_eq(seen.val, 1)
  })
}

///|
async test "caller cancellation is not converted to a transport failure" {
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let worker = group.spawn(no_wait=true, () => {
      server.run_forever((_, conn) => {
        defer conn.close()
        conn.send_response(200, "OK")
        conn.text.write("{")
        conn.flush()
        @async.sleep(60000)
      })
    })
    defer {
      worker.cancel()
      @async.protect_from_cancel(() => worker.wait() catch { _ => () })
    }
    let timed_out = try {
      ignore(
        @async.with_timeout(50, () => {
          post(
            "http://127.0.0.1:\{server.addr.port()}/call",
            "test-capability",
            {},
          )
        }),
      )
      false
    } catch {
      @async.TimeoutError => true
      error => raise error
    }
    assert_true(timed_out)
  })
}

///|
test "request shapes match the MCP host's v1 wire" {
  assert_eq(
    encode(
      Call(server="github", tool="search_issues", arguments={ "q": "bug" }),
    ),
    {
      "version": 1,
      "call": {
        "server": "github",
        "tool": "search_issues",
        "arguments": { "q": "bug" },
      },
    },
  )
  assert_eq(encode(List(cursor=None)), { "version": 1, "list": {} })
  assert_eq(encode(List(cursor=Some(12))), {
    "version": 1,
    "list": { "cursor": 12 },
  })
}
