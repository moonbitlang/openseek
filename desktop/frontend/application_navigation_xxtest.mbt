///|
test "global navigation preserves the visit sequence and is pure" {
  let dispatch = test_dispatch()
  let initial = { ..test_model(), is_desktop: true, }
  let (_, initial) = update(dispatch, ToggleSidebar, initial)
  let (_, settings) = update(dispatch, OpenSetup, initial)
  let (_, skills) = update(dispatch, OpenSkills, settings)
  let (_, back) = update(dispatch, Navigation(Back), skills)
  let (_, again) = update(dispatch, Navigation(Back), skills)
  assert_true(back.screen is Settings)
  assert_true(back.navigation == again.navigation)
  assert_true(skills.navigation.location is Some({ target: Skills, .. }))
  let (_, conversation) = update(dispatch, Navigation(Back), back)
  assert_true(conversation.screen is Chat)
  assert_eq(conversation.active_session, "desktop-test")
  let (_, forward) = update(dispatch, Navigation(Forward), conversation)
  assert_true(forward.screen is Settings)
  let (_, branch) = update(dispatch, OpenSchedules, forward)
  assert_true(!branch.navigation.can_forward)
}

///|
test "deep link waits for successful catalogs and does not confuse failure with absence" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model(),
    navigation: {
      ..AppNavigation::empty(),
      location: Some({ device: "local", target: Session("missing"), }),
      phase: Waiting,
    },
  }
  let (_, waiting) = activate_navigation(dispatch, model)
  assert_true(waiting.navigation.phase is Waiting)
  let (_, failed) = activate_navigation(dispatch, {
    ..model,
    navigation: {
      ..model.navigation,
      sessions: Some(Err("offline")),
      archived: Some(Ok(())),
    },
  })
  assert_true(failed.navigation.phase is Failed("offline"))
  let (_, missing) = activate_navigation(dispatch, {
    ..model,
    navigation: {
      ..model.navigation,
      sessions: Some(Ok(())),
      archived: Some(Ok(())),
    },
  })
  assert_true(missing.navigation.phase is Missing)
  let model = {
    ..model,
    navigation: { ..model.navigation, sessions: Some(Ok(())), },
  }
  let dev = model.dev()
  let failure = ArchivedFailed(
    message="Archive unavailable",
    connection_generation=dev.connection_generation,
    request_generation=dev.archived_request_generation,
  )
  let (_, failed) = update_dev(dispatch, failure, model)
  let (_, repeated) = update_dev(dispatch, failure, model)
  assert_true(failed.navigation.phase is Failed("Archive unavailable"))
  assert_true(failed.navigation == repeated.navigation)
  assert_true(failed.dev().archived == model.dev().archived)
  for
    stale in [
      ArchivedFailed(
        message="Old request",
        connection_generation=dev.connection_generation,
        request_generation=dev.archived_request_generation - 1,
      ),
      ArchivedFailed(
        message="Old connection",
        connection_generation=dev.connection_generation - 1,
        request_generation=dev.archived_request_generation,
      ),
    ] {
    let (_, ignored) = update_dev(dispatch, stale, model)
    assert_true(ignored.navigation == model.navigation)
  }
}

///|
test "returning to a cached conversation fences a slower foreground read" {
  let dispatch = test_dispatch()
  let base = { ..test_model().with_listed(["second"]), is_desktop: true, }
  let base = {
    ..base,
    conversations: base.conversations.map(conv => {
      ..conv,
      task: "Retained draft",
    }),
  }
  let (_, base) = update(dispatch, ToggleSidebar, base)
  let (_, reading) = update(dispatch, OpenSession(Local, "second"), base)
  let (_, back) = update(dispatch, Navigation(Back), reading)
  assert_eq(back.active_session, "desktop-test")
  assert_true(back.loading_conversation is None)
  let (_, settled) = update_dev(
    dispatch,
    SessionLoaded(
      session="second",
      items=[],
      watermark=0,
      goal=None,
      goal_markers=[],
      prediction=None,
      generation=1,
    ),
    back,
  )
  assert_eq(settled.active_session, "desktop-test")
  assert_true(settled.navigation.location == back.navigation.location)
}

