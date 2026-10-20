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
  let (_, home) = apply_browser_navigation(
    dispatch,
    { path: "/cloud", settings: false, can_back: false, can_forward: false, },
    initial,
  )
  let (_, rotated) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "desktop-test", }),
    home,
  )
  assert_true(rotated.cloud_selected() && rotated.cloud_identity() is None)
  assert_true(rotated.selected_conversation is None)
  let (_, rotated_again) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "desktop-test", }),
    home,
  )
  assert_true(rotated.navigation == rotated_again.navigation)
  assert_true(home.selected_conversation is None)
}

///|
test "deep link waits for successful catalogs and does not confuse failure with absence" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model(),
    navigation: {
      ..AppNavigation::empty(),
      location: Some({ device: Some("local"), target: Session("missing"), }),
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
          owner: @interop.Host({ channel: Local, session: "local-draft", }),
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
    owner: @interop.Host({ channel: Local, session: blank.active_session, }),
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
  let expired : @routes.Location = {
    device: Some("local"),
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
  assert_true(fresh.host_selection() is Some({ session: "fresh", .. }))
  assert_true(fresh.active_conversation() is Some(conv) && conv.draft_empty())
  assert_true(!fresh.navigation.can_back)
  assert_true(
    fresh.find_conversation(Local, "desktop-test") is Some(conv) &&
    conv.task == "Keep existing input",
  )
}

///|
test "navigation write policy distinguishes foreground visits and background identity updates" {
  let location : @routes.Location = { device: Some("local"), target: Settings, }
  let observed : NavigationObservation = {
    location: Some(location),
    user_visit: false,
    session_rotated: false,
    explicit: false,
    repeat_visit: false,
    retired: [],
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
    location: Some({ device: Some("local"), target: ChatDraft("draft"), }),
    user_visit: false,
    session_rotated: false,
    explicit: false,
    repeat_visit: false,
    retired: [],
    promotion: None,
    durable: [],
  }
  let navigation = {
    ..AppNavigation::empty(),
    location: Some({ device: Some("local"), target: ChatNew, }),
  }
  assert_true(observed.addresses_blank(navigation))
  assert_true(observed.addresses_blank(navigation))
  assert_false({ ..observed, user_visit: true, }.addresses_blank(navigation))
  assert_false(
    { ..observed, session_rotated: true, }.addresses_blank(navigation),
  )
}

///|
test "deleting the shown conversation from this page returns to a draft" {
  let dispatch = test_dispatch()
  let key : ArchiveRecordKey = {
    session: "desktop-test",
    workspace: @interop.ChannelId::Local.test_project(),
  }
  let shown : @routes.Location = {
    device: Some("local"),
    target: Session("desktop-test"),
  }
  // The browser page and the desktop window share this navigation.
  for desktop in [false, true] {
    let base = {
      ..test_model().with_dev(dev => {
        ..dev,
        sessions: [placed_archived_item("desktop-test")],
      }),
      is_desktop: desktop,
      navigation: {
        ..AppNavigation::empty(),
        location: Some(shown),
        phase: Active,
        history: @navigation.History::empty().visit(shown, replace=true),
      },
    }
    let deleted = SessionsChanged(
      change="deleted",
      key~,
      fresh_session=Some("fresh"),
    )
    // Another client's delete keeps the requested identity and its
    // unavailable state, also while this page is only asking what a delete
    // would remove, or after its own delete was refused.
    let (_, remote) = update_dev(dispatch, deleted, base)
    assert_true(remote.navigation.location == Some(shown))
    assert_true(!(remote.navigation.phase is Active))
    let (_, asked) = update(
      dispatch,
      DeleteSession(@interop.ChannelId::Local, key, LiveRecord),
      base,
    )
    let (_, remote) = update_dev(dispatch, deleted, asked)
    assert_true(remote.navigation.location == Some(shown))
    let (_, staged) = update_dev(
      dispatch,
      DeleteChecked(key~, checkout=None),
      asked,
    )
    let (_, confirmed) = update(dispatch, ConfirmDeleteSession, staged)
    let (_, refused) = update_dev(
      dispatch,
      DeleteFailed("busy", deleting=Some(key)),
      confirmed,
    )
    assert_true(refused.deletes_in_flight.is_empty())
    let (_, remote) = update_dev(dispatch, deleted, refused)
    assert_true(remote.navigation.location == Some(shown))
    let (_, own) = update_dev(dispatch, deleted, confirmed)
    assert_true(own.deletes_in_flight.is_empty())
    assert_true(own.navigation.location is Some({ target: ChatNew, .. }))
    assert_true(own.navigation.phase is Active)
    assert_eq(own.active_session, "fresh")
    assert_true(own.active_conversation() is Some(conv) && conv.draft_empty())
    assert_true(own.navigation.history.current() == own.navigation.location)
  }
}

///|
test "deleting the shown archived conversation returns to a draft" {
  let dispatch = test_dispatch()
  let key : ArchiveRecordKey = {
    session: "desktop-test",
    workspace: @interop.ChannelId::Local.test_project(),
  }
  let shown : @routes.Location = {
    device: Some("local"),
    target: Session("desktop-test"),
  }
  let item = placed_archived_item("desktop-test")
  let base = {
    ..test_model()
    .replace_conversation({ ..test_conversation(), record: ArchivedRecord, })
    .with_dev(dev => { ..dev, archived: [item], }),
    navigation: {
      ..AppNavigation::empty(),
      location: Some(shown),
      phase: Active,
      history: @navigation.History::empty().visit(shown, replace=true),
    },
  }
  let (_, staged) = update(
    dispatch,
    DeleteSession(@interop.ChannelId::Local, key, ArchivedRecord),
    base,
  )
  let (_, confirmed) = update(dispatch, ConfirmDeleteSession, staged)
  let dev = confirmed.dev()
  let (_, deleted) = update_dev(
    dispatch,
    ArchivedDeleted(
      key~,
      sessions=["desktop-test"],
      items=[],
      connection_generation=dev.connection_generation,
      request_generation=dev.archived_request_generation,
      fresh_session="fresh",
    ),
    confirmed,
  )
  assert_true(deleted.navigation.location is Some({ target: ChatNew, .. }))
  assert_true(deleted.navigation.phase is Active)
  assert_eq(deleted.active_session, "fresh")
}

///|
test "a confirmed delete stays this page's own across later delete clicks" {
  let dispatch = test_dispatch()
  let key : ArchiveRecordKey = {
    session: "desktop-test",
    workspace: @interop.ChannelId::Local.test_project(),
  }
  let other : ArchiveRecordKey = { ..key, session: "desktop-other", }
  let shown : @routes.Location = {
    device: Some("local"),
    target: Session("desktop-test"),
  }
  let base = {
    ..test_model().with_dev(dev => {
      ..dev,
      sessions: [
        placed_archived_item("desktop-test"),
        placed_archived_item("desktop-other"),
      ],
    }),
    navigation: {
      ..AppNavigation::empty(),
      location: Some(shown),
      phase: Active,
      history: @navigation.History::empty().visit(shown, replace=true),
    },
  }
  let ask = (model, key) => {
    let (_, asked) = update(
      dispatch,
      DeleteSession(@interop.ChannelId::Local, key, LiveRecord),
      model,
    )
    asked
  }
  let confirm = (model, key) => {
    let (_, staged) = update_dev(
      dispatch,
      DeleteChecked(key~, checkout=None),
      ask(model, key),
    )
    let (_, confirmed) = update(dispatch, ConfirmDeleteSession, staged)
    confirmed
  }
  let deleted = SessionsChanged(
    change="deleted",
    key~,
    fresh_session=Some("fresh"),
  )
  // Asking about another chat before the shown one's deletion is announced
  // keeps that deletion this page's own.
  let (_, own) = update_dev(dispatch, deleted, ask(confirm(base, key), other))
  assert_true(own.navigation.location is Some({ target: ChatNew, .. }))
  // Deleting the same chat again while the first delete is out: the first
  // one's refusal ends only itself.
  let twice = confirm(confirm(base, key), key)
  assert_eq(twice.deletes_in_flight.length(), 2)
  let (_, refused) = update_dev(
    dispatch,
    DeleteFailed("busy", deleting=Some(key)),
    twice,
  )
  let (_, own) = update_dev(dispatch, deleted, refused)
  assert_true(own.navigation.location is Some({ target: ChatNew, .. }))
  assert_true(own.deletes_in_flight.is_empty())
  // A delete the host stops ends that request and asks again.
  let (_, stopped) = update_dev(
    dispatch,
    DeleteStopped(key~, checkout={
      worktree: "wt-1",
      dirty_paths: [],
      dirty_path_count: 0,
    }),
    confirm(base, key),
  )
  assert_true(stopped.deletes_in_flight.is_empty())
  assert_true(
    stopped.delete_confirm is Some(HostDelete({ key: k, .. })) && k == key,
  )
  // A refused check ends no delete and leaves the latest click's question
  // out, so a repeated click on the same chat still opens its dialog.
  let again = ask(ask(ask(base, key), other), key)
  let (_, late) = update_dev(
    dispatch,
    DeleteFailed("busy", deleting=None),
    again,
  )
  let (_, staged) = update_dev(
    dispatch,
    DeleteChecked(key~, checkout=None),
    late,
  )
  assert_true(
    staged.delete_confirm is Some(HostDelete({ key: k, .. })) && k == key,
  )
}

///|
test "a retired entry yields only to the draft that replaced it" {
  let dispatch = test_dispatch()
  let shown : @routes.Location = {
    device: Some("local"),
    target: Session("desktop-test"),
  }
  let navigation = { ..AppNavigation::empty(), location: Some(shown), }
  let observed : NavigationObservation = {
    location: Some({ device: Some("local"), target: ChatNew, }),
    user_visit: false,
    session_rotated: false,
    explicit: false,
    repeat_visit: false,
    retired: ["desktop-test"],
    promotion: None,
    durable: [],
  }
  assert_true(observed.write(navigation, 0, desktop=false) is Replace(_))
  let unrelated = {
    ..observed,
    location: Some({ device: Some("local"), target: Session("desktop-other"), }),
  }
  assert_true(unrelated.write(navigation, 0, desktop=false) is Keep)
  // A delete reply the update discards as stale moves nothing.
  let key : ArchiveRecordKey = {
    session: "desktop-test",
    workspace: @interop.ChannelId::Local.test_project(),
  }
  let base = {
    ..test_model()
    .replace_conversation({ ..test_conversation(), record: ArchivedRecord, })
    .with_dev(dev => {
      ..dev,
      archived: [placed_archived_item("desktop-test")],
      archived_request_generation: 2,
    }),
    navigation: {
      ..AppNavigation::empty(),
      location: Some(shown),
      phase: Active,
      history: @navigation.History::empty().visit(shown, replace=true),
    },
  }
  let dev = base.dev()
  let reply = request_generation => {
    on_home(
      ArchivedDeleted(
        key~,
        sessions=["desktop-test"],
        items=[],
        connection_generation=dev.connection_generation,
        request_generation~,
        fresh_session="fresh",
      ),
    )
  }
  assert_true(observe_navigation(reply(1), base, base).retired.is_empty())
  assert_true(
    observe_navigation(reply(2), base, base).retired == ["desktop-test"],
  )
  let (_, stale) = update(dispatch, reply(1), base)
  assert_true(stale.navigation.location == Some(shown))
}
