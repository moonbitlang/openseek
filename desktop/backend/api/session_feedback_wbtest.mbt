///|
#cfg(not(platform="windows"))
async test "feedback uploads metadata and both complete files from one conversation snapshot" {
  let root = @pathx.Path(@fs.realpath(@fs.tmpdir(prefix="seekmoon-feedback-"))).resolve()
  defer @fs.remove(root.to_string(), recursive=true)
  let previous = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.to_string())
  defer (match previous {
    Some(value) => @sys.set_env_var("HOME", value)
    None => @sys.unset_env_var("HOME")
  })
  let workspace = root.join("project")
  @fs.mkdir(workspace.to_string())
  ignore(@workspaces.add(workspace.to_string(), _ => ()))
  let record_dir = @workspaces.store_root(workspace).join("sessions/session-1")
  @fs.mkdir(record_dir.to_string(), recursive=true)
  let records = StringBuilder()
  records.write_string(
    "{\"version\":1,\"id\":\"session-1\",\"system_prompt\":\"System\"}\n",
  )
  for turn in 1..<=80 {
    let event : Json = {
      "sequence": turn,
      "ts": turn,
      "item": {
        "kind": "user",
        "payload": { "content": "Persisted question (\{turn})" },
      },
    }
    records.write_string(event.stringify() + "\n")
  }
  @fs.write_text(
    record_dir.join("openseek_session-session-1.jsonl").to_string(),
    records.to_string(),
  )
  let resources = @host.desktop_resources({
    dir: root.to_path(),
    packaged: true,
  })
  let viz = root.join("seekmoon/web/viz")
  @fs.mkdir(viz.to_string(), recursive=true)
  @fs.write_text(
    viz.join("index.html").to_string(),
    "<html><script src=\"/viz_app.js\"></script></html>",
  )
  @fs.write_text(viz.join("viz_app.js").to_string(), "/* bundled visualizer */")
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let origin = "http://127.0.0.1:\{server.addr.port}"
  @fs.write_text(root.join("auth.json").to_string(), share_account_fixture())
  let state = ApiState(
    engine="unused",
    resources~,
    auth=@auth.AuthStore::load(runtime_dir=root.to_path()),
  )
  let metadata : @protocol.FeedbackMetadata = {
    message: "  界面闪烁\nagain  ",
    environment: { "client": "desktop" },
  }
  let payload : @protocol.SessionFeedbackPayload = {
    metadata,
    idempotency_key: "f".repeat(64),
    user_id: "123",
    source: {
      session: "session-1",
      workspace: workspace.resource_path(),
      title: "Review",
      archived: false,
    },
  }
  let account = state.auth_store().account().unwrap()
  let mismatch = state.submit_feedback({
    ..payload,
    user_id: "another-account",
  })
  assert_true(
    mismatch is Failed(message~) && message.contains("Sign-in changed"),
  )
  @async.with_task_group(group => {
    let receiver = group.spawn(() => {
      let (connection, _) = server.accept()
      defer connection.close()
      let request = connection.read_request()
      assert_true(request.meth is Post)
      assert_eq(request.path, "/v1/feedback")
      assert_eq(request.headers.get("Authorization"), Some("Bearer ts_current"))
      let boundary = request.headers
        .get("Content-Type")
        .unwrap()
        .split_once("boundary=")
        .unwrap().1
      let parts = @utf8.decode(connection.read_all())
        .split("--" + boundary.to_owned())
        .to_array()
      assert_eq(
        request.headers.get("Idempotency-Key"),
        Some(payload.idempotency_key),
      )
      assert_eq(parts.length(), 6)
      assert_true(parts[1].contains("name=\"title\""))
      assert_eq(
        parts[1].split_once("\r\n\r\n").unwrap().1.trim().to_owned(),
        payload.source.title,
      )
      assert_true(parts[4].contains("name=\"metadata\""))
      let record = @json.parse(parts[4].split_once("\r\n\r\n").unwrap().1)
      assert_true(
        record
        is {
          "message": String(message),
          "environment": { "client": "desktop", .. },
          "source": { "mode": "local", "session_id": "session-1", .. },
          ..
        } &&
        message == metadata.message,
      )
      let expected = @engine.ConversationExport::capture(
        state.manager(),
        payload.source,
        "<html><script src=\"/viz_app.js\"></script></html>",
        "/* bundled visualizer */",
      )
      for
        (index, name, mime, content) in [
          (2, "html", "text/html", expected.html),
          (3, "json", "application/json", expected.json),
        ] {
        let (headers, body) = parts[index].split_once("\r\n\r\n").unwrap()
        assert_true(
          headers.contains(
            "name=\"\{name}\"; filename=\"conversation.\{name}\"",
          ),
        )
        assert_true(headers.contains(mime))
        assert_eq(body.strip_suffix("\r\n").unwrap().to_owned(), content)
        for turn in 1..<=80 {
          assert_true(body.contains("Persisted question (\{turn})"))
        }
      }
      connection.send_response(201, "Created")
      connection.write_string("{\"id\":\"fb_test\"}")
      connection.end_response()
    })
    let reply = state.publish_feedback(payload, account, server_url=origin)
    receiver.wait()
    assert_true(reply is Submitted(id="fb_test"))
  })
  let oversized = state.publish_feedback(
    {
      ..payload,
      metadata: { ..metadata, message: "x".repeat(20 * 1024 * 1024), },
    },
    account,
    server_url=origin,
  )
  assert_true(
    oversized
    is Failed(message="This feedback exceeds the 20 MiB upload limit."),
  )
  for
    (code, body, expected) in (
      [
        (
          200,
          "{\"id\":\"fb_test\"}",
          Failed(message="Feedback failed (HTTP 200)."),
        ),
        (
          201,
          "{\"url\":\"https://shares.test/f\"}",
          Failed(message="Invalid feedback receipt."),
        ),
        (401, "{}", SignInRequired),
      ] : Array[(Int32, String, @protocol.SessionFeedbackReply)]) {
    @async.with_task_group(group => {
      let receiver = group.spawn(() => {
        let (connection, _) = server.accept()
        defer connection.close()
        ignore(connection.read_request())
        connection.skip_request_body()
        connection.send_response(code, "Fixture")
        connection.write_string(body)
        connection.end_response()
      })
      assert_eq(
        state.publish_feedback(payload, account, server_url=origin),
        expected,
      )
      receiver.wait()
    })
  }
  assert_false(state.auth_store().signed_in())
  assert_true(state.submit_feedback(payload) is SignInRequired)
}
