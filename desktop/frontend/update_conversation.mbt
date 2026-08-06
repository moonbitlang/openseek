// Conversation selection, rotation, and stored-list transitions.

///|
/// Move the UI's focus to `channel`: refetch the focused-scoped mirrors
/// that BridgeReady only loads for the then-focused device (host settings,
/// installed skills) and reset their local bookkeeping, so
/// nothing of the previous device's host bleeds through. The active
/// conversation is the caller's to place afterwards (an activation or a
/// rotation); until it does, nothing is selected. A no-op when focus is
/// already there — or when the page does not hold the channel.
fn focus_channel(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  channel : @interop.ChannelId,
) -> (@cmd.Cmd, Model) {
  guard channel != model.focused && model.device_state(channel) is Some(dev) else {
    return (@cmd.none, model)
  }
  (
    @cmd.batch([
      fetch_host_settings(dispatch, channel, dev.connection_generation),
      fetch_installed_skills(dispatch, channel),
    ]),
    {
      ..model.clear_host_settings(),
      focused: channel,
      active_session: "",
      loading_conversation: None,
      installed_skills: [],
      completion: None,
      // Forgetting what was watched makes the post-dispatch panel sync
      // re-root `fs.watch` against the newly focused host.
      file_panel: { ..model.file_panel, watching: None },
    },
  )
}

///|
/// The OpenSession body against an explicit channel — the caller has
/// already moved focus there, so `channel == model.focused` throughout.
fn open_session_on(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  model : Model,
  session_id : String,
) -> (@cmd.Cmd, Model) {
  let owner : @interop.ConversationKey = { channel, session: session_id }
  if session_id == model.active_session {
    let base = { ..model, screen: Chat, completion: None }
    // Re-selecting is an explicit catch-up point for writes made by an
    // idle CLI or another client. It also restarts an exhausted retry
    // round; an existing request stays single-flight. A fresh chat has no
    // durable record to read, including when returning here from Skills.
    match model.find_conversation(channel, session_id) {
      Some(conv) if !(conv.sync is Reloading(..)) &&
        model.can_reload_transcript(conv) => {
        let (next, generation) = base.begin_transcript_reload(conv)
        let next = { ..next, loading_conversation: Some(owner) }
        if generation is Some(generation) {
          (
            session_snapshot_command(
              dispatch, channel, next, session_id, generation, true,
            ),
            next,
          )
        } else {
          (@cmd.none, next)
        }
      }
      _ =>
        (
          @cmd.none,
          {
            ..base,
            loading_conversation: if base.loading_conversation == Some(owner) {
              Some(owner)
            } else {
              None
            },
          },
        )
    }
  } else if model.find_conversation(channel, session_id) is Some(conv) {
    // Switching focus; the transcript re-pins at the tail. The store is
    // also re-read behind the switch — the local copy may date from
    // before a reconnect, or another client may be driving this
    // conversation — and the current view stays on screen while the
    // reply is in flight. A failed/ongoing first load also needs to stay
    // attached even though it has no transcript yet.
    let reread = model.can_reload_transcript(conv) || !(conv.sync is Synced)
    let (model, generation) = if reread {
      model.begin_transcript_reload(conv)
    } else {
      (model.replace_conversation(conv), None)
    }
    let next = {
      ..model.activate(channel, session_id),
      screen: Chat,
      transcript_pinned: true,
      loading_conversation: if generation is Some(_) {
        Some(owner)
      } else {
        None
      },
      completion: None,
    }.with_active_workspace(conv.workspace)
    let commands = [scroll_transcript_after_render()]
    if generation is Some(generation) {
      commands.push(
        session_snapshot_command(
          dispatch, channel, next, session_id, generation, true,
        ),
      )
    }
    (@cmd.batch(commands), next)
  } else {
    // The sidebar item says which store holds the session; opening it
    // also makes its workspace the active one, so "New chat" follows.
    let workspace = model.session_workspace(channel, session_id)
    let (model, generation) = model.begin_transcript_reload(
      empty_conversation(
        channel,
        session_id,
        workspace?,
        // Reopening a stored conversation recovers the tier it was left on,
        // not whatever was picked last in some other chat.
        model=model
          .remembered_model(channel, session_id)
          .unwrap_or(model.default_model),
      ),
    )
    let next = { ..model, screen: Chat, loading_conversation: Some(owner) }.with_active_workspace(
      workspace,
    )
    if generation is Some(generation) {
      (
        session_snapshot_command(
          dispatch, channel, next, session_id, generation, true,
        ),
        next,
      )
    } else {
      (@cmd.none, next)
    }
  }
}

///|
/// Issue a live-session list request with a page-lifetime token. The token is
/// advanced before the command leaves update, so any older same-connection
/// reply is stale even if it returns last.
fn request_sessions_refresh(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  model : Model,
) -> (@cmd.Cmd, Model) {
  guard model.device_state(channel) is Some(dev) else {
    return (@cmd.none, model)
  }
  let request_generation = dev.sessions_request_generation + 1
  (
    fetch_sessions(
      dispatch,
      channel,
      dev.connection_generation,
      request_generation,
    ),
    model.replace_device({
      ..dev,
      sessions_request_generation: request_generation,
    }),
  )
}

