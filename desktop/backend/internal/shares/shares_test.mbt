///|
async test "upload authenticates to issuer and retries the exact snapshot after a lost response" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let snapshot = @shares.Snapshot(
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
        assert_eq(request.path, "/v1/shares")
        assert_eq(request.headers.get("Authorization"), Some("Bearer odt_test"))
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
    let reply = snapshot.publish(
      server_url="http://127.0.0.1:\{server.addr.port()}",
      token="odt_test",
    )
    assert_true(reply is Shared(url="http://shares.test/v1/shares/a"))
    receiver.wait()
  })
}

///|
/// Publish a small snapshot against a server that answers every request with
/// `code` and `body`, plus a redirect target that must never be followed.
async fn reply_for(
  code : Int,
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
      title="Test",
      html="<html>test</html>",
      json="{}",
    ).publish(server_url=origin, token="odt_test")
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
      message="The signed-in server does not provide sharing at \{origin}/v1/shares (HTTP 404). Sign in to a server with sharing enabled.",
    ),
  )
}

///|
test "upload limits count UTF-8 bytes and multipart overhead" {
  try
    @shares.Snapshot(
      title="Test",
      html="x".repeat(11 * 1024 * 1024),
      json="x".repeat(10 * 1024 * 1024),
    )
  catch {
    Oversized => ()
    error => raise error
  } noraise {
    _ => fail("files that only together exceed the limit must be refused")
  }
  try
    @shares.Snapshot(title="Test", html="x".repeat(20 * 1024 * 1024), json="{}")
  catch {
    Oversized => ()
    error => raise error
  } noraise {
    _ => fail("multipart framing must count toward the limit")
  }
  try @shares.Snapshot(title="  ", html="html", json="{}") catch {
    EmptyTitle => ()
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
  let snapshot = @shares.Snapshot(title="Test", html="<html/>", json="{}")
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
  let snapshot = @shares.Snapshot(title="Test", html="<html/>", json="{}")
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
