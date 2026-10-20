///|
fn integrated_cloud_model() -> Model {
  let state = {
    ..@cloud.State::empty(),
    user_id: Some("fixture-user"),
    epoch: 3,
    sessions: [
      {
        id: "cloud-a",
        title: Some("Cloud conversation"),
        updated_at: Some(100),
        generating: false,
        archived: false,
      },
    ],
  }
  let model = {
    ..test_model(),
    cloud: state,
    account: Some({
      token: "ts_fixture",
      user: { user_id: "fixture-user", login: "octocat", avatar_url: "", },
    }),
    is_desktop: true,
    deepseek_key_saved: false,
  }
  let (_, model) = update(
    test_dispatch(),
    OpenCloudConversation(account="fixture-user", session="cloud-a"),
    model,
  )
  let request = model.cloud.conversations.get("cloud-a").unwrap().request
  let (_, model) = update(
    test_dispatch(),
    CloudAction(
      @cloud.Loaded(3, "cloud-a", request, {
        messages: [
          {
            task_id: "finished-task",
            kind: "assistant_message",
            data: { "content": "Cloud answer" },
            created_at: 100,
          },
        ],
        generating: false,
      }),
    ),
    model,
  )
  model
}

///|
test "Cloud selection after Settings wins over the previous navigation destination" {
  let dispatch = test_dispatch()
  let model = integrated_cloud_model()
  let (_, settings) = update(dispatch, OpenSetup, model)
  assert_true(settings.screen is Settings)
  let (_, cloud) = update(
    dispatch,
    OpenCloudConversation(account="fixture-user", session="cloud-a"),
    settings,
  )
  assert_true(cloud.screen is Chat)
  assert_true(cloud.cloud_identity() == model.cloud_identity())
  let initial = {
    ..model,
    is_desktop: false,
    devices: [],
    console: { ..model.console, page_device: None, },
  }
  let snapshot : @navigation_browser.Snapshot = {
    path: "/cloud/session/cloud-b",
    settings: false,
    can_back: true,
    can_forward: false,
  }
  let (_, direct) = update(dispatch, Navigation(Browser(snapshot)), initial)
  let (_, repeated) = update(dispatch, Navigation(Browser(snapshot)), initial)
  assert_true(direct.cloud == repeated.cloud)
  assert_true(direct.navigation == repeated.navigation)
  assert_true(
    direct.cloud_identity() ==
    Some(@interop.Cloud(account="fixture-user", session="cloud-b")),
  )
  assert_false(initial.cloud.conversations.contains("cloud-b"))
  let (_, home) = update(
    dispatch,
    Navigation(Browser({ ..snapshot, path: "/cloud", })),
    direct,
  )
  assert_true(home.cloud_selected() && home.cloud_identity() is None)
  assert_true(home.cloud.creation is None)
}

///|
test "navigation restores Cloud across Settings and Work without losing its identity" {
  let dispatch = test_dispatch()
  let model = integrated_cloud_model()
  let (_, settings) = update(dispatch, OpenSetup, model)
  let (_, back) = update(dispatch, Navigation(Back), settings)
  assert_true(back.screen is Chat)
  assert_true(back.cloud_identity() == model.cloud_identity())
  let (_, forward) = update(dispatch, Navigation(Forward), back)
  assert_true(forward.screen is Settings)
  let (_, work) = update(dispatch, OpenSession(Local, "desktop-test"), back)
  assert_true(work.host_selection() is Some({ session: "desktop-test", .. }))
  let (_, cloud) = update(dispatch, Navigation(Back), work)
  assert_true(cloud.screen is Chat)
  assert_true(cloud.cloud_identity() == model.cloud_identity())
}

///|
test "Cloud navigation works in a browser without any host device" {
  let dispatch = test_dispatch()
  let cloud = integrated_cloud_model()
  let model = {
    ..cloud,
    is_desktop: false,
    devices: [],
    console: { ..cloud.console, page_device: None, },
    navigation: AppNavigation::empty(),
  }
  let (_, first) = update(
    dispatch,
    OpenCloudConversation(account="fixture-user", session="cloud-a"),
    model,
  )
  let (_, settings) = update(dispatch, OpenSetup, first)
  let (_, second) = update(
    dispatch,
    OpenCloudConversation(account="fixture-user", session="cloud-b"),
    settings,
  )
  assert_true(second.navigation.can_back)
  let (_, back) = update(dispatch, Navigation(Back), second)
  assert_true(back.screen is Settings && back.navigation.phase is Active)
  let (_, forward) = update(dispatch, Navigation(Forward), back)
  assert_true(
    forward.cloud_identity()
    is Some(@interop.Cloud(account="fixture-user", session="cloud-b")),
  )
}

