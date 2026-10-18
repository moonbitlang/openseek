///|
fn dataset(events? : String) -> String {
  let session = @agent_session.Session(
    SessionId("original"),
    system_prompt="old workspace",
  ).append(User(UserMessage(Content([Text("Hello from imported history")]))))
  let header : @log.SessionFileHeader = {
    id: "original",
    system_prompt: "old workspace",
  }
  let text = StringBuilder()
  text.write_string(ToJson::to_json(header).stringify() + "\n")
  for event in session.events() {
    text.write_string(ToJson::to_json(event).stringify() + "\n")
  }
  let events = events.unwrap_or(text.to_string())
  @viz_export.StandaloneExport("", "").json([
    @viz_export.Session(
      key="session-0",
      id="original",
      root="/original/workspace/.openseek",
      root_label="old",
      is_marker=true,
      last_active=None,
      first_prompt="Imported test",
      events~,
    ),
    @viz_export.Session(
      key="session-1",
      id="original-sr-1",
      root="/original/workspace/.openseek",
      root_label="old",
      is_marker=true,
      last_active=None,
      first_prompt="Child",
      events=events.replace_all(old="original", new="original-sr-1"),
    ),
  ])
}

///|
async test "JSON import prepares independent ordinary sessions and their children" {
  let source : @protocol.SessionImportSource = JsonFile(text=dataset())
  let records = @session_import.prepare(source)
  assert_eq(records.length(), 2)
  assert_eq(records[0].title, "Imported test")
  assert_true(
    records[0].session.id() != @session_import.prepare(source)[0].session.id(),
  )
  assert_eq(records[0].session.system_prompt(), "old workspace")
  assert_eq(records[0].session.last_sequence(), 1)
  assert_eq(
    records[1].session.id().value(),
    records[0].session.id().value() + "-sr-1",
  )
}

///|
async test "invalid JSON and incomplete logs are rejected before writing" {
  for
    text in [
      "not json",
      "{}",
      "[]",
      dataset(events="{\"version\":2,\"id\":\"x\",\"system_prompt\":\"\"}\n"),
      dataset(
        events="{\"version\":1,\"id\":\"x\",\"system_prompt\":\"\"}\n{partial",
      ),
      dataset().replace_all(
        old="original-sr-1",
        new="original-sr-1/../../elsewhere",
      ),
    ] {
    let refused = try {
      ignore(@session_import.prepare(JsonFile(text~)))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
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
            dataset()
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
    let records = @session_import.prepare(source)
    assert_eq(records[0].title, "Imported test")
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