///|
test "opening a thread does not promote a different Codex draft" {
  let dispatch = test_dispatch()
  let (_, draft) = update(
    dispatch,
    CodexDraftRotated(cwd="/work", id="local-draft"),
    { ..test_model(), is_desktop: true, },
  )
  let (_, draft) = update(
    dispatch,
    CodexComposerAction(
      @composer.DraftPresenceChanged(
        identity={
          owner: { channel: Local, session: "local-draft", },
          archive_generation: 0,
        },
        present=true,
        cleared_source=None,
      ),
    ),
    draft,
  )
  let (_, thread) = update(dispatch, CodexOpenThread("existing-thread"), draft)
  let (_, back) = update(dispatch, Navigation(Back), thread)
  assert_true(
    back.navigation.location is Some({ target: CodexDraft("local-draft"), .. }),
  )
  assert_true(back.codex.composing_draft())
  assert_eq(back.codex.active_id(), Some("local-draft"))
}

///|
test "background rotations do not replace an explicit management destination" {
  let dispatch = test_dispatch()
  let (_, settings) = update(dispatch, OpenSetup, {
    ..test_model(),
    is_desktop: true,
  })
  let (_, late) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "late", }),
    settings,
  )
  assert_true(late.screen is Settings)
  assert_true(late.navigation.location == settings.navigation.location)
  assert_true(late.navigation.history == settings.navigation.history)
}

///|
test "allocated drafts cannot overtake a newer navigation intent" {
  let dispatch = test_dispatch()
  let (_, settings) = update(dispatch, OpenSetup, {
    ..test_model(),
    is_desktop: true,
  })
  let (_, first) = update(dispatch, NewChat, settings)
  let first_revision = first.navigation.revision
  let (_, second) = update(dispatch, NewChat, first)
  let (_, stale) = update(
    dispatch,
    Navigation(
      SessionReady(
        { channel: Local, session: "stale", },
        revision=first_revision,
      ),
    ),
    second,
  )
  assert_true(stale.navigation == second.navigation)
  assert_true(stale.find_conversation(Local, "stale") is None)
  let (_, settings) = update(dispatch, OpenSetup, second)
  let (_, late) = update(
    dispatch,
    Navigation(
      CodexDraftReady(
        cwd="/work",
        id="late",
        revision=second.navigation.revision,
      ),
    ),
    settings,
  )
  assert_true(late.screen is Settings)
  assert_true(late.codex == settings.codex)
}

///|
test "leaving a pending workspace allocation cannot adopt its delayed result" {
  let dispatch = test_dispatch()
  let (_, initial) = update(dispatch, ToggleSidebar, {
    ..test_model(),
    is_desktop: true,
  })
  let (_, creating) = update(dispatch, CreateChat(Local), initial)
  assert_true(creating.chat_creation is Some(_))
  let (_, settings) = update(dispatch, OpenSetup, creating)
  assert_true(settings.chat_creation is None)
  let (_, late) = update(
    dispatch,
    ChatWorkspaceCreated(
      channel=Local,
      generation=creating.chat_creation_sequence,
      result=Ok("/new-work"),
    ),
    settings,
  )
  assert_true(late.pending_project_adoption is None)
  assert_true(late.navigation == settings.navigation)
}

///|
test "blank new entries gain a stable draft identity only after content" {
  let dispatch = test_dispatch()
  let (_, blank) = update(dispatch, ToggleSidebar, {
    ..test_model(),
    is_desktop: true,
  })
  assert_true(blank.navigation.location is Some({ target: ChatNew, .. }))
  let other_default = { ..blank, default_agent: CodexAgent, }
  let (_, unchanged) = update(dispatch, NewChat, other_default)
  let (_, repeated) = update(dispatch, NewChat, other_default)
  assert_true(unchanged.navigation == other_default.navigation)
  assert_true(repeated.navigation == unchanged.navigation)
  assert_eq(unchanged.active_session, blank.active_session)
  let (_, duplicate) = update(dispatch, NewChat, blank)
  assert_true(duplicate.navigation == blank.navigation)
  assert_eq(duplicate.active_session, blank.active_session)
  let identity : @composer.Identity = {
    owner: { channel: Local, session: blank.active_session, },
    archive_generation: 0,
  }
  let action = ComposerAction(
    @composer.DraftPresenceChanged(identity~, present=true, cleared_source=None),
  )
  let (_, draft) = update(dispatch, action, blank)
  let (_, repeated) = update(dispatch, action, blank)
  assert_true(draft.navigation == repeated.navigation)
  assert_true(
    draft.navigation.location is Some({ target: ChatDraft("desktop-test"), .. }),
  )
  assert_true(!draft.navigation.can_back)
  let (_, cleared) = update(
    dispatch,
    ComposerAction(
      @composer.DraftPresenceChanged(
        identity~,
        present=false,
        cleared_source=None,
      ),
    ),
    draft,
  )
  assert_true(cleared.navigation.location == draft.navigation.location)
  assert_true(
    cleared.active_conversation() is Some(conv) && conv.worth_keeping(),
  )
  let (_, other) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "other", }),
    cleared,
  )
  assert_true(other.find_conversation(Local, "desktop-test") is Some(_))
}

