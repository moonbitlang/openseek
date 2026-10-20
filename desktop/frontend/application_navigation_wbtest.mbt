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
fn deletion_key(session : String) -> ArchiveRecordKey {
  { session, workspace: @interop.ChannelId::Local.test_project(), }
}

///|
/// A page showing `shown` from `record`'s store, with `sessions` live and
/// `archived` rows listed in the fixture project.
fn deletion_model(
  shown : String,
  record~ : ConversationRecord = LiveRecord,
  sessions~ : Array[String] = [],
  archived~ : Array[String] = [],
  desktop~ : Bool = false,
) -> Model raise {
  let location : @routes.Location = {
    device: Some("local"),
    target: Session(shown),
  }
  {
    ..test_model()
    .replace_conversation({
      ..empty_conversation(
        @interop.ChannelId::Local,
        shown,
        @interop.ChannelId::Local.test_project(),
      ),
      record,
    })
    .with_dev(dev => {
      ..dev,
      sessions: sessions.map(placed_archived_item),
      archived: archived.map(placed_archived_item),
    }),
    is_desktop: desktop,
    active_session: shown,
    navigation: {
      ..AppNavigation::empty(),
      location: Some(location),
      phase: Active,
      history: @navigation.History::empty().visit(location, replace=true),
    },
  }
}

///|
/// Click Delete on `key`'s row and confirm the dialog. A live row first gets
/// the host's answer about what goes with it.
fn confirm_host_delete(
  model : Model,
  key : ArchiveRecordKey,
  record~ : ConversationRecord = LiveRecord,
) -> Model {
  let dispatch = test_dispatch()
  let (_, asked) = update(
    dispatch,
    DeleteSession(@interop.ChannelId::Local, key, record),
    model,
  )
  let staged = if record is LiveRecord {
    update_dev(dispatch, DeleteChecked(key~, checkout=None), asked).1
  } else {
    asked
  }
  update(dispatch, ConfirmDeleteSession, staged).1
}

///|
/// The host's `session.changed` deletion of `key`.
fn announce_deletion(model : Model, key : ArchiveRecordKey) -> Model {
  update_dev(
    test_dispatch(),
    SessionsChanged(change="deleted", key~, fresh_session=Some("fresh")),
    model,
  ).1
}

///|
fn shows_new_draft(model : Model) -> Bool {
  model.navigation.location is Some({ target: ChatNew, .. }) &&
  model.navigation.phase is Active &&
  model.navigation.history.current() == model.navigation.location
}

///|
test "deleting the shown conversation from this page returns to a draft" {
  let dispatch = test_dispatch()
  let key = deletion_key("desktop-test")
  // The browser page and the desktop window share this navigation.
  for desktop in [false, true] {
    let live = deletion_model("desktop-test", sessions=[key.session], desktop~)
    let own = announce_deletion(confirm_host_delete(live, key), key)
    assert_true(shows_new_draft(own))
    assert_eq(own.active_session, "fresh")
    assert_true(own.active_conversation() is Some(conv) && conv.draft_empty())
  }
  // An archived delete is announced while the host commits it, usually
  // before its reply, which the announcement then makes stale.
  let archived = confirm_host_delete(
    deletion_model("desktop-test", record=ArchivedRecord, archived=[key.session]),
    key,
    record=ArchivedRecord,
  )
  let dev = archived.dev()
  let reply_at = request_generation => {
    ArchivedDeleted(
      key~,
      sessions=[key.session],
      items=[],
      connection_generation=dev.connection_generation,
      request_generation~,
      fresh_session="fresh",
    )
  }
  let reply = reply_at(dev.archived_request_generation)
  let announced = announce_deletion(archived, key)
  assert_true(shows_new_draft(announced))
  let (_, late) = update_dev(dispatch, reply, announced)
  assert_true(late.navigation == announced.navigation)
  // The reply can also arrive first.
  let (_, replied) = update_dev(dispatch, reply, archived)
  assert_true(shows_new_draft(replied))
  // A stale reply the update discards moves nothing.
  let stale = reply_at(dev.archived_request_generation - 1)
  assert_true(
    observe_navigation(on_home(stale), archived, archived).retired.is_empty(),
  )
}