///|
test "new chat keeps the model intact until the rotation lands" {
  let dispatch = test_dispatch()
  let model = {
    ..running_model(),
    loading_conversation: Some({ channel: Local, session: "desktop-stale" }),
  }
  let (_, next) = update(dispatch, NewChat, model)
  inspect(next.active().is_running(), content="true")
  assert_true(next.loading_conversation is None)
}

///|
test "generated session ids include a random suffix" {
  let id = generated_session_id()
  let parts = [..id.split("-")]
  inspect(parts.length(), content="5")
  inspect(parts[0], content="desktop")
  inspect(parts[1].length(), content="8")
  inspect(parts[2].length(), content="6")
  inspect(parts[3].length(), content="3")
  inspect(parts[4].length(), content="9")
  let _ = @string.parse_int(parts[1]) catch {
    _ => fail("expected numeric date")
  }
  let _ = @string.parse_int(parts[2]) catch {
    _ => fail("expected numeric time")
  }
  let _ = @string.parse_int(parts[3]) catch {
    _ => fail("expected numeric millis")
  }
  let _ = @string.parse_int(parts[4]) catch {
    _ => fail("expected numeric salt")
  }
}

///|
test "session rotation activates a fresh conversation, keeping the old one" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..running_conversation(),
    messages: [{ kind: User, content: "hi", ts: None }],
  })
  let (_, next) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "desktop-fresh" }),
    model,
  )
  inspect(next.active_session, content="desktop-fresh")
  inspect(next.active().messages.length(), content="0")
  inspect(next.active().usage_tokens, content="0")
  assert_true(next.display_status() is Ready)
  // The previous conversation keeps running in the background.
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-test")
    is Some(old) else {
    fail("expected the old conversation to survive")
  }
  inspect(old.is_running(), content="true")
  inspect(old.messages.length(), content="1")
}

///|
test "session rotation prunes abandoned empty conversations" {
  let dispatch = test_dispatch()
  let (_, first) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "desktop-a" }),
    test_model(),
  )
  let (_, second) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "desktop-b" }),
    first,
  )
  // "desktop-test" and "desktop-a" had no transcript, no draft, no run.
  inspect(second.conversations.length(), content="1")
  inspect(second.active_session, content="desktop-b")
}

///|
test "a delayed rotation cannot steal focus from another channel" {
  let dispatch = test_dispatch()
  let remote : @interop.ChannelId = Remote("d-remote")
  let model = {
    ..test_model(),
    devices: [
      { ..empty_device_state(@interop.ChannelId::Local), bridge: Connected },
      { ..empty_device_state(remote), bridge: Connected },
    ],
  }
  let (_, next) = update(
    dispatch,
    SessionRotated({ channel: remote, session: "remote-late" }),
    model,
  )
  assert_true(next.focused is Local)
  inspect(next.active_session, content="desktop-test")
  assert_true(next.find_conversation(remote, "remote-late") is None)
}

///|
test "sessions loaded replaces the sidebar list" {
  let dispatch = test_dispatch()
  let items : Array[@transcript.SessionListItem] = [
    {
      id: "desktop-a",
      title: Some("first question"),
      workspace: None,
      workspace_name: "",
    },
  ]
  let (_, once) = update(dispatch, sessions_loaded(items), test_model())
  let (_, twice) = update(dispatch, sessions_loaded(items), test_model())
  inspect(once.dev().sessions.length(), content="1")
  inspect(once.dev().sessions[0].id, content="desktop-a")
  inspect(twice.dev().sessions.length(), content="1")
}

///|
test "session list assigns a commit-first conversation to its durable workspace" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/work/foreign")
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-foreign",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "arrived before the list" }),
    ),
    test_model(),
  )
  guard committed.find_conversation(
      @interop.ChannelId::Local,
      "desktop-foreign",
    )
    is Some(provisional) else {
    fail("commit did not materialize its conversation")
  }
  assert_true(provisional.workspace is None)
  let (_, listed) = update(
    dispatch,
    sessions_loaded(
      [
        {
          id: "desktop-foreign",
          title: Some("arrived before the list"),
          workspace: Some(workspace),
          workspace_name: "foreign",
        },
      ],
      request_generation=committed.dev().sessions_request_generation,
    ),
    committed.activate(@interop.ChannelId::Local, "desktop-foreign"),
  )
  guard listed.find_conversation(@interop.ChannelId::Local, "desktop-foreign")
    is Some(reconciled) else {
    fail("listed conversation disappeared")
  }
  assert_eq(reconciled.workspace, Some(workspace))
  assert_eq(listed.dev().active_workspace, Some(workspace))
  assert_true(encoded_start_workspace(reconciled) is Some("/work/foreign"))
}

