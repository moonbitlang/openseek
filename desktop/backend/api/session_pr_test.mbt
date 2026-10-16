///|
#cfg(not(platform="windows"))
async test "host MCP binds only its caller and persists atomic full replacements" {
  let root = @pathx.Path(
    @fs.realpath(@fs.tmpdir(prefix="seekmoon-pr-bindings-")),
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
    map=value => if value is SessionPrChanged(_) { Some(value) } else { None },
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
    let tools = client.list_tools().map(tool => tool.name)
    assert_eq(tools.length(), 3)
    for name in ["session", "session_pr_list", "session_pr_bind"] {
      assert_true(tools.contains(name))
    }
    let first : Json = {
      "bindings": [
        { "url": "https://github.com/o/r/pull/1" },
        { "url": "https://github.com/o/r/pull/1" },
        { "url": "https://github.com/o/r/tree/topic" },
      ],
    }
    let saved = client.call_tool(name="session_pr_bind", arguments=first)
    assert_false(saved.is_error)
    let snapshot : @protocol.SessionPrBindings = @json.from_json(
      @json.parse(saved.render_text()),
    )
    assert_eq(snapshot.bindings.length(), 2)
    assert_eq(
      @engine.session_pr_list(state.manager(), "two").bindings.length(),
      0,
    )
    guard notifications.try_get() is Some(changed) else {
      fail("no notification after save")
    }
    assert_eq(changed.wire_name(), "session.pr_changed")
    for
      invalid in [
        Json::empty_object(),
        { "bindings": null },
        {
          "bindings": [
            { "url": "https://github.com/o/r/pull/2" },
            { "url": "javascript:alert(1)" },
          ],
        },
        { "session": "two", "bindings": [] },
      ] {
      assert_true(
        client.call_tool(name="session_pr_bind", arguments=invalid).is_error,
      )
      assert_true(@engine.session_pr_list(state.manager(), "one") == snapshot)
      assert_true(notifications.try_get() is None)
    }
    let restarted = @api.ApiState(engine="unused")
    assert_true(@engine.session_pr_list(restarted.manager(), "one") == snapshot)
    let replacement : Json = {
      "bindings": [{ "url": "https://github.com/o/r/pull/2" }],
    }
    assert_false(
      client.call_tool(name="session_pr_bind", arguments=replacement).is_error,
    )
    let listed = client.call_tool(name="session_pr_list", arguments={})
    assert_eq(@json.parse(listed.render_text()), replacement)
    assert_false(
      client.call_tool(name="session_pr_bind", arguments={ "bindings": [] }).is_error,
    )
    assert_eq(
      @engine.session_pr_list(state.manager(), "one").bindings.length(),
      0,
    )
    // The sidecar follows the actual archive/restore operations, and an old
    // grant cannot recreate a live record while the session is archived.
    let two : @protocol.SessionPrBindings = @json.from_json(replacement)
    ignore(
      @engine.session_pr_update(state.manager(), "two", _ => two, () => ()),
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
        .join(".openseek/archived/sessions/two/pr-bindings.json")
        .to_string(),
      ),
    )
    try
      @engine.session_pr_update(state.manager(), "two", _ => two, () => ())
    catch {
      _ => ()
    } noraise {
      _ => fail("an archived session was recreated")
    }
    ignore(@engine.unarchive_session(actor.manager(), "two", (_, _) => ()))
    assert_true(@engine.session_pr_list(state.manager(), "two") == two)
    // Hold the cross-host archive commit boundary while a second manager
    // starts a bind. Move the record under that lock, as archive does, then
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
            @engine.session_pr_update(state.manager(), "two", _ => two, () => ()),
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
    assert_true(@engine.session_pr_list(state.manager(), "two") == two)
    // I/O failure must not masquerade as an empty list.
    let file = workspace.join(".openseek/sessions/one/pr-bindings.json")
    @fs.remove(file.to_string())
    @fs.mkdir(file.to_string())
    assert_true(client.call_tool(name="session_pr_list", arguments={}).is_error)
    assert_true(
      client.call_tool(name="session_pr_bind", arguments=replacement).is_error,
    )
    group.return_immediately(())
  })
}

///|
let _platform_test_import : Unit = ignore(@sys.get_env_var)
