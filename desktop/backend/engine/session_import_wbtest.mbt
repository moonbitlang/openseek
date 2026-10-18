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
    let created : Array[String] = []
    let reply = import_session(
      manager,
      {
        source: JsonFile(text=exported.json),
        workspace,
        worktree_of: Some("s-src"),
      },
      on_created=id => created.push(id),
      on_worktree_changed=(_, _) => (),
    )
    assert_eq(created, [reply.session_id])
    assert_true(
      reply.worktrees is [row] && row.sessions.contains(reply.session_id),
    )
    assert_eq(@worktree.run_dir(repo, reply.session_id), checkout)
    assert_true(store.exists(SessionId(reply.session_id)))
    assert_true(
      list_sessions().groups.any(group => {
        group.sessions.any(row => row.id == reply.session_id)
      }),
    )
    let loaded = load_session(manager, {
      session: reply.session_id,
      workspace: Some(workspace),
    })
    assert_eq(loaded.session.id, Some(reply.session_id))
    assert_true(loaded.session.events is Some(events) && events.length() == 4)
    let restarted = new_engine_manager("engine-must-not-run")
    assert_eq(
      load_session(restarted, {
        session: reply.session_id,
        workspace: Some(workspace),
      }),
      loaded,
    )
    assert_eq(
      load_session(restarted, { session: reply.session_id, workspace: None, }),
      loaded,
    )
    let id : @agent_session.SessionId = SessionId(reply.session_id)
    let saved = store.load(id)
    assert_eq(saved.system_prompt(), "system")
    let continued = store.append(
      saved,
      User(UserMessage(Content([Text("Continue here")]))),
    )
    assert_eq(continued.last_sequence(), 5)
    let fresh = new_engine_manager("engine-must-not-run")
    let reloaded = load_session(fresh, {
      session: reply.session_id,
      workspace: Some(workspace),
    })
    assert_true(reloaded.session.events is Some(events) && events.length() == 5)
    rename_session(fresh, {
      session: reply.session_id,
      workspace,
      title: "Renamed import",
    })
    assert_eq(store.title(id), Some("Renamed import"))
    let lease = fresh.begin_record_op(reply.session_id)
    fresh.end_record_op(reply.session_id, lease)
    let forked = fork_session(
      manager,
      {
        session: reply.session_id,
        workspace,
        through: 4,
        model: "deepseek-flash",
        source_title: "Imported",
      },
      on_created=_ => (),
      on_worktree_changed=(_, _) => (),
    )
    assert_true(store.exists(SessionId(forked.session)))
    assert_eq(@worktree.run_dir(repo, forked.session), checkout)
    assert_true(fresh.record_guards.is_empty())
  })
}
