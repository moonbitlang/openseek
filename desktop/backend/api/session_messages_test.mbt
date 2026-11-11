///|
#cfg(not(platform="windows"))
async test "host MCP offers one session tool per action" {
  home_env_test_lock.acquire()
  defer home_env_test_lock.release()
  let root = @pathx.Path(
    @fs.realpath(@fs.tmpdir(prefix="seekmoon-session-tools-")),
  ).resolve()
  defer @fs.rmdir(root.to_string(), recursive=true)
  let previous = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.to_string())
  defer (match previous {
    Some(value) => @sys.set_env_var("HOME", value)
    None => @sys.unset_env_var("HOME")
  })
  let workspace = root.join("project")
  @fs.mkdir(workspace.to_string())
  ignore(@workspaces.add(workspace.to_string(), _ => ()))
  // `blank` has a record but no saved history.
  for session in ["sender", "target", "blank"] {
    let dir = workspace.join(".openseek/sessions").join(session)
    @fs.mkdir(dir.to_string(), recursive=true)
    let history = if session == "blank" {
      ""
    } else {
      "{\"sequence\":1,\"ts\":0,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"hello\"}}}\n"
    }
    @fs.write_text(
      dir.join("openseek_session-\{session}.jsonl").to_string(),
      "{\"version\":1,\"id\":\"\{session}\",\"system_prompt\":\"\"}\n" + history,
    )
  }
  let server = @mcp.Server([], version="test")
  let state = @api.ApiState(engine="unused", host_mcp=server)
  let approvals : @async.Queue[@protocol.ApprovalSnapshot] = Queue(
    kind=Blocking(16),
  )
  let subscription = state.subscribe(
    approvals,
    map=value => {
      if value is AgentApprovals(snapshot) {
        Some(snapshot)
      } else {
        None
      }
    },
    on_lag=sub => sub.close(),
  )
  defer subscription.close()
  @async.with_task_group(group => {
    state.start_services(group)
    let grant = server.grant("sender")
    let connection = @streamhttp.connect(
      group,
      url=server.url(),
      headers={
        "Authorization": "Bearer " + grant.get(@mcp.TokenEnv).unwrap(),
        "X-SeekMoon-Tool-Groups": "session",
      },
      client_name="test",
      client_version="test",
    )
    defer connection.shutdown()
    let client = connection.client()
    let names = client.list_tools().map(tool => tool.name)
    assert_eq(names, [
      "session_list", "session_read", "session_send", "session_status", "session_cancel",
    ])
    let call = (name : String, arguments : Json) => {
      let result = client.call_tool(name~, arguments~)
      assert_false(result.is_error)
      @json.parse(result.render_text())
    }
    let failed = (name : String, arguments : Json) => {
      client.call_tool(name~, arguments~).is_error
    }

    // session_list pages through flat sessions.
    guard call("session_list", {}) is { "sessions": Array(all), .. } else {
      fail("session_list did not return sessions")
    }
    let ids = all.map(entry => {
      guard entry is { "id": String(id), .. } else { fail("session has no id") }
      id
    })
    assert_true(ids.contains("sender") && ids.contains("target"))
    guard call("session_list", { "limit": 1 })
      is { "sessions": Array(first), "next_offset": Number(next, ..), .. } else {
      fail("a one-entry page must offer the next offset")
    }
    assert_eq(first.length(), 1)
    assert_eq(next, 1.0)
    assert_true(failed("session_list", { "limit": 51 }))

    // session_read returns the saved history of one chat.
    guard call("session_read", { "session": "target" })
      is { "session": { "events": Array(events), .. }, .. } else {
      fail("session_read did not return events")
    }
    assert_eq(events.length(), 1)
    assert_true(failed("session_read", {}))

    // session_send refuses its own chat, a target without history, and
    // incomplete requests before asking the user.
    let request : Json = {
      "target": "target",
      "text": "Exact message",
      "request_id": "req-1",
    }
    assert_true(
      failed("session_send", {
        "target": "sender",
        "text": "Exact message",
        "request_id": "req-0",
      }),
    )
    assert_true(
      failed("session_send", {
        "target": "blank",
        "text": "Exact message",
        "request_id": "req-0",
      }),
    )
    assert_true(
      failed("session_send", { "target": "target", "text": "Exact message" }),
    )
    assert_true(approvals.try_get() is None)

    // A send waits for approval; status reports it pending and cancel
    // withdraws it, which also ends the waiting send.
    group.spawn_bg(() => {
      let snapshot = approvals.get()
      guard snapshot.approvals is [approval] else {
        fail("expected one message approval")
      }
      assert_eq(approval.tool_name, "session.send")
      assert_eq(approval.detail, "target")
      assert_eq(approval.body, Some("Exact message"))
      guard call("session_status", { "id": approval.id })
        is { "status": "pending_approval", .. } else {
        fail("the request must await approval")
      }
      guard call("session_cancel", { "id": approval.id })
        is { "status": "cancelled", .. } else {
        fail("cancel must withdraw the request")
      }
      assert_true(approvals.get().approvals is [])
    })
    guard call("session_send", request) is { "status": "cancelled", .. } else {
      fail("the waiting send must report the withdrawal")
    }
    // Retrying the same request id returns the recorded outcome without
    // asking again.
    guard call("session_send", request)
      is { "status": "cancelled", "id": String(id), .. } else {
      fail("a retry must return the recorded outcome")
    }
    assert_true(approvals.try_get() is None)
    assert_true(failed("session_cancel", { "id": id }))
    assert_true(failed("session_status", { "id": "msg-unknown" }))
    group.return_immediately()
  })
}
