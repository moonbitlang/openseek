///|
test "Chats exclude retired local history and user named workspaces remain projects" {
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
    archived: [
      {
        id: "archived-local",
        title: Some("Archived local chat"),
        workspace: managed,
        workspace_name: "Unnamed workspace",
        updated_at_ms: Some(1),
      },
    ],
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
  // Each list is its own sidebar mode; archived conversations are on
  // Settings' archived page.
  let labels = (model : Model) => {
    model.sidebar_component_sections(model.dev()).map(section => section.label)
  }
  let work = { ..model, sidebar_mode: WorkMode, }
  assert_eq(labels(work), [None])
  assert_eq(work.sidebar_component_sections(work.dev())[0].entries.length(), 2)
  let chat = { ..model, sidebar_mode: ChatMode, }
  assert_eq(labels(chat), [Some("Chats")])
  assert_true(chat.sidebar_component_sections(chat.dev())[0].entries is [_])
  // The retired chat's archive reaches neither the sidebar nor the archived
  // page.
  assert_true(chat.archived_chat_groups().is_empty())
  assert_true(chat.account is None)
}

///|
test "managed Codex chats are excluded from Chat and Work lists" {
  let root = @interop.ChannelId::Local.test_resource("/app-data/workspaces")
  let managed = @interop.ChannelId::Local.test_resource(
    "/app-data/workspaces/codex-chat",
  )
  let model = test_model().with_dev(dev => {
    ..dev,
    projects: [managed],
    chat_root: Some(Ok(root)),
  })
  let model = {
    ..model,
    screen: Codex,
    sidebar_mode: ChatMode,
    conversations: [],
    codex: @codex.State::from_thread_snapshot({
      "thread": {
        "id": "local-codex",
        "name": "Existing Codex chat",
        "cwd": managed.path,
        "projectRoot": managed.path,
        "turns": [],
      },
    }),
  }
  for mode in ([ChatMode, WorkMode] : Array[@sidebar.Mode]) {
    let model = { ..model, sidebar_mode: mode, }
    for section in model.sidebar_component_sections(model.dev()) {
      assert_false(
        section.entries.any(entry => entry is @section.Conversation(_)),
      )
    }
  }
}

///|
test "the sidebar mode follows the conversation on screen and keeps a manual pick" {
  let dispatch = test_dispatch()
  let channel = @interop.ChannelId::Local
  let root = channel.test_resource("/app-data/workspaces")
  let managed = channel.test_resource("/app-data/workspaces/Unnamed workspace")
  let named = channel.test_resource("/user/project")
  let model = test_model().with_dev(dev => {
    ..dev,
    projects: [named, managed],
    chat_root: Some(Ok(root)),
    active_project: Some(named),
  })
  assert_eq(model.sidebar_activation(), Some((WorkMode, model.active_session)))
  // The first transition stamps the conversation already on screen.
  let (_, model) = update(dispatch, ToggleSidebar, model)
  assert_true(model.sidebar_mode is WorkMode)
  // Browsing the other list does not move the conversation, and the pick
  // survives unrelated messages while that conversation stays on screen.
  let (_, browsing) = update(dispatch, SidebarModeSelected(ChatMode), model)
  assert_true(browsing.sidebar_mode is ChatMode)
  assert_eq(browsing.active_session, model.active_session)
  let (_, settled) = update(dispatch, ToggleSidebar, browsing)
  assert_true(settled.sidebar_mode is ChatMode)
  // A dialog preserves the conversation's list and the manual pick.
  let (_, settings) = update(dispatch, OpenSetup, settled)
  assert_true(settings.sidebar_activation() == settled.sidebar_activation())
  assert_true(settings.sidebar_mode is ChatMode)
  // Retired standalone chats no longer claim a sidebar list.
  let in_work = { ..model, sidebar_mode: WorkMode, }
  let (_, revealed) = update(
    dispatch,
    ToggleSidebar,
    in_work.with_active_project(Some(managed)),
  )
  assert_true(revealed.sidebar_activation() is None)
  let (_, ignored) = update(dispatch, SidebarModeLoaded(WorkMode), revealed)
  assert_true(ignored.sidebar_mode is WorkMode)
  let empty = test_model().with_dev(dev => { ..dev, active_project: None, })
  let (_, restored) = update(dispatch, SidebarModeLoaded(ChatMode), empty)
  assert_true(restored.sidebar_mode is ChatMode)
}