///|
test "Cloud navigation restores Settings while the host is offline" {
  let dispatch = test_dispatch()
  let cloud = integrated_cloud_model().with_dev(dev => {
    ..dev,
    bridge: BridgeLost("offline"),
  })
  let (_, settings) = update(dispatch, OpenSetup, cloud)
  let (_, reopened) = update(
    dispatch,
    OpenCloudConversation(account="fixture-user", session="cloud-a"),
    settings,
  )
  let (_, back) = update(dispatch, Navigation(Back), reopened)
  assert_true(back.screen is Settings && back.navigation.phase is Active)
  let (_, forward) = update(dispatch, Navigation(Forward), back)
  assert_true(forward.cloud_identity() == cloud.cloud_identity())
  assert_true(forward.navigation.phase is Active)
}

///|
test "navigation cannot restore another account's Cloud conversation" {
  let dispatch = test_dispatch()
  let cloud = integrated_cloud_model()
  let (_, settings) = update(dispatch, OpenSetup, cloud)
  let other = {
    ..settings,
    selected_conversation: None,
    account: Some({
      token: "ts_other",
      user: { user_id: "other-user", login: "other", avatar_url: "", },
    }),
    cloud: { ..@cloud.State::empty(), user_id: Some("other-user"), },
  }
  let (_, back) = update(dispatch, Navigation(Back), other)
  assert_true(back.navigation.phase is Missing)
  assert_true(back.cloud_identity() is None)
  assert_true(back.account == other.account)
  assert_true(back.cloud.conversations.is_empty())
}

///|
test "Back prevents a pending Cloud creation from taking foreground later" {
  let dispatch = test_dispatch()
  let cloud = integrated_cloud_model()
  let (_, settings) = update(dispatch, OpenSetup, cloud)
  let (_, creating) = update(dispatch, CloudAction(@cloud.Create), settings)
  let creating = submit_blank_cloud(creating)
  let creation = creating.cloud.creation.unwrap()
  let (_, back) = update(dispatch, Navigation(Back), creating)
  let (_, late) = update(
    dispatch,
    CloudAction(
      @cloud.Created(creating.cloud.epoch, creation.request, "late-cloud"),
    ),
    back,
  )
  assert_true(back.screen is Settings && late.screen is Settings)
  assert_true(late.navigation.location == back.navigation.location)
  assert_eq(late.navigation.revision, back.navigation.revision)
  assert_true(late.cloud.sessions.any(item => item.id == "late-cloud"))
}

///|
test "Cloud and Local folders keep their own rows, ordering and create action" {
  let channel = @interop.ChannelId::Local
  let root = channel.test_resource("/app-data/workspaces")
  let managed = channel.test_resource("/app-data/workspaces/old-chat")
  let cloud = integrated_cloud_model()
  let model = cloud.with_dev(dev => {
    ..dev,
    projects: [managed],
    chat_root: Some(Ok(root)),
    sessions: [
      {
        id: "local-a",
        title: Some("Older local"),
        workspace: managed,
        workspace_name: "Unnamed workspace",
        updated_at_ms: Some(200),
      },
      {
        id: "local-b",
        title: Some("Newer local"),
        workspace: managed,
        workspace_name: "Unnamed workspace",
        updated_at_ms: Some(400),
      },
    ],
  })
  let model = {
    ..model,
    cloud: {
      ..model.cloud,
      sessions: [
        {
          id: "cloud-a",
          title: Some("Older cloud"),
          updated_at: Some(100),
          generating: false,
          archived: false,
        },
        {
          id: "cloud-b",
          title: Some("Newer cloud"),
          updated_at: Some(300),
          generating: false,
          archived: false,
        },
      ],
    },
  }
  let sections = model.sidebar_component_sections(model.dev())
  let ids = (section : @section.Input) => {
    section.entries.filter_map(entry => {
      match entry {
        @section.Conversation(row) => Some(row.id.conversation())
        _ => None
      }
    })
  }
  assert_eq(sections.map(section => section.label), [
    "Cloud", "Local", "Archived chats",
  ])
  assert_eq(ids(sections[0]), ["cloud-b", "cloud-a"])
  assert_eq(ids(sections[1]), ["local-b", "local-a"])
  assert_true(sections[0].action is Some(_))
  assert_true(sections[1].action is None)
  assert_true(
    !sections[0].initially_collapsed && !sections[1].initially_collapsed,
  )
}

