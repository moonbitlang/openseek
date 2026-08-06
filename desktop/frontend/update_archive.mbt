// Archive-list invalidation and archived-conversation transitions.

///|
const ArchivedPendingInputNotice : String = "This conversation was archived while a prompt was being sent. The input was restored here; check the archived transcript before resubmitting."

///|
/// The archived list is fetched independently from the live list and keeps
/// its own token, so a newer live-only refresh does not invalidate a useful
/// archived reply.
fn request_archived_refresh(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  model : Model,
) -> (@cmd.Cmd, Model) {
  guard model.device_state(channel) is Some(dev) else {
    return (@cmd.none, model)
  }
  let request_generation = dev.archived_request_generation + 1
  (
    fetch_archived(
      dispatch,
      channel,
      dev.connection_generation,
      request_generation,
    ),
    model.replace_device({
      ..dev,
      archived_request_generation: request_generation,
    }),
  )
}

///|
/// Leave an archived active session immediately, carrying only resubmittable
/// composer state into the supplied fresh id. This is shared by list replies
/// and identity notifications because either can win their delivery race.
fn replace_archived_active(
  model : Model,
  channel : @interop.ChannelId,
  session : String,
  fresh_session : String,
  workspace : @common.Uri?,
) -> Model {
  guard channel == model.focused &&
    model.active_session == session &&
    model.find_conversation(channel, session) is Some(archived_conv) else {
    return model
  }
  let (restored_task, restored_mentions, pending_initial) = archived_conv.archive_salvage()
  let conversations = model.conversations.filter(conv => {
    conv.device != channel || conv.session_id != session
  })
  let activated = { ..model, conversations, }.activate(channel, fresh_session)
  let fresh = activated.active()
  let task = if fresh.task.is_empty() {
    restored_task
  } else if restored_task.is_empty() || fresh.task == restored_task {
    fresh.task
  } else {
    restored_task + "\n\n" + fresh.task
  }
  let mentions = restored_mentions
  for mention in fresh.mentions {
    mentions.push(mention)
  }
  let fresh = { ..fresh, task, mentions, workspace }
  let fresh = if pending_initial {
    fresh.append_local_notice(
      Assistant(is_danger=true),
      ArchivedPendingInputNotice,
    )
  } else {
    fresh
  }
  {
    ..activated.replace_conversation(fresh).with_active_workspace(workspace),
    screen: Chat,
    loading_conversation: None,
    transcript_pinned: true,
    completion: None,
  }
}

///|
fn archived_loaded(
  items : Array[@transcript.SessionListItem],
  request_generation? : Int = 0,
) -> Msg {
  on_home(
    ArchivedLoaded(
      items,
      connection_generation=0,
      request_generation~,
      fresh_session="desktop-archive-replacement",
    ),
  )
}

///|
fn archived_item(id : String) -> @transcript.SessionListItem {
  { id, title: Some(""), workspace: None, workspace_name: "" }
}

///|
test "session.changed decoder preserves archive invalidation identity" {
  guard session_changed_msg({ change: "archived", session: "desktop-old" })
    is Some(
      SessionsChanged(
        change="archived",
        session="desktop-old",
        fresh_session=Some(_)
      )
    ) else {
    fail("archive invalidation was not decoded")
  }
}

