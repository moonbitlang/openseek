///|
#cfg(not(platform="windows"))
async test "import loads through the normal session API and joins the selected worktree as a writable engine record" {
  with_worktree_fork_fixture((manager, repo, store, checkout) => {
    let workspace = repo.resource_path()
    let exported = ConversationExport::capture(
      manager,
      {
        session: "s-src",
        workspace,
        title: "Imported source",
        archived: false,
      },
      "<script src=\"/viz_app.js\"></script>",
      "",
    )
    // The frozen page carries the run's timeline too: without it an exported
    // conversation could not show the waterfall its readers choose.
    assert_true(exported.html.contains("/api/trajectory/s-src"))
    let created : Array[String] = []
    let session_id = import_session(
      manager,
      {
        source: JsonFile(text=exported.json),
        workspace,
        worktree_of: Some("s-src"),
      },
      on_created=id => created.push(id),
      on_worktree_changed=(_, _) => (),
    )
    assert_eq(created, [session_id])
    assert_true(
      @worktree.list(repo).worktrees is [row] &&
      row.sessions.contains(session_id),
    )
    assert_eq(@worktree.run_dir(repo, session_id), checkout)
    assert_true(store.exists(SessionId(session_id)))
    assert_true(
      list_sessions().groups.any(group => {
        group.sessions.any(row => row.id == session_id)
      }),
    )
    let loaded = load_session(manager, {
      session: session_id,
      workspace: Some(workspace),
    })
    assert_eq(loaded.session.id, Some(session_id))
    assert_true(loaded.session.events is Some(events) && events.length() == 4)
    let restarted = new_engine_manager("engine-must-not-run")
    assert_eq(
      load_session(restarted, {
        session: session_id,
        workspace: Some(workspace),
      }),
      loaded,
    )
    assert_eq(
      load_session(restarted, { session: session_id, workspace: None, }),
      loaded,
    )
    let id : @agent_session.SessionId = SessionId(session_id)
    let saved = store.load(id)
    assert_eq(saved.system_prompt(), "system")
    let continued = store.append(
      saved,
      User(UserMessage(Content([Text("Continue here")]))),
    )
    assert_eq(continued.last_sequence(), 5)
    let fresh = new_engine_manager("engine-must-not-run")
    let reloaded = load_session(fresh, {
      session: session_id,
      workspace: Some(workspace),
    })
    assert_true(reloaded.session.events is Some(events) && events.length() == 5)
    rename_session(fresh, {
      session: session_id,
      workspace,
      title: "Renamed import",
    })
    assert_eq(store.title(id), Some("Renamed import"))
    let lease = fresh.begin_record_op(session_id)
    fresh.end_record_op(session_id, lease)
    let forked = fork_session(
      manager,
      {
        session: session_id,
        workspace,
        through: 4,
        model: "deepseek-flash",
        source_title: "Imported",
        side_chat: None,
      },
      on_created=_ => (),
      on_worktree_changed=(_, _) => (),
    )
    assert_true(store.exists(SessionId(forked.session)))
    // Like any worktree conversation's fork, it works in a checkout of its
    // own.
    let fork_checkout = @worktree.run_dir(repo, forked.session)
    assert_true(fork_checkout != checkout)
    assert_true(@fsx.is_dir(fork_checkout.to_path()))
    assert_true(fresh.record_guards.is_empty())
  })
}

///|
#cfg(not(platform="windows"))
async test "an export's timeline covers the whole run, not just the level it lists" {
  with_worktree_fork_fixture((manager, _repo, store, _checkout) => {
    // A child and a grandchild: the session list stops at the child (each level
    // belongs to its own export), but the run is the whole tree.
    store.create(
      @agent_session.Session(SessionId("s-src-sr-1"), system_prompt="system")
      .append(User(UserMessage(Content([Text("scout")]))))
      .append(Terminal(Finished("done"))),
    )
    store.create(
      @agent_session.Session(
        SessionId("s-src-sr-1-sr-2"),
        system_prompt="system",
      )
      .append(User(UserMessage(Content([Text("nested scout")]))))
      .append(Terminal(Finished("done"))),
    )
    let workspace = _repo.resource_path()
    let exported = ConversationExport::capture(
      manager,
      { session: "s-src", workspace, title: "Run source", archived: false, },
      "<script src=\"/viz_app.js\"></script>",
      "",
    )
    let dataset = @json.parse(exported.json) catch {
      _ => fail("the export dataset must be JSON")
    }
    guard dataset is Object(fields) else { fail("the export must be a map") }
    let listed = match fields.get("/api/sessions") {
      Some(String(listing)) => listing
      _ => fail("the export must list its sessions")
    }
    assert_true(listed.contains("s-src-sr-1"))
    assert_false(listed.contains("s-src-sr-1-sr-2"))
    guard fields.get("/api/trajectory/s-src") is Some(String(timeline)) else {
      fail("the export must bake the run's timeline")
    }
    assert_true(timeline.contains("s-src-sr-1-sr-2"))
  })
}

///|
#cfg(not(platform="windows"))
async test "an export's timeline also covers non-sr children discovered via tool results" {
  with_worktree_fork_fixture((manager, _repo, store, _checkout) => {
    store.create(
      @agent_session.Session(SessionId("s-parent"), system_prompt="system")
      .append(User(UserMessage(Content([Text("delegate")]))))
      .append(
        Assistant(
          AssistantMessage("", tool_calls=[
            ToolCall(id="c1", name="subagent", arguments="{}"),
          ]),
        ),
      )
      .append(
        Tool(
          ToolResult(
            tool_call_id="c1",
            tool_name="subagent",
            content=[Text("ok")],
            data=Json::object({ "session": Json("custom-worker-1") }),
          ),
        ),
      )
      .append(Terminal(Finished("done"))),
    )
    store.create(
      @agent_session.Session(
        SessionId("custom-worker-1"),
        system_prompt="system",
      )
      .append(User(UserMessage(Content([Text("custom worker task")]))))
      .append(Terminal(Finished("ok"))),
    )
    let workspace = _repo.resource_path()
    let exported = ConversationExport::capture(
      manager,
      { session: "s-parent", workspace, title: "Parent run", archived: false, },
      "<script src=\"/viz_app.js\"></script>",
      "",
    )
    let dataset = @json.parse(exported.json) catch {
      _ => fail("the export dataset must be JSON")
    }
    guard dataset is Object(fields) else { fail("the export must be a map") }
    guard fields.get("/api/trajectory/s-parent") is Some(String(timeline)) else {
      fail("the export must bake the run's timeline")
    }
    assert_true(timeline.contains("custom-worker-1"))
  })
}