///|
test "Cloud uses the existing composer and transcript without a host workspace" {
  let cloud = integrated_cloud_model()
  let model = {
    ..cloud,
    installed_skills: [
      {
        id: "host-skill",
        name: "Host skill",
        description: "",
        source: "local",
        registry: None,
        enabled: true,
      },
    ],
    composer_context_generation: 7,
    file_panel: { ..cloud.file_panel, request_epoch: 99, },
  }
  let input = model.composer_input()
  assert_true(
    input.identity.owner
    is @interop.Cloud(account="fixture-user", session="cloud-a"),
  )
  assert_true(input.file_index is @composer.FileIndexEmpty(epoch=99))
  assert_eq(input.root, file_ctx(model).root())
  assert_true(input.root is Some({ scheme: "openseek-cloud", .. }))
  assert_true(!input.shell_available && !input.presentation.images_enabled)
  assert_true(
    input.slash_commands.is_empty() && input.installed_skills.is_empty(),
  )
  assert_true(model.transcript_slot() is Some(CloudTranscriptSlot(_)))
  assert_eq(model.selected_conversation_title(), "Cloud conversation")
  assert_true(model.quote_screen() is Some(ChatQuote))
  assert_true(input.quote_target() is Some(_))
  assert_true(input.presentation.context.is_empty())
  assert_true(
    input.presentation.primary_action is @composer.Send(available=true),
  )
  assert_true(!model.file_panel_visible() && !model.terminal_panel_visible())
}

///|
test "the device sign-in gate cannot hide a cached Cloud conversation or quote target" {
  let model = integrated_cloud_model()
  let model = {
    ..model,
    is_desktop: false,
    devices: [],
    console: { ..model.console, auth: AuthSignedOut, page_device: None, },
  }
  assert_true(model.is_console_gated())
  assert_true(model.transcript_slot() is Some(CloudTranscriptSlot(_)))
  assert_true(model.quote_screen() is Some(ChatQuote))
  assert_true(
    model.cloud_identity() ==
    Some(@interop.Cloud(account="fixture-user", session="cloud-a")),
  )
}

///|
test "same-account sign-out retires old composer actions, while the new entry can send" {
  let model = integrated_cloud_model()
  let old = model.composer_input().identity
  let (_, out) = update(test_dispatch(), RemoteDisconnectClicked, model)
  let (_, connecting) = update(test_dispatch(), RemoteConnectClicked, out)
  let epoch = connecting.cloud.epoch + 1
  let (_, signed_in) = update(
    test_dispatch(),
    AccountLoaded(
      connecting.account_epoch,
      Ok(
        Some({
          token: "ts_new",
          user: { user_id: "fixture-user", login: "octocat", avatar_url: "", },
        }),
      ),
    ),
    connecting,
  )
  let (_, signed_in) = update(
    test_dispatch(),
    CloudAction(
      @cloud.Listed(epoch, signed_in.cloud.list_request, model.cloud.sessions),
    ),
    signed_in,
  )
  let (_, opened) = update(
    test_dispatch(),
    OpenCloudConversation(account="fixture-user", session="cloud-a"),
    signed_in,
  )
  let request = opened.cloud.conversations.get("cloud-a").unwrap().request
  let (_, loaded) = update(
    test_dispatch(),
    CloudAction(
      @cloud.Loaded(epoch, "cloud-a", request, {
        messages: [],
        generating: false,
      }),
    ),
    opened,
  )
  let draft : @composer.Draft = {
    task: "A question",
    images: [],
    mentions: [],
  }
  let (_, stale) = update(
    test_dispatch(),
    ComposerAction(@composer.DraftSubmitted(identity=old, draft~)),
    loaded,
  )
  assert_eq(stale.cloud.sequence, loaded.cloud.sequence)
  assert_false(stale.cloud.conversations.get("cloud-a").unwrap().sending)
  let current = loaded.composer_input().identity
  let (_, sent) = update(
    test_dispatch(),
    ComposerAction(@composer.DraftSubmitted(identity=current, draft~)),
    loaded,
  )
  assert_true(sent.cloud.conversations.get("cloud-a").unwrap().sending)
}

