///|
async test "upload authenticates to issuer and retries the exact snapshot after a lost response" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let snapshot = @shares.Snapshot(
    key="a".repeat(64),
    title="中文 \"title\"",
    html="<html>snapshot</html>",
    json="{\"snapshot\":true}",
  )
  @async.with_task_group(group => {
    let receiver = group.spawn(() => {
      let mut key : String? = None
      let mut body : Bytes? = None
      for attempt in 0..<2 {
        let (connection, _) = server.accept()
        defer connection.close()
        let request = connection.read_request()
        let uploaded = connection.read_all().binary()
        assert_true(request.meth is Post)
        assert_eq(request.path, "/v2/shares")
        assert_eq(request.headers.get("Authorization"), Some("Bearer ts_test"))
        let request_key = request.headers.get("Idempotency-Key")
        assert_true(request_key is Some(value) && value.length() == 64)
        guard request.headers.get("Content-Type") is Some(content_type) &&
          content_type.split_once("boundary=") is Some((_, boundary)) else {
          fail("multipart boundary is required")
        }
        // The API rejects boundaries longer than 70 characters.
        assert_true(boundary.length() > 0 && boundary.length() <= 70)
        let text = @utf8.decode(uploaded)
        assert_true(text.has_prefix("--\{boundary}\r\n"))
        assert_true(text.has_suffix("\r\n--\{boundary}--\r\n"))
        assert_true(text.contains("name=\"title\"\r\n\r\n中文 \"title\"\r\n"))
        assert_true(
          text.contains("name=\"html\"; filename=\"conversation.html\""),
        )
        assert_true(text.contains("<html>snapshot</html>"))
        assert_true(
          text.contains("name=\"json\"; filename=\"conversation.json\""),
        )
        assert_true(text.contains("{\"snapshot\":true}"))
        if attempt == 0 {
          // Drop the connection without a response: publication may have
          // succeeded even though the client never learns it.
          key = request_key
          body = Some(uploaded)
        } else {
          assert_true(request_key == key)
          assert_true(Some(uploaded) == body)
          connection.send_response(200, "OK")
          connection.write_string(
            "{\"url\":\"http://shares.test/v1/shares/a\",\"expires_at\":\"2026-09-22T00:00:00Z\"}",
          )
          connection.end_response()
        }
      }
    })
    let phases : Array[@protocol.ShareProgress] = []
    let reply = snapshot.publish(
      server_url="http://127.0.0.1:\{server.addr.port()}",
      token="ts_test",
      on_progress=phase => phases.push(phase),
    )
    assert_eq(phases, [
      Connecting(attempt=1),
      Uploading(attempt=1),
      Waiting(attempt=1),
      Connecting(attempt=2),
      Uploading(attempt=2),
      Waiting(attempt=2),
    ])
    assert_true(reply is Shared(url="http://shares.test/v1/shares/a"))
    receiver.wait()
  })
}

///|
/// Publish a small snapshot against a server that answers every request with
/// `code` and `body`, plus a redirect target that must never be followed.
async fn reply_for(
  code : Int32,
  body : String,
) -> (String, @protocol.SessionShareReply) {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let origin = "http://127.0.0.1:\{server.addr.port()}"
  @async.with_task_group(group => {
    let receiver = group.spawn(() => {
      let (connection, _) = server.accept()
      defer connection.close()
      ignore(connection.read_request())
      connection.skip_request_body()
      connection.send_response(code, "Fixture", extra_headers={
        "Location": "http://127.0.0.1:1/never-follow",
      })
      connection.write_string(body)
      connection.end_response()
    })
    let reply = @shares.Snapshot(
      key="a".repeat(64),
      title="Test",
      html="<html>test</html>",
      json="{}",
    ).publish(server_url=origin, token="ts_test")
    receiver.wait()
    (origin, reply)
  })
}

///|
async test "upload maps server replies without following redirects" {
  let invalid = "The share server did not return a valid share link."
  for
    (code, body, expected) in [
      (401, "{}", @protocol.SignInRequired),
      (413, "{}", Failed(message="Sharing failed (HTTP 413).")),
      (302, "{}", Failed(message="Sharing failed (HTTP 302).")),
      (201, "invalid", Failed(message=invalid)),
      (201, "{\"expires_at\":\"date\"}", Failed(message=invalid)),
      (
        400,
        "{\"error\":\"invalid multipart header\"}",
        Failed(message="Sharing failed (HTTP 400): invalid multipart header"),
      ),
      (
        400,
        "<html>proxy error</html>",
        Failed(message="Sharing failed (HTTP 400)."),
      ),
      (400, "{\"error\":null}", Failed(message="Sharing failed (HTTP 400).")),
      (400, "{\"error\":\"   \"}", Failed(message="Sharing failed (HTTP 400).")),
    ] {
    let (_, reply) = reply_for(code, body)
    assert_eq(reply, expected)
  }
  // A device login can still point at a deployment without share routes.
  let (origin, reply) = reply_for(404, "{}")
  assert_eq(
    reply,
    Failed(
      message="The signed-in server does not provide sharing at \{origin}/v2/shares (HTTP 404). Sign in to a server with sharing enabled.",
    ),
  )
}

