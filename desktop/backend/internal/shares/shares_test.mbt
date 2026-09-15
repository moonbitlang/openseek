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
      for attempt = 0; attempt < 2; attempt = attempt + 1 {
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
        // The API rejects boundaries longer than 70 characters with this
        // error, even when the header includes a boundary parameter.
        assert_true(
          boundary.length() > 0 && boundary.length() <= 70,
          msg="multipart boundary is required: received \{boundary.length()} characters (maximum 70)",
        )
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
          key = request_key
          body = Some(uploaded)
          // Publication may have succeeded even though its response was lost.
          connection.close()
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
    assert_true(
      reply
      is Shared(
        url="http://shares.test/v1/shares/a",
        expires_at="2026-09-22T00:00:00Z"
      ),
    )
    receiver.wait()
  })
}

///|
async test "upload reports authentication server failures malformed responses and redirects without following them" {
  for
    (code, body) in [
      (401, "{}"),
      (404, "{}"),
      (413, "{}"),
      (503, "{}"),
      (302, "{}"),
      (201, "invalid"),
      (201, "{\"url\":\"javascript:bad\",\"expires_at\":\"date\"}"),
    ] {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    @async.with_task_group(group => {
      let receiver = group.spawn(() => {
        let (connection, _) = server.accept()
        defer connection.close()
        let _ = connection.read_request()
        connection.skip_request_body()
        connection.send_response(code, "Fixture", extra_headers={
          "Location": "http://127.0.0.1:1/never-follow",
        })
        connection.write_string(body)
        connection.end_response()
      })
      let snapshot = @shares.Snapshot(
        title="Test",
        html="<html>test</html>",
        json="{}",
      )
      let reply = snapshot.publish(
        server_url="http://127.0.0.1:\{server.addr.port()}",
        token="odt_test",
      )
      if code == 401 {
        assert_true(reply is SignInRequired)
      } else if code == 404 {
        guard reply is Failed(message~) else {
          fail("expected missing share route")
        }
        assert_true(
          message.contains("http://127.0.0.1:\{server.addr.port()}/v1/shares"),
        )
        assert_true(
          message.contains("Sign in to a server with sharing enabled"),
        )
      } else {
        assert_true(reply is Failed(..))
      }
      receiver.wait()
    })
  }
}

///|
async test "upload preserves server error details and falls back for invalid error bodies" {
  for
    (code, body, expected) in [
      (
        400, "{\"error\":\"invalid multipart header\"}", "Sharing failed (HTTP 400): invalid multipart header",
      ),
      (
        403, "{\"error\":\"forbidden origin\"}", "Sharing failed (HTTP 403): forbidden origin",
      ),
      (
        429, "{\"error\":\"daily share quota exceeded\"}", "Sharing failed (HTTP 429): daily share quota exceeded",
      ),
      (
        502, "{\"error\":\"could not save share\"}", "Sharing failed (HTTP 502): could not save share",
      ),
      (400, "<html>proxy error</html>", "Sharing failed (HTTP 400)."),
      (400, "{\"error\":null}", "Sharing failed (HTTP 400)."),
      (400, "{\"error\":\"   \"}", "Sharing failed (HTTP 400)."),
      (
        400,
        "{\"error\":\"\{"😀".repeat(2049)}\"}",
        "Sharing failed (HTTP 400): \{"😀".repeat(2048)}…",
      ),
    ] {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    @async.with_task_group(group => {
      let receiver = group.spawn(() => {
        let (connection, _) = server.accept()
        defer connection.close()
        let _ = connection.read_request()
        connection.skip_request_body()
        connection.send_response(code, "Fixture")
        connection.write_string(body)
        connection.end_response()
      })
      let snapshot = @shares.Snapshot(
        title="Test",
        html="<html>test</html>",
        json="{}",
      )
      let reply = snapshot.publish(
        server_url="http://127.0.0.1:\{server.addr.port()}",
        token="odt_test",
      )
      assert_eq(reply, @protocol.Failed(message=expected))
      receiver.wait()
    })
  }
}

///|
test "upload limits count UTF-8 bytes and multipart overhead" {
  let combined = Ok(
    @shares.Snapshot(
      title="Test",
      html="x".repeat(11 * 1024 * 1024),
      json="x".repeat(10 * 1024 * 1024),
    ),
  ) catch {
    error => Err(error)
  }
  assert_true(combined is Err(_))
  for (title, html) in [("  ", "html"), ("Test", "x".repeat(20 * 1024 * 1024))] {
    let result = Ok(@shares.Snapshot(title~, html~, json="{}")) catch {
      e => Err(e)
    }
    assert_true(result is Err(_))
  }
}

///|
async test "long metadata titles are byte bounded without truncating conversation files" {
  for
    (title, expected) in [
      ("a".repeat(1024), "a".repeat(1024)),
      ("a".repeat(1025), "a".repeat(1024)),
      ("中".repeat(342), "中".repeat(341)),
      ("😀".repeat(257), "😀".repeat(256)),
      ("a".repeat(1023) + "😀", "a".repeat(1023)),
    ] {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let snapshot = @shares.Snapshot(
      title~,
      html="<html>\{title}</html>",
      json="{\"prompt\":\"\{title}\"}",
    )
    @async.with_task_group(group => {
      let receiver = group.spawn(() => {
        let (connection, _) = server.accept()
        defer connection.close()
        let _ = connection.read_request()
        let body = connection.read_all().text()
        assert_true(body.contains("name=\"title\"\r\n\r\n\{expected}\r\n"))
        assert_true(@utf8.encode(expected).length() <= 1024)
        assert_true(body.contains("<html>\{title}</html>"))
        assert_true(body.contains("{\"prompt\":\"\{title}\"}"))
        connection.send_response(201, "Created")
        connection.write_string(
          "{\"url\":\"https://shares.test/test\",\"expires_at\":\"2026-09-22T00:00:00Z\"}",
        )
        connection.end_response()
      })
      let reply = snapshot.publish(
        server_url="http://127.0.0.1:\{server.addr.port()}",
        token="test",
      )
      assert_true(reply is Shared(..))
      receiver.wait()
    })
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
    assert_true(message.has_prefix("Could not connect to the share server:"))
    assert_false(message.contains("may already have been created"))
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
      connection.close()
    })
    let reply = snapshot.publish(server_url=origin, token="test-token")
    guard reply is Failed(message~) else { fail("expected connection failure") }
    assert_true(message.contains("Could not connect to the share server:"))
    assert_false(message.contains("may already have been created"))
    receiver.wait()
  })
}
