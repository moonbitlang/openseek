///|
#cfg(not(platform="windows"))
async test "feedback uploads both persisted exports or reports the missing transcript" {
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
  let state = ApiState(engine="unused", resources~)
  let payload : @protocol.SessionFeedbackPayload = {
    user_id: "123",
    source: {
      session: "session-1",
      workspace: workspace.resource_path(),
      title: "Review",
      archived: false,
    },
    metadata: {
      message: "  界面闪烁\nagain  ",
      environment: { "client": "desktop" },
    },
  }
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let origin = "http://127.0.0.1:\{server.addr.port}"
  for attached in [true, false] {
    if !attached {
      @fs.remove(viz.join("viz_app.js").to_string())
    }
    @async.with_task_group(group => {
      let receiver = group.spawn(() => {
        let (connection, _) = server.accept()
        defer connection.close()
        let request = connection.read_request()
        assert_true(request.meth is Post)
        assert_eq(request.path, "/v1/feedback")
        assert_eq(
          request.headers.get("Authorization"),
          Some("Bearer test-account"),
        )
        let boundary = request.headers
          .get("Content-Type")
          .unwrap()
          .split_once("boundary=")
          .unwrap().1
        let parts = @utf8.decode(connection.read_all())
          .split("--" + boundary.to_owned())
          .to_array()
        assert_eq(parts.length(), if attached { 5 } else { 3 })
        let metadata = @json.parse(parts[1].split_once("\r\n\r\n").unwrap().1)
        assert_true(
          metadata
          is {
            "message": String(message),
            "environment": { "client": "desktop", .. },
            "source": { "mode": "local", "session_id": "session-1", .. },
            ..
          } &&
          message == payload.metadata.message,
        )
        if attached {
          assert_false(metadata is { "transcript_error": _, .. })
          let expected = @engine.ConversationExport::capture(
            state.manager(),
            payload.source,
            "<html><script src=\"/viz_app.js\"></script></html>",
            "/* bundled visualizer */",
          )
          for
            (index, name, content) in [
              (2, "html", expected.html),
              (3, "json", expected.json),
            ] {
            let (headers, body) = parts[index].split_once("\r\n\r\n").unwrap()
            assert_true(
              headers.contains(
                "name=\"\{name}\"; filename=\"transcript.\{name}\"",
              ),
            )
            assert_eq(body.strip_suffix("\r\n").unwrap().to_owned(), content)
            for turn in 1..<=80 {
              assert_true(body.contains("Persisted question (\{turn})"))
            }
          }
        } else {
          assert_true(
            metadata is { "transcript_error": String(reason), .. } &&
            reason.contains("visualizer"),
          )
        }
        connection.send_response(201, "Created")
        connection.write_string("{\"id\":\"fb_test\"}")
        connection.end_response()
      })
      let receipt = state.submit_feedback(
        payload,
        origin~,
        token="test-account",
      )
      receiver.wait()
      assert_eq(receipt.id, "fb_test")
      assert_eq(receipt.transcript_error is None, attached)
    })
  }
}

///|
async test "feedback only uses the matching local account" {
  let dir : @pathx.Path = Path(@fs.tmpdir(prefix="seekmoon-feedback-account-"))
  defer @fs.remove(dir.to_string(), recursive=true)
  @fs.write_text(dir.join("auth.json").to_string(), share_account_fixture())
  let state = ApiState(
    engine="unused",
    auth=@auth.AuthStore::load(runtime_dir=dir),
  )
  assert_false(
    endpoints(state, HostConnection()).any(endpoint => {
      endpoint.name() == "session.feedback"
    }),
  )
  let endpoint = endpoints(state, HostConnection(), local_feedback=true)
    .iter()
    .find_first(endpoint => endpoint.name() == "session.feedback")
    .unwrap()
  let request : @protocol.SessionFeedbackPayload = {
    user_id: "different-account",
    source: { session: "test", title: "Test", workspace: ".", archived: false, },
    metadata: { message: "Hello", environment: {}, },
  }
  let result : Result[@protocol.FeedbackReceipt, String] = @json.from_json(
    endpoint.invoke(ToJson::to_json(request)),
  )
  assert_true(result is Err(reason) && reason.contains("same account"))
}
