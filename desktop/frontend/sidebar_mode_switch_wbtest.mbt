///|
/// A Work conversation with a typed draft and a run in flight on screen, after
/// the Cloud conversation `cloud-a` was on screen before it.
fn work_after_cloud() -> Model raise {
  let project = @interop.ChannelId::Local.test_project()
  let listed : @transcript.SessionListItem = {
    id: "desktop-test",
    title: Some("Work conversation"),
    workspace: project,
    workspace_name: "project",
    updated_at_ms: None,
  }
  let model = integrated_cloud_model()
    .with_active_project(Some(project))
    .with_dev(dev => { ..dev, sessions: [listed], })
  let (_, model) = update(
    test_dispatch(),
    OpenSession(Local, "desktop-test"),
    model,
  )
  model.replace_conversation({
    ..model.active(),
    task: "half-written follow-up",
    run: Starting(submission_id="in-flight"),
  })
}

///|
test "the mode switch moves the column to each mode's last page and back" {
  let work = work_after_cloud()
  assert_true(work.sidebar_mode is WorkMode)
  assert_true(work.navigation.location is Some({ target: Session(_), .. }))
  let (_, chat) = update(test_dispatch(), SidebarModeSelected(ChatMode), work)
  assert_true(chat.sidebar_mode is ChatMode)
  assert_true(
    chat.cloud_identity() is Some(@interop.Cloud(session="cloud-a", ..)),
  )
  assert_true(
    chat.navigation.location
    is Some({ target: CloudSession(session="cloud-a", ..), .. }),
  )
  // Leaving the column is a navigation, so the intents it fences retire.
  assert_true(chat.chat_navigation_generation > work.chat_navigation_generation)
  let (_, back) = update(test_dispatch(), SidebarModeSelected(WorkMode), chat)
  assert_true(back.sidebar_mode is WorkMode)
  assert_false(back.cloud_selected())
  assert_eq(back.active_session, "desktop-test")
  let restored = back.active()
  assert_eq(restored.task, "half-written follow-up")
  assert_true(restored.run is Starting(submission_id="in-flight"))
  assert_true(back.navigation.location == work.navigation.location)
}

///|
test "picking the mode already on screen leaves the column and the intents" {
  let work = work_after_cloud()
  let (_, same) = update(test_dispatch(), SidebarModeSelected(WorkMode), work)
  assert_true(same.navigation.location == work.navigation.location)
  assert_eq(same.chat_navigation_generation, work.chat_navigation_generation)
  assert_eq(same.active_session, work.active_session)
}

///|
test "a mode with no page yet opens its fresh page" {
  // Chat: from a Work conversation, with no Cloud page shown before.
  let model = {
    ..integrated_cloud_model(),
    mode_returns: ModeReturns::empty(),
  }
  let (_, work) = update(test_dispatch(), OpenSession(Local, "desktop-test"), {
    ..model,
    mode_returns: ModeReturns::empty(),
  })
  let work = { ..work, mode_returns: { ..work.mode_returns, chat: None, }, }
  let (_, chat) = update(test_dispatch(), SidebarModeSelected(ChatMode), work)
  assert_true(chat.navigation.location is Some({ target: Cloud, .. }))
  assert_true(chat.cloud_selected() && chat.cloud_identity() is None)
  assert_true(chat.sidebar_mode is ChatMode)
  // Work: from a Cloud conversation, with no Work page shown before.
  let cloud = { ..model, mode_returns: { ..model.mode_returns, work: None, }, }
  let (_, fresh) = update(test_dispatch(), SidebarModeSelected(WorkMode), cloud)
  assert_true(fresh.navigation.location is Some({ target: ChatNew, .. }))
  assert_false(fresh.cloud_selected())
  assert_true(fresh.sidebar_mode is WorkMode)
}

///|
test "a remembered Cloud conversation deleted since opens Cloud home" {
  let work = work_after_cloud()
  let work = {
    ..work,
    cloud: { ..work.cloud, retired: work.cloud.retired + ["cloud-a"], },
  }
  let (_, chat) = update(test_dispatch(), SidebarModeSelected(ChatMode), work)
  assert_true(chat.navigation.location is Some({ target: Cloud, .. }))
  assert_true(chat.cloud_identity() is None)
}

///|
test "the narrow drawer stays open across a mode switch" {
  let work = { ..work_after_cloud(), narrow: true, sidebar_open: true, }
  let (_, chat) = update(test_dispatch(), SidebarModeSelected(ChatMode), work)
  assert_true(chat.cloud_identity() is Some(_))
  assert_true(chat.sidebar_open)
}

///|
test "a page without a host shows Chat alone" {
  let cloud = integrated_cloud_model()
  let cloud = {
    ..cloud,
    is_desktop: false,
    console: { ..cloud.console, page_device: None, },
    devices: [],
  }
  let (_, picked) = update(
    test_dispatch(),
    SidebarModeSelected(WorkMode),
    cloud,
  )
  assert_true(picked.sidebar_mode is ChatMode)
  assert_true(picked.navigation.location == cloud.navigation.location)
  assert_eq(picked.chat_navigation_generation, cloud.chat_navigation_generation)
}

///|
test "a stored Chat pick moves a blank Work start page to Chat" {
  let model = test_model()
  let blank = {
    ..model,
    navigation: {
      ..model.navigation,
      location: Some({ device: model.console.page_device, target: ChatNew, }),
    },
  }
  let (_, launched) = update(
    test_dispatch(),
    SidebarModeLoaded(ChatMode),
    blank,
  )
  assert_true(launched.navigation.location is Some({ target: Cloud, .. }))
  assert_true(launched.sidebar_mode is ChatMode)
  assert_true(launched.launch_mode is None)
  // The start page can be learned after the stored pick: the pick waits.
  let (_, waiting) = update(test_dispatch(), SidebarModeLoaded(ChatMode), model)
  assert_true(waiting.navigation.location is None)
  let (_, arrived) = update(test_dispatch(), ToggleSidebar, {
    ..waiting,
    navigation: blank.navigation,
  })
  assert_true(arrived.navigation.location is Some({ target: Cloud, .. }))
  // A start page the URL names stays.
  let named = {
    ..model,
    navigation: {
      ..model.navigation,
      location: Some({
        device: model.console.page_device,
        target: Session("desktop-test"),
      }),
    },
  }
  let (_, kept) = update(test_dispatch(), SidebarModeLoaded(ChatMode), named)
  assert_true(kept.navigation.location == named.navigation.location)
  assert_true(kept.launch_mode is None)
}