///|
test "upload limits count UTF-8 bytes and multipart overhead" {
  try
    @shares.Snapshot(
      key="a".repeat(64),
      title="Test",
      html="x".repeat(11 * 1024 * 1024),
      json="x".repeat(10 * 1024 * 1024),
    )
  catch {
    @shares.Oversized => ()
    error => raise error
  } noraise {
    _ => fail("files that only together exceed the limit must be refused")
  }
  try
    @shares.Snapshot(
      key="a".repeat(64),
      title="Test",
      html="x".repeat(20 * 1024 * 1024),
      json="{}",
    )
  catch {
    @shares.Oversized => ()
    error => raise error
  } noraise {
    _ => fail("multipart framing must count toward the limit")
  }
  try
    @shares.Snapshot(key="a".repeat(64), title="  ", html="html", json="{}")
  catch {
    @shares.EmptyTitle => ()
    error => raise error
  } noraise {
    _ => fail("a blank title must be refused")
  }
}

///|
async test "setup and refused connections retain definite failures" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let origin = "http://127.0.0.1:\{server.addr.port()}"
  server.close()
  let snapshot = @shares.Snapshot(
    key="a".repeat(64),
    title="Test",
    html="<html/>",
    json="{}",
  )
  for server_url in ["not-a-url", origin] {
    let reply = snapshot.publish(server_url~, token="test-token")
    guard reply is Failed(message~) else { fail("expected connection failure") }
    assert_true(message.has_prefix("The share request failed:"))
    assert_false(message.contains("test-token"))
  }
}

///|
async test "a lost response followed by a refused retry reports the connection failure" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let origin = "http://127.0.0.1:\{server.addr.port()}"
  let snapshot = @shares.Snapshot(
    key="a".repeat(64),
    title="Test",
    html="<html/>",
    json="{}",
  )
  @async.with_task_group(group => {
    let receiver = group.spawn(() => {
      let (connection, _) = server.accept()
      defer connection.close()
      ignore(connection.read_request())
      connection.skip_request_body()
      // The upload reached the server. Close the listener before dropping the
      // response so the retry fails definitively, without resolving attempt one.
      server.close()
    })
    let reply = snapshot.publish(server_url=origin, token="test-token")
    guard reply is Failed(message~) else { fail("expected connection failure") }
    assert_true(message.has_prefix("The share request failed:"))
    receiver.wait()
  })
}

///|
async test "cancelling a streamed export closes a backpressured connection" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let arrived : @async.Queue[Unit] = Queue(kind=Blocking(1))
  let release : @async.Queue[Unit] = Queue(kind=Blocking(1))
  let snapshot = @shares.Snapshot(
    key="a".repeat(64),
    title="Test",
    html="x".repeat(16 * 1024 * 1024),
    json="{}",
  )
  @async.with_task_group(group => {
    let receiver = group.spawn(() => {
      let (connection, _) = server.accept()
      defer connection.close()
      let request = connection.read_request()
      assert_eq(request.headers.get("Transfer-Encoding"), Some("chunked"))
      ignore(connection.read_exactly(1024))
      arrived.put(())
      release.get()
      // A cancelled chunked request has no final chunk. Draining must fail
      // when the client closes its connection rather than hang indefinitely.
      try connection.skip_request_body() catch {
        _ => ()
      } noraise {
        _ => fail("cancelled upload unexpectedly completed")
      }
    })
    let sender = group.spawn(() => {
      snapshot.publish(
        server_url="http://127.0.0.1:\{server.addr.port()}",
        token="test-token",
      )
    })
    arrived.get()
    @async.sleep(50)
    sender.cancel()
    try sender.wait() catch {
      @async.WaitedTaskAlreadyCancelled => ()
      error => raise error
    } noraise {
      _ => fail("upload should be cancelled")
    }
    release.put(())
    @async.with_timeout(5000, () => receiver.wait())
  })
}