///|
test "a background session list updates only its channel's same-id workspace" {
  let dispatch = test_dispatch()
  let remote : @interop.ChannelId = Remote("d-remote")
  let local_conv = {
    ..empty_conversation(@interop.ChannelId::Local, "shared"),
    workspace: Some(@interop.ChannelId::Local.test_resource("/local")),
  }
  let remote_conv = {
    ..empty_conversation(remote, "shared"),
    workspace: Some(remote.test_resource("/remote-old")),
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
      SessionsLoaded(
        [
          {
            id: "shared",
            title: Some("remote"),
            workspace: Some(remote.test_resource("/remote-new")),
            workspace_name: "remote-new",
          },
        ],
        connection_generation=0,
        request_generation=0,
      ),
    ),
    model,
  )
  guard next.find_conversation(@interop.ChannelId::Local, "shared")
    is Some(local_conv) &&
    next.find_conversation(remote, "shared") is Some(remote_conv) else {
    fail("same-id conversations disappeared")
  }
  assert_true(
    local_conv.workspace is Some(workspace) && workspace.path == "/local",
  )
  assert_true(
    remote_conv.workspace is Some(workspace) && workspace.path == "/remote-new",
  )
}

///|
test "session list assigns a Started-first conversation to its durable workspace" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/work/started-first")
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="foreign-run",
      session="desktop-started-first",
      model=High,
      max_steps=1000,
      cwd=None,
      session_root=None,
      task=Some("arrived before the list"),
      submission_id=None,
    ),
    test_model(),
  )
  guard started.find_conversation(
      @interop.ChannelId::Local,
      "desktop-started-first",
    )
    is Some(provisional) else {
    fail("Started did not materialize its conversation")
  }
  assert_true(provisional.workspace is None)
  let (_, listed) = update(
    dispatch,
    sessions_loaded([
      {
        id: "desktop-started-first",
        title: Some("arrived before the list"),
        workspace: Some(workspace),
        workspace_name: "started-first",
      },
    ]),
    started,
  )
  guard listed.find_conversation(
      @interop.ChannelId::Local,
      "desktop-started-first",
    )
    is Some(reconciled) else {
    fail("listed conversation disappeared")
  }
  assert_eq(reconciled.workspace, Some(workspace))
  assert_true(
    encoded_start_workspace(reconciled) is Some("/work/started-first"),
  )
}

///|
test "Started places a foreign conversation from its host session root" {
  let dispatch = test_dispatch()
  let workspace = @interop.ChannelId::Local.test_resource("/C:/work/core")
  let model = test_model().with_dev(dev => { ..dev, workspaces: [workspace] })
  let (_, started) = update_dev(
    dispatch,
    Started(
      run_id="foreign-run",
      session="desktop-workspace-run",
      model=High,
      max_steps=1000,
      cwd=Some(workspace),
      session_root=Some(
        @interop.ChannelId::Local.test_resource("/C:/work/core/.openseek"),
      ),
      task=Some("arrived before the list"),
      submission_id=None,
    ),
    model,
  )
  guard started.find_conversation(
      @interop.ChannelId::Local,
      "desktop-workspace-run",
    )
    is Some(foreign) else {
    fail("Started did not materialize its conversation")
  }
  assert_eq(foreign.workspace, Some(workspace))
  inspect(started.active_session, content="desktop-test")
}

///|
test "sessions failure pops a toast without touching the transcript" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    messages: [{ kind: User, content: "hi", ts: None }],
  })
  let (_, next) = update_dev(dispatch, SessionsFailed("engine exploded"), model)
  inspect(next.notifications.length(), content="1")
  inspect(
    next.notifications[0].message,
    content="Session list unavailable: engine exploded",
  )
  inspect(next.active().messages.length(), content="1")
}

///|
test "open session is a no-op for the current session" {
  let dispatch = test_dispatch()
  let (_, next) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-test"),
    test_model(),
  )
  inspect(next.active_session, content="desktop-test")
  inspect(next.conversations.length(), content="1")
}

///|
test "open session keeps live state on screen while re-reading the store" {
  let dispatch = test_dispatch()
  let background = {
    ..empty_conversation(@interop.ChannelId::Local, "desktop-bg"),
    run: Open(run_id="r9", stage=Opened),
    streaming_response: "mid-stream",
    messages: [{ kind: User, content: "background task", ts: None }],
  }
  let model = running_model().replace_conversation(background)
  let (_, once) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-bg"),
    model,
  )
  let (_, twice) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-bg"),
    model,
  )
  inspect(once.active_session, content="desktop-bg")
  // The live state stays on screen; the store re-read happens behind it
  // (this client may have been absent for part of this conversation).
  inspect(once.active().streaming_response, content="mid-stream")
  inspect(once.active().is_running(), content="true")
  assert_true(
    once.loading_conversation is Some({ channel: Local, session: "desktop-bg" }),
  )
  // The previous conversation is still running in the background.
  guard once.find_conversation(@interop.ChannelId::Local, "desktop-test")
    is Some(old) else {
    fail("expected the old conversation to survive")
  }
  inspect(old.is_running(), content="true")
  inspect(twice.active_session, content="desktop-bg")
}