///|
test "a deletion this page did not confirm keeps the unavailable target" {
  let dispatch = test_dispatch()
  let key = deletion_key("desktop-test")
  let base = deletion_model("desktop-test", sessions=[key.session])
  let kept = (model : Model) => {
    model.navigation.location == base.navigation.location
  }
  // Another client deletes it with no delete from this page, while this
  // page only asks what a delete would remove, or after this page's own
  // delete was refused.
  assert_true(kept(announce_deletion(base, key)))
  let (_, asked) = update(
    dispatch,
    DeleteSession(@interop.ChannelId::Local, key, LiveRecord),
    base,
  )
  assert_true(kept(announce_deletion(asked, key)))
  let (_, refused) = update_dev(
    dispatch,
    DeleteFailed("busy", deleting=Some(key)),
    confirm_host_delete(base, key),
  )
  assert_true(refused.deletes_in_flight.is_empty())
  assert_true(kept(announce_deletion(refused, key)))
  // The host deletes a family from one store only: a child archived apart
  // from its live parent is not part of the parent's delete.
  let parent = deletion_key("desktop-parent")
  let child = deletion_key("desktop-parent-sr-1")
  let apart = confirm_host_delete(
    deletion_model(
      child.session,
      record=ArchivedRecord,
      sessions=[parent.session],
      archived=[child.session],
    ),
    parent,
  )
  let elsewhere = announce_deletion(apart, child)
  assert_true(elsewhere.navigation.location == apart.navigation.location)
}

///|
test "each confirmed delete settles only itself" {
  let dispatch = test_dispatch()
  let key = deletion_key("desktop-test")
  let other = deletion_key("desktop-other")
  let base = deletion_model("desktop-test", sessions=[
    key.session,
    other.session,
  ])
  // A later click on another chat does not take over the confirmed delete.
  let (_, asked_other) = update(
    dispatch,
    DeleteSession(@interop.ChannelId::Local, other, LiveRecord),
    confirm_host_delete(base, key),
  )
  assert_true(shows_new_draft(announce_deletion(asked_other, key)))
  // Deleting the same chat twice: the first one's refusal ends only itself.
  let twice = confirm_host_delete(confirm_host_delete(base, key), key)
  assert_eq(twice.deletes_in_flight.length(), 2)
  let (_, refused) = update_dev(
    dispatch,
    DeleteFailed("busy", deleting=Some(key)),
    twice,
  )
  let own = announce_deletion(refused, key)
  assert_true(shows_new_draft(own))
  assert_true(own.deletes_in_flight.is_empty())
  // A delete the host stops ends that request and asks again.
  let (_, stopped) = update_dev(
    dispatch,
    DeleteStopped(key~, checkout={
      worktree: "wt-1",
      dirty_paths: [],
      dirty_path_count: 0,
    }),
    confirm_host_delete(base, key),
  )
  assert_true(stopped.deletes_in_flight.is_empty())
  assert_true(
    stopped.delete_confirm is Some(HostDelete({ key: k, .. })) && k == key,
  )
  // A refused check ends no delete and leaves the latest click's question
  // out, so its dialog still opens.
  let mut asked = base
  for clicked in [key, other, key] {
    asked = update(
        dispatch,
        DeleteSession(@interop.ChannelId::Local, clicked, LiveRecord),
        asked,
      ).1
  }
  let (_, late) = update_dev(
    dispatch,
    DeleteFailed("busy", deleting=None),
    asked,
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
test "deleting a family from this page retires its shown descendant" {
  let dispatch = test_dispatch()
  let parent = deletion_key("desktop-parent")
  let child = deletion_key("desktop-parent-sr-1")
  // The child was opened from a transcript link before the catalog listed
  // it; the host still deletes it with its parent.
  let confirmed = confirm_host_delete(
    deletion_model(child.session, sessions=[parent.session]),
    parent,
  )
  // A catalog read can land after the host removed the records but before
  // it announces them, one descendant at a time before the parent.
  let dev = confirmed.dev()
  let (_, refreshed) = update_dev(
    dispatch,
    SessionsLoaded(
      [],
      connection_generation=dev.connection_generation,
      request_generation=dev.sessions_request_generation,
    ),
    confirmed,
  )
  let child_gone = announce_deletion(refreshed, child)
  assert_true(shows_new_draft(child_gone))
  let parent_gone = announce_deletion(child_gone, parent)
  assert_true(parent_gone.deletes_in_flight.is_empty())
  assert_true(parent_gone.navigation == child_gone.navigation)
  // Descent follows the `-sr-N` structure, not a textual prefix.
  assert_true(
    is_subrun_descendant("desktop-parent-sr-1-sr-2", "desktop-parent"),
  )
  assert_false(
    is_subrun_descendant("desktop-parent-sr-other", "desktop-parent"),
  )
  assert_false(is_subrun_descendant("desktop-parent-copy", "desktop-parent"))
  assert_false(is_subrun_descendant("desktop-parent", "desktop-parent"))
}
