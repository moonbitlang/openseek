///|
#cfg(not(platform="windows"))
async test "host MCP attaches only to its caller and preserves concurrent artifacts" {
  let root = @pathx.Path(
    @fs.realpath(@fs.tmpdir(prefix="seekmoon-pr-artifacts-")),
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
  for session in ["one", "two"] {
    let dir = workspace.join(".openseek/sessions").join(session)
    @fs.mkdir(dir.to_string(), recursive=true)
    @fs.write_file(
      dir.join("openseek_session-\{session}.jsonl").to_string(),
      "{\"version\":1,\"id\":\"\{session}\",\"system_prompt\":\"\"}\n",
    )
  }
  let server = @mcp.Server([], version="test")
  let state = @api.ApiState(engine="unused", host_mcp=server)
  let notifications : @async.Queue[@protocol.Notification] = Queue(
    kind=Blocking(16),
  )
  let subscription = state.subscribe(
    notifications,
    map=value => {
      if value is SessionArtifactsChanged(_) {
        Some(value)
      } else {
        None
      }
    },
    on_lag=sub => sub.close(),
  )
  defer subscription.close()
  @async.with_task_group(group => {
    state.start_services(group)
    let grant = server.grant("one")
    let connection = @streamhttp.connect(
      group,
      url=server.url(),
      headers={ "Authorization": "Bearer " + grant.get(@mcp.TokenEnv).unwrap() },
      client_name="test",
      client_version="test",
    )
    defer connection.shutdown()
    let client = connection.client()
    let first : Json = {
      "type": "pull_request",
      "url": "https://github.com/o/r/pull/1",
    }
    let branch : Json = {
      "type": "branch",
      "url": "https://github.com/o/r/tree/topic",
    }
    let second : Json = {
      "type": "pull_request",
      "url": "https://github.com/o/r/pull/2",
    }
    assert_false(
      client.call_tool(name="artifacts_attach", arguments=first).is_error,
    )
    // Repeating attach is idempotent; it never replaces earlier artifacts.
    assert_false(
      client.call_tool(name="artifacts_attach", arguments=first).is_error,
    )
    assert_false(
      client.call_tool(name="artifacts_attach", arguments=branch).is_error,
    )
    let snapshot = @engine.session_artifacts_list(state.manager(), "one")
    assert_eq(snapshot.artifacts.length(), 2)
    assert_eq(
      @engine.session_artifacts_list(state.manager(), "two").artifacts.length(),
      0,
    )
    guard notifications.try_get() is Some(changed) else {
      fail("no notification after attach")
    }
    assert_eq(changed.wire_name(), "session.artifacts_changed")
    while notifications.try_get() is Some(_) {

    }
    for
      invalid in [
        Json::empty_object(),
        { "artifacts": [] },
        { "url": "https://github.com/o/r/pull/2" },
        { "type": "file", "url": "https://github.com/o/r/pull/2" },
        { "type": "pull_request", "url": "javascript:alert(1)" },
        {
          "type": "pull_request",
          "url": "https://github.com/o/r/pull/2",
          "session": "two",
        },
      ] {
      assert_true(
        client.call_tool(name="artifacts_attach", arguments=invalid).is_error,
      )
      assert_true(
        @engine.session_artifacts_list(state.manager(), "one") == snapshot,
      )
      assert_true(notifications.try_get() is None)
    }
    // Neither detach nor the previous replacement tool is exposed to agents.
    for name in ["artifacts_detach", "artifacts_bind", "session_pr_bind"] {
      try client.call_tool(name~, arguments=first) catch {
        _ => ()
      } noraise {
        result => assert_true(result.is_error)
      }
    }
    let restarted = @api.ApiState(engine="unused")
    assert_true(
      @engine.session_artifacts_list(restarted.manager(), "one") == snapshot,
    )
    assert_false(
      client.call_tool(name="artifacts_attach", arguments=second).is_error,
    )
    let listed = client.call_tool(name="artifacts_list", arguments={})
    let expected : @protocol.SessionArtifacts = @json.from_json({
      "artifacts": [first, branch, second],
    })
    assert_eq(@json.parse(listed.render_text()), expected.to_json())
    // UI removal targets one typed artifact without losing another attachment.
    let first_artifact : @protocol.SessionArtifact = @json.from_json(first)
    let after_remove = @engine.session_artifacts_update(
      state.manager(),
      "one",
      current => current.without(first_artifact),
      () => (),
    )
    assert_eq(after_remove.artifacts.length(), 2)
    assert_true(after_remove.artifacts.contains(@json.from_json(second)))
    // Separate managers serialize append against the latest stored snapshot.
    let third : @protocol.SessionArtifact = @json.from_json({
      "type": "pull_request",
      "url": "https://github.com/o/r/pull/3",
    })
    let fourth : @protocol.SessionArtifact = @json.from_json({
      "type": "branch",
      "url": "https://github.com/o/r/tree/four",
    })
    let left = group.spawn(() => {
      @engine.session_artifacts_update(
        state.manager(),
        "one",
        current => current.attach(third),
        () => (),
      )
    })
    let right = group.spawn(() => {
      @engine.session_artifacts_update(
        restarted.manager(),
        "one",
        current => current.attach(fourth),
        () => (),
      )
    })
    ignore(left.wait())
    ignore(right.wait())
    let concurrent = @engine.session_artifacts_list(state.manager(), "one")
    assert_eq(concurrent.artifacts.length(), 4)
    assert_true(
      concurrent.artifacts.contains(third) &&
      concurrent.artifacts.contains(fourth),
    )
    // The sidecar follows archive/restore; stale grants cannot recreate it.
    let two = expected
    ignore(
      @engine.session_artifacts_update(state.manager(), "two", _ => two, () => {
        ()
      }),
    )
    let script = root.join("list-engine.sh").to_string()
    @fs.write_file(script, "#!/bin/sh\nprintf '[]\\n'\n")
    @fs.chmod(script, 0o700)
    let actor = @engine.new_engine_actor(script)
    let ready : @async.Queue[Unit] = Queue(kind=Blocking(1))
    group.spawn_bg(no_wait=true, () => {
      actor.run(
        EventSink(event => {
          if event is Connected(_) {
            ignore(ready.try_put(()) catch { _ => false })
          }
        }),
        _ => (),
      )
    })
    @async.with_timeout(3000, () => ready.get())
    assert_true(
      @engine.archive_session(actor.manager(), "two", (_, _) => ())
      is Archived(_),
    )
    assert_true(
      @fs.exists(
        workspace
        .join(".openseek/archived/sessions/two/artifacts.json")
        .to_string(),
      ),
    )
    try
      @engine.session_artifacts_update(state.manager(), "two", _ => two, () => {
        ()
      })
    catch {
      _ => ()
    } noraise {
      _ => fail("an archived session was recreated")
    }
    ignore(@engine.unarchive_session(actor.manager(), "two", (_, _) => ()))
    assert_true(@engine.session_artifacts_list(state.manager(), "two") == two)
    // Hold the cross-host archive commit boundary while a second manager
    // starts an attach. Move the record under that lock, as archive does, then
    // let the writer resume: it must revalidate before creating any sidecar.
    let live = workspace.join(".openseek/sessions/two")
    let archived = workspace.join(".openseek/archived/sessions/two")
    let pending = {
      let shared = @fsx.FileLock::acquire(
        workspace.join(".openseek/archived").to_path(),
      )
      defer shared.release()
      let mut completed = false
      let pending = group.spawn(() => {
        let refused = try {
          ignore(
            @engine.session_artifacts_update(state.manager(), "two", _ => two, () => {
              ()
            }),
          )
          false
        } catch {
          @engine.EngineError(_) => true
          error => raise error
        }
        completed = true
        refused
      })
      @async.sleep(100)
      assert_false(completed)
      @fs.rename(live.to_string(), archived.to_string())
      pending
    }
    assert_true(@async.with_timeout(3000, () => pending.wait()))
    assert_false(@fs.exists(live.to_string()))
    ignore(@engine.unarchive_session(actor.manager(), "two", (_, _) => ()))
    assert_true(@engine.session_artifacts_list(state.manager(), "two") == two)
    // I/O failure must not masquerade as an empty list.
    let file = workspace.join(".openseek/sessions/one/artifacts.json")
    @fs.remove(file.to_string())
    @fs.mkdir(file.to_string())
    assert_true(client.call_tool(name="artifacts_list", arguments={}).is_error)
    assert_true(
      client.call_tool(name="artifacts_attach", arguments=second).is_error,
    )
    group.return_immediately(())
  })
}

///|
let _platform_test_import : Unit = ignore(@sys.get_env_var)
