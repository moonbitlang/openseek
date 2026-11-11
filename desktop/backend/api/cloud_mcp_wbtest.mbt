///|
async test "Cloud MCP discovers only client tools without loading Local history" {
  let dir : @pathx.Path = Path(@fs.tmpdir(prefix="seekmoon-cloud-mcp-"))
  defer @fs.rmdir(dir.to_string(), recursive=true)
  @fs.write_text(dir.join("auth.json").to_string(), share_account_fixture())
  let store = @auth.AuthStore::load(runtime_dir=dir)
  let opened : Array[String] = []
  let state = ApiState(engine="must-not-launch", auth=store, cloud_browser=_ => {
    name: "browser_open",
    description: "Test browser",
    input_schema: Json::empty_object(),
    call: call => {
      opened.push(call.session)
      [Text("opened")]
    },
  })
  let catalog = endpoints(state, HostConnection())
  guard catalog.iter().find_first(endpoint => endpoint.name() == "cloud.mcp")
    is Some(endpoint) else {
    fail("missing Cloud MCP endpoint")
  }
  async fn dispatch(session : String, method_ : String, params : Json) -> Json {
    endpoint.invoke(
      @protocol.CloudMcpRequest::Dispatch(account="123", session~, message={
        "jsonrpc": "2.0",
        "id": 1,
        "method": Json(method_),
        "params": params,
      }).to_json(),
    )
  }
  assert_true(
    dispatch("cloud-a", "initialize", {})
    is { "result": { "serverInfo": { "name": "seekmoon", .. }, .. }, .. },
  )
  assert_true(
    dispatch("cloud-a", "tools/list", {})
    is {
      "result": {
        "tools": [
          { "name": "browser_open", .. },
          { "name": "preview_open", .. },
          { "name": "ask_user", .. },
        ],
        ..
      },
      ..
    },
  )
  let _ = dispatch("cloud-b", "tools/call", {
    "name": "browser_open",
    "arguments": { "url": "https://example.test/" },
  })
  assert_eq(opened, ["cloud-b"])
  let previews : @async.Queue[@protocol.PreviewOpenRequest] = Queue(
    kind=Blocking(8),
  )
  let preview_subscription = state.subscribe(
    previews,
    map=event => {
      match event {
        PreviewOpen(request) => Some(request)
        _ => None
      }
    },
    on_lag=sub => sub.close(),
  )
  defer preview_subscription.close()
  for
    path in [
      "index.html", "report.pdf", "image.png", "report.docx", "src/main.mbt", "notes.txt",
    ] {
    let result = dispatch("cloud-b", "tools/call", {
      "name": "preview_open",
      "arguments": {
        "path": Json(path),
        "session": "wrong-session",
        "workspace": "/wrong-workspace",
      },
    })
    guard result
      is {
        "result": {
          "isError": false,
          "content": [{ "text": String(text), .. }],
          ..
        },
        ..
      } else {
      fail("preview request was not accepted")
    }
    assert_true(@json.parse(text) is { "status": "opening", .. })
    assert_eq(
      previews.try_get(),
      Some(Cloud(account="123", session="cloud-b", path~)),
    )
  }

  assert_true(
    dispatch("cloud-a", "tools/call", { "name": "browser_navigate" })
    is { "error": { "code": -32602, .. }, .. },
  )
  @async.with_task_group(group => {
    let waiting = group.spawn(() => {
      dispatch("cloud-a", "tools/call", {
        "name": "ask_user",
        "arguments": { "questions": [{ "id": "plan", "title": "Which plan?" }] },
      })
    })
    let client = state.cloud_mcp_client("123")
    // Let the tool register its question before answering from another UI.
    while client.questions.snapshot().requests.is_empty() {
      @async.sleep(1)
    }
    let pending = client.questions.snapshot().requests[0]
    assert_eq(pending.session, "cloud-a")
    let snapshot : @protocol.UserQuestionSnapshot = @json.from_json(
      endpoint.invoke(
        @protocol.CloudMcpRequest::Answer(account="123", answer={
          id: pending.id,
          session: "cloud-a",
          answers: Some({ "plan": "A" }),
        }).to_json(),
      ),
    )
    assert_true(snapshot.requests.is_empty())
    guard waiting.wait()
      is {
        "result": {
          "content": [{ "text": String(text), .. }],
          "isError": false,
          ..
        },
        ..
      } else {
      fail("missing ask-user result")
    }
    assert_true(
      @json.parse(text)
      is { "status": "answered", "answers": { "plan": "A", .. }, .. },
    )
    assert_true(client.questions.take_inputs().is_empty())
  })
  let events : @async.Queue[@protocol.Notification] = Queue(kind=Blocking(16))
  let subscription = state.subscribe(events, map=event => Some(event), on_lag=sub => {
    sub.close()
  })
  defer subscription.close()
  @async.with_task_group(group => {
    let waiting = group.spawn(() => {
      dispatch("cloud-a", "tools/call", {
        "name": "ask_user",
        "arguments": {
          "questions": [{ "id": "plan", "title": "Answer after reconnect" }],
        },
      })
    })
    let client = state.cloud_mcp_client("123")
    while client.questions.snapshot().requests.is_empty() {
      @async.sleep(1)
    }
    let pending = client.questions.snapshot().requests[0]
    state.detach_cloud_questions()
    let _ = endpoint.invoke(
      @protocol.CloudMcpRequest::Detach(account="123", session="cloud-a").to_json(),
    )
    guard waiting.wait()
      is { "result": { "content": [{ "text": String(text), .. }], .. }, .. } else {
      fail("missing detached result")
    }
    assert_true(@json.parse(text) is { "status": "pending", .. })
    let _ = endpoint.invoke(
      @protocol.CloudMcpRequest::Answer(account="123", answer={
        id: pending.id,
        session: "cloud-a",
        answers: Some({ "plan": "Delayed answer" }),
      }).to_json(),
    )
    let inputs : Array[(String, String)] = []
    while events.try_get() is Some(event) {
      if event is CloudMcp(Input(account="123", session~, text~, ..)) {
        inputs.push((session, text))
      }
    }
    assert_eq(inputs.length(), 1)
    assert_eq(inputs[0].0, "cloud-a")
    assert_true(inputs[0].1.contains("Delayed answer"))
    assert_true(client.questions.take_inputs().is_empty())
  })
  assert_true(state.questions.snapshot().requests.is_empty())
  let stale = try {
    let _ = state.cloud_mcp(Questions(account="other"))
    false
  } catch {
    _ => true
  }
  assert_true(stale)
  // Retiring the native account also fences the already-created dispatcher.
  store.expire_account("ts_current")
  let retired = try {
    let _ = state.cloud_mcp(Questions(account="123"))
    false
  } catch {
    _ => true
  }
  assert_true(retired)
}
