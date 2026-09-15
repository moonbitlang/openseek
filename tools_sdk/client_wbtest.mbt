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
test "tool errors remain values and absent data stays absent" {
  let result = decode_result({
    "version": 1,
    "content": "invalid edit",
    "is_error": true,
  })
  assert_true(result.is_error)
  assert_eq(result.content, "invalid edit")
  assert_true(result.data is None)
  let result = decode_result({
    "version": 1,
    "content": "ok",
    "is_error": false,
    "data": {
      "sources": [{ "url": "https://example.com" }],
      "truncated": false,
    },
  })
  assert_false(result.is_error)
  assert_true(
    result.data
    is Some({ "sources": [{ "url": "https://example.com", .. }], .. }),
  )
}

///|
test "invalid response envelopes are transport errors" {
  for
    json in [
      ({ "version": 2, "content": "ok", "is_error": false } : Json),
      { "version": 1, "content": "ok", "is_error": "false" },
      { "version": 1, "is_error": false },
    ] {
    let rejected = try {
      ignore(decode_result(json))
      false
    } catch {
      TransportError(_) => true
    }
    assert_true(rejected)
  }
}

///|
async test "HTTP request uses capability and ordinary tool schema" {
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let seen = Ref(false)
    let worker = group.spawn(no_wait=true, () => {
      server.run_forever((req, body, conn) => {
        defer conn.close()
        assert_true(req.meth is Post)
        assert_eq(req.path, "/call")
        assert_eq(
          req.headers.get("Authorization"),
          Some("Bearer test-capability"),
        )
        assert_true(
          @json.parse(body.read_all().text())
          is {
            "version": 1,
            "name": "edit",
            "arguments": { "path": "note.txt", .. },
            ..
          },
        )
        seen.val = true
        conn.send_response(200, "OK")
        conn.write(
          ({ "version": 1, "content": "edited", "is_error": false } : Json),
        )
        conn.end_response()
      })
    })
    defer {
      worker.cancel()
      @async.protect_from_cancel(() => worker.wait() catch { _ => () })
    }
    let result = @async.with_timeout(3000, () => {
      request(
        "http://127.0.0.1:\{server.addr.port()}/call",
        "test-capability",
        "edit",
        { "path": "note.txt" },
      )
    })
    assert_eq(result.content, "edited")
    assert_false(result.is_error)
    assert_true(seen.val)
  })
}

///|
async test "HTTP failures are not retried" {
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let seen = Ref(0)
    let worker = group.spawn(no_wait=true, () => {
      server.run_forever((_, _, conn) => {
        defer conn.close()
        seen.val += 1
        conn.send_response(503, "Unavailable")
        conn.end_response()
      })
    })
    defer {
      worker.cancel()
      @async.protect_from_cancel(() => worker.wait() catch { _ => () })
    }
    let rejected = try {
      ignore(
        request(
          "http://127.0.0.1:\{server.addr.port()}/call",
          "test-capability",
          "edit",
          {},
        ),
      )
      false
    } catch {
      TransportError(_) => true
      error => raise error
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
      server.run_forever((_, _, conn) => {
        defer conn.close()
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
          request(
            "http://127.0.0.1:\{server.addr.port()}/call",
            "test-capability",
            "web_search",
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