///|
test "archive broadcast invalidates the active send target before list replies" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/work/archived")
  let mention : Mention = { ref_: Skill(name="draft-skill"), range: None }
  let model = test_model()
    .replace_conversation({
      ..test_conversation(),
      task: "must not target archived session",
      mentions: [mention],
    })
    .with_dev(dev => {
      ..dev,
      sessions: [
        {
          ..archived_item("desktop-test"),
          workspace: Some(workspace),
          workspace_name: "archived",
        },
      ],
      worktrees: [{ workspace, rows: [], generation: 1 }],
    })
  let (_, invalidated) = update_dev(
    dispatch,
    SessionsChanged(
      change="archived",
      session="desktop-test",
      fresh_session=Some("desktop-fresh"),
    ),
    model,
  )
  inspect(invalidated.active_session, content="desktop-fresh")
  assert_true(
    invalidated.find_conversation(@interop.ChannelId::Local, "desktop-test")
    is None,
  )
  inspect(invalidated.active().session_id, content="desktop-fresh")
  assert_eq(invalidated.dev().active_workspace, Some(workspace))
  assert_eq(invalidated.active().workspace, Some(workspace))
  inspect(invalidated.active().task, content="must not target archived session")
  inspect(invalidated.active().mentions.length(), content="1")
  assert_true(
    invalidated.active().mentions[0].ref_ is Skill(name="draft-skill"),
  )
  assert_true(
    invalidated.dev().archived.iter().any(item => item.id == "desktop-test"),
  )
  assert_false(
    invalidated.dev().sessions.iter().any(item => item.id == "desktop-test"),
  )
  // Even before either sidebar refresh returns, the next submit belongs to
  // the replacement conversation; no live state can target the archived id.
  let (_, drafted) = update(
    dispatch,
    TaskChanged("safe replacement"),
    invalidated,
  )
  let (_, sent) = update(dispatch, Send, drafted)
  inspect(sent.active_session, content="desktop-fresh")
  inspect(sent.active().session_id, content="desktop-fresh")
  assert_true(sent.active().run is Starting(..))
  assert_true(
    sent.find_conversation(@interop.ChannelId::Local, "desktop-test") is None,
  )
}

///|
test "an archive response arriving before its notification preserves the draft once" {
  let dispatch = test_dispatch()
  let model = test_model()
    .replace_conversation({ ..test_conversation(), task: "keep this draft" })
    .with_dev(dev => { ..dev, sessions: [archived_item("desktop-test")] })
  let (_, responded) = update(
    dispatch,
    archived_loaded([archived_item("desktop-test")]),
    model,
  )
  inspect(responded.active_session, content="desktop-archive-replacement")
  inspect(responded.active().task, content="keep this draft")
  let (_, notified) = update_dev(
    dispatch,
    SessionsChanged(
      change="archived",
      session="desktop-test",
      fresh_session=Some("desktop-notification-replacement"),
    ),
    responded,
  )
  // The late duplicate only refreshes the tombstone; it cannot rotate the
  // already-safe composer a second time or lose its recovered text.
  inspect(notified.active_session, content="desktop-archive-replacement")
  inspect(notified.active().task, content="keep this draft")
  inspect(notified.active().overlay.length(), content="0")
}

///|
test "archiving a pending start restores its original composer without ownership" {
  let dispatch = test_dispatch()
  let sent_mention : Mention = { ref_: Skill(name="sent-skill"), range: None }
  let newer_mention : Mention = { ref_: Skill(name="newer-skill"), range: None }
  let pending = test_conversation().enqueue_input(
    InitialPrompt,
    "pending-start",
    None,
    "serialized prompt",
    "original draft",
    [sent_mention],
  )
  let model = test_model()
    .replace_conversation({
      ..pending,
      run: Starting(submission_id="pending-start"),
      task: "typed afterward",
      mentions: [newer_mention],
    })
    .with_dev(dev => { ..dev, sessions: [archived_item("desktop-test")] })
  let (_, next) = update_dev(
    dispatch,
    SessionsChanged(
      change="archived",
      session="desktop-test",
      fresh_session=Some("desktop-restored"),
    ),
    model,
  )
  inspect(next.active_session, content="desktop-restored")
  inspect(next.active().task, content="original draft\n\ntyped afterward")
  inspect(next.active().mentions.length(), content="2")
  assert_true(next.active().run is NoRun(ended=None))
  inspect(next.active().input_ledger.length(), content="0")
  inspect(next.active().overlay.length(), content="1")
  inspect(next.active().overlay[0].content, content=ArchivedPendingInputNotice)
  assert_true(next.active().overlay[0].reconciliation is Retained)
}