///|
test "expired draft replaces its entry with a fresh new page" {
  let dispatch = test_dispatch()
  let expired : @navigation.Location = {
    device: "local",
    target: ChatDraft("expired"),
  }
  let base = {
    ..test_model(),
    is_desktop: true,
    conversations: test_model().conversations.map(conv => {
      ..conv,
      task: "Keep existing input",
      draft_addressed: true,
    }),
    navigation: {
      ..AppNavigation::empty(),
      location: Some(expired),
      phase: Waiting,
      history: @navigation.History::empty().visit(expired, replace=true),
    },
  }
  let (_, pending) = activate_navigation(dispatch, base)
  assert_true(pending.navigation.location is Some({ target: ChatNew, .. }))
  assert_true(pending.navigation.phase is PreparingNew)
  let (_, fresh) = update(
    dispatch,
    Navigation(
      SessionReady(
        { channel: Local, session: "fresh", },
        revision=pending.navigation.revision,
      ),
    ),
    pending,
  )
  assert_true(fresh.navigation.phase is Active)
  assert_true(fresh.navigation.location is Some({ target: ChatNew, .. }))
  assert_eq(fresh.active_session, "fresh")
  assert_true(fresh.selected_conversation is Some({ session: "fresh", .. }))
  assert_true(fresh.active_conversation() is Some(conv) && conv.draft_empty())
  assert_true(!fresh.navigation.can_back)
  assert_true(
    fresh.find_conversation(Local, "desktop-test") is Some(conv) &&
    conv.task == "Keep existing input",
  )
}

///|
test "navigation write policy distinguishes foreground visits and background identity updates" {
  let location : @navigation.Location = { device: "local", target: Settings, }
  let observed : NavigationObservation = {
    location: Some(location),
    user_visit: false,
    session_rotated: false,
    explicit: false,
    repeat_visit: false,
    promotion: None,
    durable: [],
  }
  let navigation = { ..AppNavigation::empty(), location: Some(location), }
  assert_true(observed.write(navigation, 0, desktop=true) is Keep)
  let foreground = { ..observed, explicit: true, repeat_visit: true, }
  assert_true(foreground.write(navigation, 0, desktop=true) is Push(_))
  assert_true(foreground.write(navigation, 0, desktop=true) is Push(_))
  let pending = { ..navigation, new_chat_requested: true, revision: 1, }
  assert_true(foreground.write(pending, 0, desktop=true) is Keep)
  assert_true(
    observed.write(AppNavigation::empty(), 0, desktop=true) is Replace(_),
  )
  assert_true(observed.write(AppNavigation::empty(), 0, desktop=false) is Keep)
}

///|
test "blank draft addressing does not turn an explicit visit into replacement" {
  let observed : NavigationObservation = {
    location: Some({ device: "local", target: ChatDraft("draft"), }),
    user_visit: false,
    session_rotated: false,
    explicit: false,
    repeat_visit: false,
    promotion: None,
    durable: [],
  }
  let navigation = {
    ..AppNavigation::empty(),
    location: Some({ device: "local", target: ChatNew, }),
  }
  assert_true(observed.addresses_blank(navigation))
  assert_true(observed.addresses_blank(navigation))
  assert_false({ ..observed, user_visit: true, }.addresses_blank(navigation))
  assert_false(
    { ..observed, session_rotated: true, }.addresses_blank(navigation),
  )
}
