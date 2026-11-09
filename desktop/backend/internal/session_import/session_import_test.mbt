///|
async test "JSON files are passed through unchanged within the size limit" {
  let text = "{\"exported\":true}"
  assert_eq(@session_import.prepare(JsonFile(text~)), text)
  let oversized = String::make(16 * 1024 * 1024 + 1, 'x')
  let message = try {
    ignore(@session_import.prepare(JsonFile(text=oversized)))
    ""
  } catch {
    @session_import.SessionImportError(message) => message
    error => raise error
  }
  assert_true(message.contains("16 MiB"))
}

///|
test "OpenSeek share links resolve only to the public JSON resource" {
  for suffix in ["", "/", "/preview", "/files/json", "?utm_source=test#preview"] {
    assert_eq(
      @session_import.share_json_url(
        "https://shares.example/v1/shares/sh_test" + suffix,
      ),
      "https://shares.example/v1/shares/sh_test/files/json",
    )
  }
  for
    url in [
      "file:///tmp/test", "https://user:password@example/v1/shares/sh_x", "https://example/v1/shares/../config",
      "https://example/v1/shares/sh_x/files/html", "https://example/other", "https://example/v1/shares/sh_x%2F..",
    ] {
    let refused = try {
      ignore(@session_import.share_json_url(url))
      false
    } catch {
      @session_import.SessionImportError(_) => true
      error => raise error
    }
    assert_true(refused)
  }
}

///|
async test "share download is anonymous and expiry leaves no imported record" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_task_group(group => {
    let receiver = group.spawn(() => {
      for code in [200, 410, 302] {
        let (connection, _) = server.accept()
        defer connection.close()
        let request = connection.read_request()
        assert_eq(request.path, "/v1/shares/sh_test/files/json")
        assert_true(request.headers.get("Authorization") is None)
        assert_true(request.headers.get("Cookie") is None)
        connection.send_response(code, "Test")
        connection.write_string(
          if code == 200 {
            "{\"exported\":true}"
          } else {
            "unavailable"
          },
        )
        connection.end_response()
      }
    })
    let source : @protocol.SessionImportSource = ShareLink(
      url="http://127.0.0.1:\{server.addr.port()}/v1/shares/sh_test",
    )
    assert_eq(@session_import.prepare(source), "{\"exported\":true}")
    for expected in ["expired", "HTTP 302"] {
      let message = try {
        ignore(@session_import.prepare(source))
        ""
      } catch {
        @session_import.SessionImportError(message) => message
        error => raise error
      }
      assert_true(message.contains(expected))
    }
    receiver.wait()
  })
}