///|
test "an archive notification wins over a stale live-list reply" {
  let dispatch = test_dispatch()
  let item = archived_item("desktop-test")
  let model = test_model().with_dev(dev => { ..dev, sessions: [item] })
  let (_, invalidated) = update_dev(
    dispatch,
    SessionsChanged(
      change="archived",
      session="desktop-test",
      fresh_session=Some("desktop-safe"),
    ),
    model,
  )
  let (_, stale) = update(
    dispatch,
    sessions_loaded([item], request_generation=1),
    invalidated,
  )
  assert_false(
    stale.dev().sessions.iter().any(current => current.id == item.id),
  )
  assert_true(stale.dev().archived.iter().any(current => current.id == item.id))
  inspect(stale.active_session, content="desktop-safe")
}

///|
test "a background archive removes only its channel's same-id conversation" {
  let dispatch = test_dispatch()
  let remote : @interop.ChannelId = Remote("d-remote")
  let local_conv = {
    ..empty_conversation(@interop.ChannelId::Local, "shared"),
    messages: [{ kind: User, content: "local", ts: None }],
  }
  let remote_conv = {
    ..empty_conversation(remote, "shared"),
    messages: [{ kind: User, content: "remote", ts: None }],
  }
  let model = {
    ..test_model(),
    devices: [
      { ..empty_device_state(@interop.ChannelId::Local), bridge: Connected },
      { ..empty_device_state(remote), bridge: Connected },
    ],
    active_session: "shared",
    conversations: [local_conv, remote_conv],
  }
  let (_, next) = update(
    dispatch,
    FromDevice(
      remote,
      ArchivedLoaded(
        [archived_item("shared")],
        connection_generation=0,
        request_generation=0,
        fresh_session="remote-fresh",
      ),
    ),
    model,
  )
  assert_true(next.focused is Local)
  inspect(next.active_session, content="shared")
  guard next.find_conversation(@interop.ChannelId::Local, "shared")
    is Some(kept) else {
    fail("the focused same-id conversation was removed")
  }
  inspect(kept.messages[0].content, content="local")
  assert_true(next.find_conversation(remote, "shared") is None)
}

///|
test "an unarchive notification wins over a stale archived-list reply" {
  let dispatch = test_dispatch()
  let item = archived_item("desktop-old")
  let model = test_model().with_dev(dev => { ..dev, archived: [item] })
  let (_, restored) = update_dev(
    dispatch,
    SessionsChanged(
      change="unarchived",
      session="desktop-old",
      fresh_session=None,
    ),
    model,
  )
  let (_, stale) = update(
    dispatch,
    archived_loaded([item], request_generation=1),
    restored,
  )
  assert_false(
    stale.dev().archived.iter().any(current => current.id == item.id),
  )
  assert_true(stale.dev().sessions.iter().any(current => current.id == item.id))
}

///|
test "BridgeReady replaces archive overrides with fresh-list truth" {
  let dispatch = test_dispatch()
  let item = archived_item("desktop-old")
  let model = test_model()
    .with_archive_override(@interop.ChannelId::Local, "desktop-old", true)
    .with_dev(dev => { ..dev, archived: [item] })
  let (_, ready) = update_dev(dispatch, BridgeReady, model)
  inspect(ready.dev().connection_generation, content="1")
  inspect(ready.dev().archive_overrides.length(), content="0")
  let (_, live) = update_dev(
    dispatch,
    SessionsLoaded([item], connection_generation=1, request_generation=1),
    ready,
  )
  let (_, reconciled) = update_dev(
    dispatch,
    ArchivedLoaded(
      [],
      connection_generation=1,
      request_generation=1,
      fresh_session="desktop-unused",
    ),
    live,
  )
  assert_true(
    reconciled.dev().sessions.iter().any(current => current.id == item.id),
  )
  inspect(reconciled.dev().archived.length(), content="0")
  let (_, stale) = update_dev(
    dispatch,
    ArchivedLoaded(
      [item],
      connection_generation=0,
      request_generation=1,
      fresh_session="desktop-stale",
    ),
    reconciled,
  )
  inspect(stale.dev().archived.length(), content="0")
}