///|
test "Cloud selection revokes a pending host snapshot's foreground intent" {
  let model = test_model().with_listed(["late-host"])
  let (_, loading) = update(
    test_dispatch(),
    OpenSession(Local, "late-host"),
    model,
  )
  let owner = loading.loading_conversation
  let prepared = { ..loading, cloud: integrated_cloud_model().cloud, }
  let (_, cloud) = update(
    test_dispatch(),
    OpenCloudConversation(account="fixture-user", session="cloud-a"),
    prepared,
  )
  assert_true(cloud.loading_conversation is None)
  if owner is Some(owner) &&
    cloud.find_conversation(owner.channel, owner.session) is Some(conversation) &&
    conversation.sync is Reloading(generation~, ..) {
    let (_, replied) = apply_session_snapshot(
      test_dispatch(),
      owner.channel,
      cloud,
      owner.session,
      [],
      1,
      None,
      [],
      generation,
      true,
      None,
    )
    assert_true(replied.cloud_identity() == cloud.cloud_identity())
    assert_true(
      replied.find_conversation(owner.channel, owner.session) is Some(_),
    )
  } else {
    fail("the fixture must have a pending host snapshot")
  }
}

///|
test "Codex projection cannot use the remembered Cloud transcript or its capability restrictions" {
  let model = integrated_cloud_model()
  let codex = {
    ..model,
    screen: Codex,
    codex: @codex.State::from_thread_snapshot({
      "thread": { "id": "thread-fixture", "turns": [] },
    }),
  }
  assert_false(codex.cloud_selected())
  let without_cloud_selection = { ..codex, selected_conversation: None, }
  assert_true(
    codex.transcript_input() == without_cloud_selection.transcript_input(),
  )
  assert_true(
    codex.transcript_slot()
    is Some(HostTranscript(source=@transcript_component.Codex, ..)),
  )
  assert_true(codex.quote_screen() is Some(CodexQuote))
  let back = { ..codex, screen: Chat, }
  assert_true(back.transcript_slot() is Some(CloudTranscriptSlot(_)))
}

///|
test "a roster focus change preserves remembered Cloud selection on other screens" {
  let cloud = integrated_cloud_model()
  for screen in [Settings, Codex] {
    let model = {
      ..cloud,
      screen,
      is_desktop: false,
      console: empty_console_state(Some("d_on"), None),
    }
    let (_, reconciled) = apply_roster(
      test_dispatch(),
      model,
      console_test_roster(),
    )
    assert_true(reconciled.cloud_identity() == cloud.cloud_identity())
    assert_true(reconciled.screen == screen)
    let back = { ..reconciled, screen: Chat, }
    assert_true(back.transcript_slot() is Some(CloudTranscriptSlot(_)))
  }
}

///|
test "notification navigation prevents a pending Cloud creation from stealing focus" {
  let model = {
    ..running_model(),
    cloud: integrated_cloud_model().cloud,
    account: integrated_cloud_model().account,
  }
  let (_, creating) = update(test_dispatch(), CloudAction(@cloud.Create), model)
  let creating = submit_blank_cloud(creating)
  let request = creating.cloud.sequence
  let (_, opened) = update(
    test_dispatch(),
    NotificationClicked(run_id="r7"),
    creating,
  )
  assert_true(
    opened.chat_navigation_generation > creating.chat_navigation_generation,
  )
  let (_, completed) = update(
    test_dispatch(),
    CloudAction(@cloud.Created(3, request, "new-cloud")),
    opened,
  )
  assert_true(
    completed.cloud.sessions.any(session => session.id == "new-cloud"),
  )
  assert_true(completed.cloud_identity() is None)
  assert_eq(completed.active_session, "desktop-test")
}