///|
test "the stored sidebar mode round-trips and rejects unknown text" {
  for mode in ([ChatMode, WorkMode] : Array[@sidebar.Mode]) {
    assert_eq(parse_sidebar_mode(sidebar_mode_wire(mode)), Some(mode))
  }
  assert_true(parse_sidebar_mode("") is None)
  assert_true(parse_sidebar_mode("code") is None)
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

///|
test "Host catalogs retain project history and exclude retired standalone history" {
  let dispatch = test_dispatch()
  let channel = @interop.ChannelId::Local
  let project = channel.test_project()
  let root = channel.test_resource("/app-data/workspaces")
  let retired = channel.test_resource("/app-data/workspaces/old")
  let (_, model) = update_dev(
    dispatch,
    ProjectsChanged([project, retired], chat_root=Some(Ok(root))),
    test_model(),
  )
  assert_eq(model.dev().projects, [project])
  let ordinary : @transcript.SessionListItem = {
    id: "project-live",
    title: Some("Project history"),
    workspace: project,
    workspace_name: "project",
    updated_at_ms: None,
  }
  let old = { ..ordinary, id: "retired-live", workspace: retired, }
  let (_, model) = update_dev(
    dispatch,
    SessionsLoaded(
      [ordinary, old],
      connection_generation=model.dev().connection_generation,
      request_generation=model.dev().sessions_request_generation,
    ),
    model,
  )
  assert_eq(model.dev().sessions.map(item => item.id), [ordinary.id])
  let archived = { ..ordinary, id: "project-archived", }
  let (_, model) = update_dev(
    dispatch,
    ArchivedLoaded(
      [archived, { ..old, id: "retired-archived", }],
      connection_generation=model.dev().connection_generation,
      request_generation=model.dev().archived_request_generation,
      fresh_session="archive-fallback",
    ),
    model,
  )
  assert_eq(model.dev().archived.map(item => item.id), [archived.id])
  assert_true(
    model.archived_chat_groups() is [{ kind: Project(_), rows: [{ id, .. }], }] &&
    id.conversation() == archived.id,
  )
}

///|
test "navigation does not restore retired standalone Codex conversations" {
  let channel = @interop.ChannelId::Local
  let root = channel.test_resource("/app-data/workspaces")
  let old = channel.test_resource("/app-data/workspaces/old")
  let model = {
    ..test_model().with_dev(dev => { ..dev, chat_root: Some(Ok(root)), }),
    screen: Codex,
    codex: @codex.State::from_thread_snapshot({
      "thread": {
        "id": "retired-codex",
        "cwd": old.path,
        "projectRoot": old.path,
        "turns": [],
      },
    }),
  }
  let (_, unavailable) = update(test_dispatch(), ToggleSidebar, model)
  assert_true(unavailable.navigation.phase is Missing)
}

///|
test "restoring a Host session waits for workspace classification and reports its failure" {
  let model = {
    ..test_model().with_dev(dev => { ..dev, project_catalog: None, }),
    selected_conversation: None,
    loading_conversation: None,
    navigation: {
      ..AppNavigation::empty(),
      location: Some({ device: Some("host"), target: Session("desktop-test"), }),
      phase: Waiting,
    },
  }
  let (_, waiting) = activate_navigation(test_dispatch(), model)
  assert_true(waiting.navigation.phase is Waiting)
  assert_true(waiting.loading_conversation is None)
  let (_, failed) = update(
    test_dispatch(),
    FromDevice(
      Local,
      ProjectsLoadFailed(
        message="directory unavailable",
        connection_generation=0,
        request_generation=0,
      ),
    ),
    waiting,
  )
  assert_true(failed.navigation.phase is Failed("directory unavailable"))
  let (_, retry) = update(test_dispatch(), Navigation(Retry), failed)
  assert_true(retry.dev().project_catalog is None)
  assert_true(retry.navigation.phase is Waiting)
  assert_eq(retry.dev().projects_request_generation, 1)
}
