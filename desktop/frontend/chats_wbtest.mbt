///|
test "one-click chat creation blocks repeats and adopts only its matching reply" {
  let dispatch = test_dispatch()
  let (_, creating) = update(dispatch, CreateChat(Local), test_model())
  assert_true(creating.project_picker is None)
  guard creating.chat_creation is Some((channel, generation, _)) else {
    fail("expected a pending chat creation")
  }
  let (_, duplicate) = update(dispatch, CreateChat(Local), creating)
  assert_eq(duplicate.chat_creation, creating.chat_creation)
  let path = "/app-data/workspaces/Unnamed workspace"
  let (_, stale) = update(
    dispatch,
    ChatWorkspaceCreated(channel~, generation=generation - 1, result=Ok(path)),
    creating,
  )
  assert_true(stale.pending_project_adoption is None)
  assert_eq(stale.chat_creation, creating.chat_creation)
  let (_, received) = update(
    dispatch,
    ChatWorkspaceCreated(channel~, generation~, result=Ok(path)),
    creating,
  )
  assert_true(received.chat_creation is None)
  assert_true(
    received.pending_project_adoption is Some(pending) &&
    pending.requested == path,
  )
}

///|
test "chat creation failure and a dead connection cannot steal project selection" {
  let dispatch = test_dispatch()
  let (_, creating) = update(dispatch, CreateChat(Local), test_model())
  guard creating.chat_creation is Some((channel, generation, _)) else {
    fail("expected pending creation")
  }
  let (_, failed) = update(
    dispatch,
    ChatWorkspaceCreated(channel~, generation~, result=Err("disk full")),
    creating,
  )
  assert_true(failed.chat_creation is None)
  assert_true(failed.pending_project_adoption is None)
  assert_eq(failed.active_session, creating.active_session)
  let reconnected = creating.with_dev(dev => {
    ..dev,
    connection_generation: dev.connection_generation + 1,
  })
  let (_, stale) = update(
    dispatch,
    ChatWorkspaceCreated(channel~, generation~, result=Ok("/app/old")),
    reconnected,
  )
  assert_true(stale.pending_project_adoption is None)
  assert_true(!stale.chat_creation_pending())
}

///|
test "managed chats are flat and user named workspaces remain projects" {
  let channel = @interop.ChannelId::Local
  let root = channel.test_resource("/app-data/workspaces")
  let managed = channel.test_resource("/app-data/workspaces/Unnamed workspace")
  let named = channel.test_resource("/user/Unnamed workspace")
  let prefix_sibling = channel.test_resource(
    "/app-data/workspaces-other/project",
  )
  let model = test_model().with_dev(dev => {
    ..dev,
    projects: [named, managed, prefix_sibling],
    chat_root: Some(Ok(root)),
    active_project: Some(managed),
  })
  let model = model.replace_conversation({
    ..model.active(),
    workspace: Project(root=managed),
  })
  assert_true(model.dev().is_chat_workspace(managed))
  assert_true(!model.dev().is_chat_workspace(named))
  assert_true(!model.dev().is_chat_workspace(prefix_sibling))
  assert_true(!model.can_choose_new_chat_project())
  assert_eq(model.transcript_projects().length(), 2)
  let sections = model.sidebar_component_sections(model.dev())
  let projects = sections.filter(section => section.label == "Projects")
  assert_eq(projects[0].entries.length(), 2)
  let chats = sections.filter(section => section.label == "Chats")
  assert_eq(chats.length(), 1)
  assert_eq(chats[0].activation, Some(model.active_session))
  assert_true(
    chats[0].entries is [@section.Conversation(row)] &&
    row.label == "New chat" &&
    !row.nested &&
    row.active,
  )
}

///|
test "stale workspace snapshots cannot move Chats back into Projects" {
  let dispatch = test_dispatch()
  let root = @interop.ChannelId::Local.test_resource("/app-data/workspaces")
  let chat = @interop.ChannelId::Local.test_resource("/app-data/workspaces/one")
  let (_, changed) = update_dev(
    dispatch,
    ProjectsChanged([chat], chat_root=Some(Ok(root))),
    test_model(),
  )
  let (_, stale) = update_dev(
    dispatch,
    ProjectsLoaded(
      [chat],
      chat_root=None,
      connection_generation=0,
      request_generation=0,
    ),
    changed,
  )
  assert_eq(stale.dev().chat_root, Some(Ok(root)))
}

///|
test "failed chat metadata preserves ordinary project snapshots and reports its own error" {
  let dispatch = test_dispatch()
  let project = @interop.ChannelId::Local.test_resource("/user/project")
  let (_, loaded) = update_dev(
    dispatch,
    ProjectsLoaded(
      [project],
      chat_root=Some(Err("permission denied")),
      connection_generation=0,
      request_generation=0,
    ),
    test_model(),
  )
  assert_eq(loaded.dev().projects, [project])
  assert_true(
    loaded.sidebar_component_input().notices.contains(
      "Chats storage unavailable: permission denied",
    ),
  )
  let added = @interop.ChannelId::Local.test_resource("/user/added")
  let (_, changed) = update_dev(
    dispatch,
    ProjectsChanged([project, added], chat_root=Some(Err("permission denied"))),
    loaded,
  )
  assert_eq(changed.dev().projects, [project, added])
  let (_, removed) = update_dev(
    dispatch,
    ProjectsChanged([added], chat_root=Some(Err("permission denied"))),
    changed,
  )
  assert_eq(removed.dev().projects, [added])
  let (_, recovered) = update_dev(
    dispatch,
    ProjectsChanged(
      [added],
      chat_root=Some(
        Ok(@interop.ChannelId::Local.test_resource("/app-data/workspaces")),
      ),
    ),
    removed,
  )
  assert_true(recovered.sidebar_component_input().notices.is_empty())
}