///|
test "remote toggle preserves Cloud while account sign-out clears it" {
  let model = {
    ..integrated_cloud_model(),
    remote_access: Some({
      connected: true,
      managed_by_env: false,
      device_url: Some(
        "https://openseek-api.moonbitlang.cn/console/?device=fixture",
      ),
    }),
  }
  let (_, disconnected) = update(test_dispatch(), RemoteAccessSet(false), model)
  assert_true(disconnected.cloud == model.cloud)
  assert_true(disconnected.selected_conversation == model.selected_conversation)
  let (_, signed_out) = update(test_dispatch(), RemoteDisconnectClicked, model)
  assert_true(signed_out.account is None)
  assert_true(signed_out.remote_access == model.remote_access)
  assert_true(signed_out.remote_connecting)
}

///|
test "Local setup does not interrupt Cloud selection or background settings" {
  let model = integrated_cloud_model()
  let (_, opened) = update(test_dispatch(), OpenApiSetup, model)
  assert_false(opened.api_setup_open)
  let (_, settled) = update_dev(
    test_dispatch(),
    HostSettingsLoaded(
      host_settings(provider="deepseek"),
      connection_generation=None,
    ),
    { ..model, api_setup_open: true, },
  )
  assert_false(settled.api_setup_open)
  assert_true(
    settled.composer_input().presentation.primary_action
    is @composer.Send(available=true),
  )
}

///|
test "Cloud suppression does not dismiss Work API setup" {
  let model = integrated_cloud_model()
  let (_, work) = update(
    test_dispatch(),
    OpenSession(Local, "desktop-test"),
    model,
  )
  let work = work.settle_api_setup()
  assert_true(work.api_setup_open)
  let (_, cloud) = update(
    test_dispatch(),
    OpenCloudConversation(account="fixture-user", session="cloud-a"),
    work,
  )
  assert_false(cloud.api_setup_open)
  assert_false(cloud.api_setup_dismissed)
  let (_, returned) = update(
    test_dispatch(),
    OpenSession(Local, "desktop-test"),
    cloud,
  )
  assert_true(returned.settle_api_setup().api_setup_open)
  let (_, dismissed) = update(test_dispatch(), DismissApiSetup, work)
  let (_, cloud) = update(
    test_dispatch(),
    OpenCloudConversation(account="fixture-user", session="cloud-a"),
    dismissed,
  )
  let (_, returned) = update(
    test_dispatch(),
    OpenSession(Local, "desktop-test"),
    cloud,
  )
  assert_false(returned.settle_api_setup().api_setup_open)
}

///|
test "project New chat replaces Cloud selection before the host rotation arrives" {
  let model = integrated_cloud_model()
  let project = @interop.ChannelId::Local.test_project()
  let (_, navigating) = update(
    test_dispatch(),
    NewChatIn(Local, Some(project)),
    model,
  )
  assert_true(navigating.cloud_identity() is None)
  let (_, rotated) = update(
    test_dispatch(),
    SessionRotated({ channel: Local, session: "fresh-work", }),
    navigating,
  )
  assert_eq(rotated.active_session, "fresh-work")
  assert_true(rotated.active_conversation() is Some(_))
}

///|
test "late Cloud creation cannot replace a project New chat" {
  let model = integrated_cloud_model()
  let (_, creating) = update(test_dispatch(), CloudAction(@cloud.Create), model)
  let creating = submit_blank_cloud(creating)
  let creation = creating.cloud.creation.unwrap()
  let (_, navigating) = update(
    test_dispatch(),
    NewChatIn(Local, Some(@interop.ChannelId::Local.test_project())),
    creating,
  )
  let (_, rotated) = update(
    test_dispatch(),
    SessionRotated({ channel: Local, session: "new-work", }),
    navigating,
  )
  let (_, settled) = update(
    test_dispatch(),
    CloudAction(
      @cloud.Created(creating.cloud.epoch, creation.request, "late-cloud"),
    ),
    rotated,
  )
  assert_true(settled.cloud_identity() is None)
  assert_eq(settled.active_session, "new-work")
  assert_true(settled.cloud.sessions.any(item => item.id == "late-cloud"))
}