///|
test "an older same-connection live list cannot replace a newer reply" {
  let dispatch = test_dispatch()
  let old : @transcript.SessionListItem = {
    id: "desktop-listed",
    title: Some("old title"),
    workspace: None,
    workspace_name: "",
  }
  let current = { ..old, title: Some("current title") }
  let model = test_model().with_dev(dev => {
    ..dev,
    sessions_request_generation: 2,
  })
  let (_, newest) = update_dev(
    dispatch,
    SessionsLoaded([current], connection_generation=0, request_generation=2),
    model,
  )
  let (_, stale) = update_dev(
    dispatch,
    SessionsLoaded([old], connection_generation=0, request_generation=1),
    newest,
  )
  inspect(stale.dev().sessions.length(), content="1")
  assert_true(stale.dev().sessions[0].title is Some("current title"))
}

///|
test "an older same-connection archived list cannot replace a newer reply" {
  let dispatch = test_dispatch()
  let old : @transcript.SessionListItem = {
    id: "desktop-archived",
    title: Some("old title"),
    workspace: None,
    workspace_name: "",
  }
  let current = { ..old, title: Some("current title") }
  let model = test_model().with_dev(dev => {
    ..dev,
    archived_request_generation: 2,
  })
  let (_, newest) = update_dev(
    dispatch,
    ArchivedLoaded(
      [current],
      connection_generation=0,
      request_generation=2,
      fresh_session="desktop-unused",
    ),
    model,
  )
  let (_, stale) = update_dev(
    dispatch,
    ArchivedLoaded(
      [old],
      connection_generation=0,
      request_generation=1,
      fresh_session="desktop-unused",
    ),
    newest,
  )
  inspect(stale.dev().archived.length(), content="1")
  assert_true(stale.dev().archived[0].title is Some("current title"))
}

///|
test "an archived background session drops its live state, active stays" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model(),
    conversations: [
      test_conversation(),
      empty_conversation(@interop.ChannelId::Local, "desktop-old"),
    ],
  }
  let (_, next) = update(
    dispatch,
    archived_loaded([archived_item("desktop-old")]),
    model,
  )
  inspect(next.dev().archived.length(), content="1")
  inspect(next.dev().archived[0].id, content="desktop-old")
  assert_true(
    next.find_conversation(@interop.ChannelId::Local, "desktop-old") is None,
  )
  inspect(next.active_session, content="desktop-test")
}

///|
test "an archived-list reply immediately replaces the active conversation" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    archived_loaded([archived_item("desktop-test")]),
    test_model(),
  )
  assert_true(
    next.find_conversation(@interop.ChannelId::Local, "desktop-test") is None,
  )
  inspect(next.active_session, content="desktop-archive-replacement")
  inspect(next.dev().archived[0].id, content="desktop-test")
}

///|
test "an archive failure pops a toast that a click or its timer dismisses" {
  let dispatch = test_dispatch()
  let (_, failed) = update_dev(
    dispatch,
    ArchiveFailed("zip missing"),
    test_model(),
  )
  inspect(failed.notifications.length(), content="1")
  inspect(
    failed.notifications[0].message,
    content="Archive failed: zip missing",
  )
  let id = failed.notifications[0].id
  // A stale timer (the toast is already gone) must not touch a later toast.
  let (_, dismissed) = update(dispatch, DismissNotification(id), failed)
  inspect(dismissed.notifications.length(), content="0")
  let (_, again) = update_dev(
    dispatch,
    ArchiveFailed("still missing"),
    dismissed,
  )
  let (_, expired) = update(dispatch, NotificationExpired(id), again)
  inspect(expired.notifications.length(), content="1")
  inspect(
    expired.notifications[0].message,
    content="Archive failed: still missing",
  )
}

///|
test "toast ids only ever grow, so timers and toasts stay paired" {
  let dispatch = test_dispatch()
  let (_, first) = update_dev(dispatch, ArchiveFailed("one"), test_model())
  let (_, second) = update_dev(dispatch, SessionsFailed("two"), first)
  inspect(second.notifications.length(), content="2")
  assert_true(second.notifications[0].id != second.notifications[1].id)
  inspect(second.notification_seq, content="2")
}
