///|
fn export_files(events~ : String = "test") -> @engine.ConversationExport raise {
  @engine.ConversationExport(
    StandaloneExport(
      "<html><script src=\"/viz_app.js\"></script></html>", "globalThis.ready = true;",
    ),
    [
      Session(
        key="session-0",
        id="test",
        root="/workspace",
        root_label="workspace",
        is_marker=true,
        last_active=None,
        first_prompt="Test",
        events~,
      ),
    ],
  )
}

///|
async test "upload authenticates to issuer and retries the exact snapshot after a lost response" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let files = export_files(
    events="a".repeat(4095) + "😀".repeat(4097) + "中\"\\\n</script>",
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
        assert_true(
          request_key is Some(value) &&
          value.length() > 0 &&
          value.length() <= 128 &&
          value
          .iter()
          .all(c => {
            (c >= 'a' && c <= 'z') ||
            (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') ||
            c == '-' ||
            c == '_'
          }),
        )
        guard request.headers.get("Content-Type") is Some(content_type) &&
          content_type.split_once("boundary=") is Some((_, boundary)) else {
          fail("multipart boundary is required")
        }
        // The API rejects boundaries longer than 70 characters.
        assert_true(boundary.length() > 0 && boundary.length() <= 70)
        assert_eq(request_key, Some(boundary.to_owned()))
        let text = @utf8.decode(uploaded)
        assert_true(text.has_prefix("--\{boundary}\r\n"))
        assert_true(text.has_suffix("\r\n--\{boundary}--\r\n"))
        assert_true(text.contains("name=\"title\"\r\n\r\n中文 \"title\"\r\n"))
        assert_true(
          text.contains("name=\"html\"; filename=\"conversation.html\""),
        )
        assert_true(text.contains(files.html))
        assert_true(
          text.contains("name=\"json\"; filename=\"conversation.json\""),
        )
        assert_true(text.contains(files.json))
        assert_true(text.contains("Content-Type: text/html; charset=utf-8\r\n"))
        assert_true(
          text.contains("Content-Type: application/json; charset=utf-8\r\n"),
        )
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
    let progress : Array[@protocol.ShareProgress] = []
    let reply = @shares.publish(
      on_progress=value => progress.push(value),
      title="中文 \"title\"",
      files,
      server_url="http://127.0.0.1:\{server.addr.port()}",
      token="odt_test",
    )
    assert_true(reply is Shared(url="http://shares.test/v1/shares/a"))
    let mut attempt = 0
    let mut percent = -1
    let mut waiting = false
    for value in progress {
      match value {
        Connecting(attempt=next) => {
          assert_eq(next, attempt + 1)
          if attempt > 0 {
            assert_true(waiting)
          }
          attempt = next
          percent = -1
          waiting = false
        }
        Uploading(attempt=actual, percent=next) => {
          assert_eq(actual, attempt)
          assert_true(next > percent && next <= 100)
          assert_false(waiting)
          percent = next
        }
        Waiting(attempt=actual) => {
          assert_eq(actual, attempt)
          assert_eq(percent, 100)
          waiting = true
        }
        Preparing => fail("capture progress belongs to the caller")
      }
    }
    assert_eq(attempt, 2)
    assert_true(waiting)
    receiver.wait()
  })
}

///|
/// Publish a snapshot against a server that answers every request with
/// `code` and `body`, plus a redirect target that must never be followed.
async fn reply_for(
  code : Int32,
  body : String,
  events~ : String = "test",
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
    let reply = @shares.publish(
      title="Test",
      export_files(events~),
      server_url=origin,
      token="odt_test",
    )
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
async test "upload size limits are enforced by the server" {
  let (_, reply) = reply_for(
    413,
    "{\"error\":\"share upload exceeds 20 MiB\"}",
    events="x".repeat(21 * 1024 * 1024),
  )
  assert_eq(
    reply,
    Failed(message="Sharing failed (HTTP 413): share upload exceeds 20 MiB"),
  )
}

///|
async test "a blank title is refused before upload" {
  try
    @shares.publish(
      title="  ",
      export_files(),
      server_url="not-a-url",
      token="test-token",
    )
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
  for server_url in ["not-a-url", origin] {
    let reply = @shares.publish(
      title="Test",
      export_files(),
      server_url~,
      token="test-token",
    )
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
    let reply = @shares.publish(
      title="Test",
      export_files(),
      server_url=origin,
      token="test-token",
    )
    guard reply is Failed(message~) else { fail("expected connection failure") }
    assert_true(message.has_prefix("The share request failed:"))
    receiver.wait()
  })
}

///|
async test "upload timeouts are actionable and external cancellation propagates" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      // The accept loop owns the listener: closing it here, when the group
      // cancels this task, is what lets the loop terminate.
      defer server.close()
      for ;; {
        let (connection, _) = server.accept()
        group.spawn_bg(no_wait=true, () => {
          defer connection.close()
          ignore(connection.read_request())
          connection.skip_request_body()
          @async.sleep(60_000)
        })
      }
    })
    let reply = @shares.publish(
      title="Test",
      export_files(),
      server_url="http://127.0.0.1:\{server.addr.port()}",
      token="test-token",
      timeout_ms=100,
    )
    guard reply is Failed(message~) else { fail("expected upload timeout") }
    assert_true(message.contains("timed out"))
    let cancelled = @async.with_timeout_opt(100, () => {
      @shares.publish(
        title="Test",
        export_files(),
        server_url="http://127.0.0.1:\{server.addr.port()}",
        token="test-token",
      )
    })
    assert_true(cancelled is None)
  })
}

///|
async test "long titles are bounded without truncating streamed conversation files" {
  for
    (title, expected) in [
      ("a".repeat(341), "a".repeat(341)),
      ("a".repeat(1025), "a".repeat(341)),
      ("中".repeat(342), "中".repeat(341)),
      ("😀".repeat(257), "😀".repeat(170)),
      ("a".repeat(340) + "😀", "a".repeat(340)),
    ] {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    let files = export_files(events=title)
    @async.with_task_group(group => {
      let receiver = group.spawn(() => {
        let (connection, _) = server.accept()
        defer connection.close()
        ignore(connection.read_request())
        let body = connection.read_all().text()
        assert_true(body.contains("name=\"title\"\r\n\r\n\{expected}\r\n"))
        assert_true(@utf8.encode(expected).length() <= 1024)
        assert_true(body.contains(files.html))
        assert_true(body.contains(files.json))
        connection.send_response(201, "Created")
        connection.write_string("{\"url\":\"https://shares.test/a\"}")
        connection.end_response()
      })
      let reply = @shares.publish(
        title~,
        files,
        server_url="http://127.0.0.1:\{server.addr.port()}",
        token="test-token",
      )
      assert_true(reply is Shared(..))
      receiver.wait()
    })
  }
}

///|
async test "cancelling a streamed export closes a backpressured connection" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let arrived : @async.Queue[Unit] = Queue(kind=Blocking(1))
  let release : @async.Queue[Unit] = Queue(kind=Blocking(1))
  let files = export_files(events="x".repeat(16 * 1024 * 1024))
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
      @shares.publish(
        title="Test",
        files,
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