///|
test "the new-chat shortcut follows the visible conversation instead of the sidebar" {
  let model = integrated_cloud_model()
  let (_, cloud) = update(test_dispatch(), NewChatRequested, {
    ..model,
    sidebar_mode: WorkMode,
  })
  assert_true(cloud.cloud.creation is Some(_))
  let (_, work) = update(
    test_dispatch(),
    OpenSession(Local, "desktop-test"),
    model,
  )
  let work = { ..work, sidebar_mode: ChatMode, }
  let (_, navigating) = update(test_dispatch(), NewChatRequested, work)
  let (_, rotated) = update(
    test_dispatch(),
    SessionRotated({ channel: Local, session: "shortcut-work", }),
    navigating,
  )
  assert_true(rotated.cloud.creation is None)
  assert_eq(rotated.active_session, "shortcut-work")
  assert_true(rotated.active_conversation() is Some(_))
  for message in [OpenSetup, OpenSkills, OpenSchedules] {
    let (_, covered) = update(test_dispatch(), message, model)
    let (_, created) = update(test_dispatch(), NewChatRequested, covered)
    assert_true(created.cloud.creation is Some(_))
    let (_, covered) = update(test_dispatch(), message, work)
    let (_, created) = update(test_dispatch(), NewChatRequested, covered)
    assert_true(created.cloud.creation is None)
  }
}

///|
test "managed local and Codex Chats start Cloud even when browsing Work" {
  let channel = @interop.ChannelId::Local
  let root = channel.test_resource("/app-data/workspaces")
  let managed = channel.test_resource("/app-data/workspaces/old-chat")
  let model = integrated_cloud_model().with_dev(dev => {
    ..dev,
    projects: [managed],
    active_project: Some(managed),
    chat_root: Some(Ok(root)),
  })
  let model = model.replace_conversation({
    ..model.find_conversation(channel, "desktop-test").unwrap(),
    workspace: Project(root=managed),
  })
  let model = {
    ..model.activate(channel, "desktop-test", managed),
    sidebar_mode: WorkMode,
  }
  let (_, created) = update(test_dispatch(), NewChatRequested, model)
  assert_true(created.cloud.creation is Some(_))
  for message in [OpenSetup, OpenSkills, OpenSchedules] {
    let (_, covered) = update(test_dispatch(), message, model)
    let (_, created) = update(test_dispatch(), NewChatRequested, covered)
    assert_true(created.cloud.creation is Some(_))
  }
  let codex = {
    ..model,
    screen: Codex,
    codex: @codex.State::from_thread_snapshot({
      "thread": {
        "id": "local-codex",
        "cwd": managed.path,
        "projectRoot": managed.path,
        "turns": [],
      },
    }),
  }
  let (_, created) = update(test_dispatch(), NewChatRequested, codex)
  assert_true(created.cloud.creation is Some(_))
  for message in [OpenSetup, OpenSkills, OpenSchedules] {
    let (_, covered) = update(test_dispatch(), message, codex)
    let (_, created) = update(test_dispatch(), NewChatRequested, covered)
    assert_true(created.cloud.creation is Some(_))
  }
}

///|
test "new-chat shortcuts create conversations in the selected Codex project" {
  let channel = @interop.ChannelId::Local
  let chat_root = channel.test_resource("/app-data/workspaces")
  let managed = channel.test_resource("/app-data/workspaces/old-chat")
  let ordinary = channel.test_resource("/work/previous-project")
  let project = channel.test_resource("/work/codex-project")
  let actual : Array[@common.Uri] = []
  for previous in [managed, ordinary] {
    let model = test_model().with_dev(dev => {
      ..dev,
      projects: [previous, project],
      active_project: Some(previous),
      chat_root: Some(Ok(chat_root)),
    })
    let model = model.replace_conversation({
      ..model.active(),
      workspace: Project(root=previous),
    })
    let model = {
      ..model,
      screen: Codex,
      sidebar_mode: WorkMode,
      codex: @codex.State::from_thread_snapshot({
        "thread": {
          "id": "codex-work",
          "cwd": project.path,
          "projectRoot": project.path,
          "turns": [],
        },
      }),
    }
    let (_, settings) = update(test_dispatch(), OpenSetup, model)
    for selected in [model, settings] {
      let (_, requested) = update(test_dispatch(), NewChatRequested, selected)
      let (_, created) = update(
        test_dispatch(),
        SessionRotated({ channel, session: "new-work", }),
        requested,
      )
      actual.push(created.active().project())
    }
  }
  assert_eq(actual, [project, project, project, project])
}
