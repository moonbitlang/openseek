// Durable transcript snapshot, commit, and reload transitions.

///|
const TranscriptReloadMaxAttempts : Int = 3

///|
/// Build the request for one transcript generation. Foreground loads may
/// activate a selected stored session; background refreshes only reconcile
/// the conversation already in the model.
fn session_snapshot_command(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  model : Model,
  session : String,
  generation : Int,
  activate_on_success : Bool,
) -> @cmd.Cmd {
  let workspace = model.session_workspace(channel, session)
  if activate_on_success {
    open_session(dispatch, channel, session, workspace~, generation~)
  } else {
    refresh_session(dispatch, channel, session, workspace~, generation~)
  }
}

///|
/// Retry one failed generation without losing commits that arrived while its
/// snapshot was in flight. Three attempts form one bounded round. Exhaustion
/// keeps the buffer and a visible local notice; a later commit/reconnect/open
/// starts a fresh generation.
fn retry_session_snapshot(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  model : Model,
  session : String,
  generation : Int,
  activate_on_success : Bool,
  message : String,
) -> (@cmd.Cmd, Model) {
  guard model.find_conversation(channel, session) is Some(conv) &&
    conv.sync
    is Reloading(generation=current, attempt~, buffered~, reload_after_current~) &&
    current == generation else {
    return (@cmd.none, model)
  }
  if attempt < TranscriptReloadMaxAttempts {
    let next_attempt = attempt + 1
    let next = model.replace_conversation({
      ..conv,
      sync: Reloading(
        generation~,
        attempt=next_attempt,
        buffered=buffered.copy(),
        reload_after_current~,
      ),
    })
    let delay_ms = match next_attempt {
      2 => 250
      _ => 500
    }
    (
      @cmd.delay(
        session_snapshot_command(
          dispatch, channel, next, session, generation, activate_on_success,
        ),
        delay_ms,
      ),
      next,
    )
  } else {
    let failed = {
      ..conv,
      sync: ReloadFailed(generation~, buffered=buffered.copy()),
    }.append_local_notice_once(
      Assistant(is_danger=true),
      TranscriptRefreshFailedNotice,
    )
    let next = model.replace_conversation(failed)
    let scroll = if failed.overlay.length() > conv.overlay.length() {
      scroll_if_active(next, channel, session)
    } else {
      @cmd.none
    }
    let owner : @interop.ConversationKey = { channel, session }
    if activate_on_success && model.loading_conversation == Some(owner) {
      let (toast, next) = next.notify_error(dispatch, message)
      let (sessions, next) = request_sessions_refresh(dispatch, channel, next)
      (
        @cmd.batch([toast, sessions, scroll]),
        { ..next, loading_conversation: None },
      )
    } else {
      (scroll, next)
    }
  }
}

///|
/// Fold one current-generation snapshot into its conversation. Lower
/// watermarks retry instead of rolling the transcript back; stale generations
/// are no-ops. Buffered gaps start one new background generation. A
/// foreground result activates only if it still owns `loading_conversation`.
fn apply_session_snapshot(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  model : Model,
  session : String,
  items : Array[@transcript.TranscriptItem],
  watermark : Int,
  event_boundaries : Array[(Int, Bool, Int)],
  generation : Int,
  activate_on_success : Bool,
) -> (@cmd.Cmd, Model) {
  guard model.find_conversation(channel, session) is Some(conv) &&
    conv.sync is Reloading(generation=current, reload_after_current~, ..) &&
    current == generation else {
    return (@cmd.none, model)
  }
  if watermark < conv.watermark {
    return retry_session_snapshot(
      dispatch,
      channel,
      model,
      session,
      generation,
      activate_on_success,
      "failed to load session \{session}: snapshot watermark moved backwards",
    )
  }
  let (conv, gapped) = conv.adopt_snapshot(items, watermark, event_boundaries)
  let mut next = model.replace_conversation(conv)
  let commands : Array[@cmd.Cmd] = []
  let owner : @interop.ConversationKey = { channel, session }
  if activate_on_success && model.loading_conversation == Some(owner) {
    next = {
      ..next.activate(channel, session),
      transcript_pinned: true,
      loading_conversation: None,
      completion: None,
    }
    commands.push(scroll_transcript_after_render())
    // The host derives the resumed workspace from the session id, so the
    // branch probe sends no cwd.
    let (branch_cmd, probed) = probe_branch(
      dispatch,
      next,
      channel,
      session,
      None,
    )
    next = probed
    commands.push(branch_cmd)
  } else {
    commands.push(scroll_if_active(next, channel, session))
  }
  if gapped || reload_after_current {
    guard next.find_conversation(channel, session) is Some(conv) else {
      return (@cmd.batch(commands), next)
    }
    let (reloading, next_generation) = next.begin_transcript_reload(conv)
    next = reloading
    if next_generation is Some(next_generation) {
      commands.push(
        session_snapshot_command(
          dispatch, channel, next, session, next_generation, false,
        ),
      )
    }
  }
  (@cmd.batch(commands), next)
}

///|
/// Scroll the transcript only when `session_id` is the conversation on
/// screen — a background conversation's stream must not yank the visible
/// scroll position around — and only while the user is at the bottom:
/// someone who scrolled up to read history stays where they are.
fn scroll_if_active(
  model : Model,
  channel : @interop.ChannelId,
  session_id : String,
) -> @cmd.Cmd {
  if channel == model.focused &&
    session_id == model.active_session &&
    model.transcript_pinned {
    scroll_transcript_after_render()
  } else {
    @cmd.none
  }
}

///|
test "SessionsLoaded retries an unconfirmed start after an empty recovery" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    { ..test_conversation(), run: NoRun(ended=Some(RunFailed)) },
    "unknown-id",
    "maybe accepted",
  )
  let (conv, _) = conv.mark_submission_unconfirmed(
    "unknown-id", "delivery unconfirmed", false,
  )
  let model = {
    ..test_model().replace_conversation({ ..conv, sync: test_reloading([]) }),
    transcript_request_generation: 1,
  }
  let (_, empty) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[],
      watermark=0,
      event_boundaries=[],
      generation=1,
    ),
    model,
  )
  assert_true(empty.active().sync is Synced)
  inspect(empty.active().input_ledger.length(), content="1")
  let (_, proved) = update(
    dispatch,
    sessions_loaded([
      {
        id: "desktop-test",
        title: Some("persisted"),
        workspace: None,
        workspace_name: "",
      },
    ]),
    empty,
  )
  guard proved.active().sync is Reloading(generation=2, ..) else {
    fail("durable session-list proof did not retry the recovery")
  }
}

///|
test "open session tracks the latest load and ignores stale replies" {
  let dispatch = test_dispatch()
  let (_, loading_a) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-a"),
    test_model(),
  )
  inspect(loading_a.active_session, content="desktop-test")
  assert_true(
    loading_a.loading_conversation
    is Some({ channel: Local, session: "desktop-a" }),
  )
  let (_, loading_b) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-b"),
    loading_a,
  )
  assert_true(
    loading_b.loading_conversation
    is Some({ channel: Local, session: "desktop-b" }),
  )
  let a_items : Array[@transcript.TranscriptItem] = [
    { kind: User, content: "old selection", ts: None },
  ]
  let (_, after_a) = update_dev(
    dispatch,
    SessionLoaded(
      session="desktop-a",
      items=a_items,
      watermark=0,
      event_boundaries=[],
      generation=1,
    ),
    loading_b,
  )
  inspect(after_a.active_session, content="desktop-test")
  assert_true(
    after_a.loading_conversation
    is Some({ channel: Local, session: "desktop-b" }),
  )
  let b_items : Array[@transcript.TranscriptItem] = [
    { kind: User, content: "latest selection", ts: None },
  ]
  let (_, after_b) = update_dev(
    dispatch,
    SessionLoaded(
      session="desktop-b",
      items=b_items,
      watermark=0,
      event_boundaries=[],
      generation=2,
    ),
    after_a,
  )
  inspect(after_b.active_session, content="desktop-b")
  assert_true(after_b.loading_conversation is None)
  inspect(after_b.active().messages[0].content, content="latest selection")
}

///|
test "same-id session loads are fenced by channel owner" {
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
  let (_, loading_remote) = update(
    dispatch,
    OpenSession(remote, "shared"),
    model,
  )
  let (_, loading_local) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "shared"),
    loading_remote,
  )
  assert_true(
    loading_local.loading_conversation
    is Some({ channel: Local, session: "shared" }),
  )
  let (_, remote_reply) = update(
    dispatch,
    FromDevice(
      remote,
      SessionLoaded(
        session="shared",
        items=[
          {
            kind: Assistant(is_danger=false),
            content: "remote loaded",
            ts: None,
          },
        ],
        watermark=1,
        event_boundaries=[],
        generation=1,
      ),
    ),
    loading_local,
  )
  assert_true(remote_reply.focused is Local)
  inspect(remote_reply.active().messages[0].content, content="local")
  assert_true(
    remote_reply.loading_conversation
    is Some({ channel: Local, session: "shared" }),
  )
  guard remote_reply.find_conversation(remote, "shared") is Some(loaded) else {
    fail("remote conversation disappeared")
  }
  inspect(loaded.messages[0].content, content="remote loaded")
}

///|
test "reselecting a synced active session reloads idle external writes" {
  let dispatch = test_dispatch()
  let model = test_model().with_dev(dev => {
    ..dev,
    sessions: [
      {
        id: "desktop-test",
        title: Some(""),
        workspace: None,
        workspace_name: "",
      },
    ],
  })
  let (_, reloading) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-test"),
    model,
  )
  assert_true(
    reloading.loading_conversation
    is Some({ channel: Local, session: "desktop-test" }),
  )
  guard reloading.active().sync is Reloading(generation=1, attempt=1, ..) else {
    fail("expected active reselect to catch up")
  }
  let (_, still_single_flight) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-test"),
    reloading,
  )
  inspect(still_single_flight.transcript_request_generation, content="1")
  guard still_single_flight.active().sync
    is Reloading(generation=1, attempt=1, ..) else {
    fail("active reselect duplicated an in-flight request")
  }
  let (_, loaded) = update_dev(
    dispatch,
    SessionLoaded(
      session="desktop-test",
      items=[
        {
          kind: Assistant(is_danger=false),
          content: "written elsewhere",
          ts: None,
        },
      ],
      watermark=1,
      event_boundaries=[],
      generation=1,
    ),
    still_single_flight,
  )
  inspect(loaded.active().messages.length(), content="1")
  inspect(loaded.active().messages[0].content, content="written elsewhere")
  inspect(loaded.active().watermark, content="1")
  assert_true(loaded.active().sync is Synced)
}

///|
test "returning to a fresh active chat does not load a missing session" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model().replace_conversation({
      ..test_conversation(),
      task: "unsent draft",
    }),
    screen: Skills,
  }
  let (_, next) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-test"),
    model,
  )
  assert_true(next.screen is Chat)
  assert_true(next.loading_conversation is None)
  inspect(next.transcript_request_generation, content="0")
  assert_true(next.active().sync is Synced)
  inspect(next.active().task, content="unsent draft")
}

///|
test "pruning and reopening cannot reuse a transcript request token" {
  let dispatch = test_dispatch()
  let (_, opening) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-pruned"),
    test_model(),
  )
  guard opening.find_conversation(@interop.ChannelId::Local, "desktop-pruned")
    is Some(first) &&
    first.sync is Reloading(generation=1, ..) else {
    fail("expected the original request")
  }
  let pruned = opening.activate(@interop.ChannelId::Local, "desktop-other")
  assert_true(
    pruned.find_conversation(@interop.ChannelId::Local, "desktop-pruned")
    is None,
  )
  let (_, reopened) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-pruned"),
    pruned,
  )
  guard reopened.find_conversation(@interop.ChannelId::Local, "desktop-pruned")
    is Some(second) &&
    second.sync is Reloading(generation=2, ..) else {
    fail("reopened conversation reused its old request token")
  }
  let (_, stale) = update_dev(
    dispatch,
    SessionLoaded(
      session="desktop-pruned",
      items=[{ kind: User, content: "late old snapshot", ts: None }],
      watermark=9,
      event_boundaries=[],
      generation=1,
    ),
    reopened,
  )
  assert_true(
    stale.loading_conversation
    is Some({ channel: Local, session: "desktop-pruned" }),
  )
  guard stale.find_conversation(@interop.ChannelId::Local, "desktop-pruned")
    is Some(current) &&
    current.sync is Reloading(generation=2, ..) else {
    fail("late reply changed the reopened conversation")
  }
  inspect(current.messages.length(), content="0")
  inspect(current.watermark, content="0")
  let (_, fresh) = update_dev(
    dispatch,
    SessionLoaded(
      session="desktop-pruned",
      items=[{ kind: User, content: "fresh snapshot", ts: None }],
      watermark=1,
      event_boundaries=[],
      generation=2,
    ),
    stale,
  )
  inspect(fresh.active_session, content="desktop-pruned")
  inspect(fresh.active().messages[0].content, content="fresh snapshot")
}

///|
test "archive removal and reopening cannot reuse a transcript request token" {
  let dispatch = test_dispatch()
  let (_, opening) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-archived"),
    test_model(),
  )
  let (_, archived) = update(
    dispatch,
    archived_loaded([archived_item("desktop-archived")]),
    opening,
  )
  assert_true(
    archived.find_conversation(@interop.ChannelId::Local, "desktop-archived")
    is None,
  )
  let (_, restored) = update(dispatch, archived_loaded([]), archived)
  let (_, reopened) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-archived"),
    restored,
  )
  guard reopened.find_conversation(
      @interop.ChannelId::Local,
      "desktop-archived",
    )
    is Some(current) &&
    current.sync is Reloading(generation=2, ..) else {
    fail("archive removal allowed a request token to be reused")
  }
  let (_, stale) = update_dev(
    dispatch,
    SessionLoaded(
      session="desktop-archived",
      items=[{ kind: User, content: "late archived snapshot", ts: None }],
      watermark=4,
      event_boundaries=[],
      generation=1,
    ),
    reopened,
  )
  guard stale.find_conversation(@interop.ChannelId::Local, "desktop-archived")
    is Some(unchanged) &&
    unchanged.sync is Reloading(generation=2, ..) else {
    fail("late pre-archive reply changed the reopened conversation")
  }
  inspect(unchanged.messages.length(), content="0")
  inspect(unchanged.watermark, content="0")
}

///|
test "an abandoned session load retries silently" {
  let dispatch = test_dispatch()
  let (_, loading) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-a"),
    test_model(),
  )
  let (_, abandoned) = update(dispatch, NewChat, loading)
  let (_, next) = update_dev(
    dispatch,
    SessionLoadFailed(
      session="desktop-a",
      message="failed to load session desktop-a",
      generation=1,
    ),
    abandoned,
  )
  assert_true(next.loading_conversation is None)
  inspect(next.active().messages.length(), content="0")
  inspect(next.notifications.length(), content="0")
}

///|
test "a foreground load preserves state through retries and reports exhaustion" {
  let dispatch = test_dispatch()
  let (_, loading) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-a"),
    test_model(),
  )
  let failure = SessionLoadFailed(
    session="desktop-a",
    message="failed to load session desktop-a: no such file",
    generation=1,
  )
  let (_, retrying2) = update_dev(dispatch, failure, loading)
  assert_true(
    retrying2.loading_conversation
    is Some({ channel: Local, session: "desktop-a" }),
  )
  inspect(retrying2.notifications.length(), content="0")
  guard retrying2.find_conversation(@interop.ChannelId::Local, "desktop-a")
    is Some(conv2) &&
    conv2.sync is Reloading(attempt=2, ..) else {
    fail("expected the second foreground attempt")
  }
  let (_, retrying3) = update_dev(dispatch, failure, retrying2)
  guard retrying3.find_conversation(@interop.ChannelId::Local, "desktop-a")
    is Some(conv3) &&
    conv3.sync is Reloading(attempt=3, ..) else {
    fail("expected the third foreground attempt")
  }
  let (_, next) = update_dev(dispatch, failure, retrying3)
  assert_true(next.loading_conversation is None)
  inspect(next.notifications.length(), content="1")
  inspect(
    next.notifications[0].message,
    content="failed to load session desktop-a: no such file",
  )
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-a")
    is Some(failed) else {
    fail("expected the failed conversation")
  }
  assert_true(failed.sync is ReloadFailed(..))
  inspect(failed.overlay.length(), content="1")
  assert_eq(failed.overlay[0].content, TranscriptRefreshFailedNotice)
  // The conversation on screen keeps its transcript and status untouched.
  inspect(next.active().messages.length(), content="0")
  assert_true(next.display_status() is Ready)
}

///|
test "send does not show a prompt until its commit lands" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    task: "build the thing",
  })
  let (_, sent) = update(dispatch, Send, model)
  // Starting the request changes lifecycle/composer state only.
  inspect(sent.active().messages.length(), content="0")
  inspect(sent.active().overlay.length(), content="0")
  inspect(sent.active().watermark, content="0")
  // The durable commit is the first point the prompt becomes transcript.
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "build the thing" }),
    ),
    sent,
  )
  inspect(committed.active().messages.length(), content="1")
  guard committed.active().messages[0].kind is User else {
    fail("expected a user item")
  }
  inspect(committed.active().overlay.length(), content="0")
  inspect(committed.active().watermark, content="1")
}

///|
test "a replayed commit at or below the watermark is dropped" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    messages: [{ kind: User, content: "already there", ts: None }],
    watermark: 2,
  })
  let (_, next) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.User({ content: "already there" }),
    ),
    model,
  )
  inspect(next.active().messages.length(), content="1")
  inspect(next.active().watermark, content="2")
}

///|
test "a commit past the frontier buffers and flips into a reload" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    watermark: 1,
  })
  let (_, next) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=5,
      ts=None,
      item=@protocol.User({ content: "from the future" }),
    ),
    model,
  )
  // The gap means missed broadcasts; nothing is applied out of order.
  inspect(next.active().messages.length(), content="0")
  inspect(next.active().watermark, content="1")
  guard next.active().sync is Reloading(buffered~, ..) else {
    fail("expected a reload in flight")
  }
  inspect(buffered.length(), content="1")
  inspect(buffered[0].sequence, content="5")
}

///|
test "commits buffer while a reload is in flight" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    sync: test_reloading([]),
  })
  let (_, next) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=3,
      ts=None,
      item=@protocol.User({ content: "mid-reload" }),
    ),
    model,
  )
  inspect(next.active().messages.length(), content="0")
  guard next.active().sync is Reloading(buffered~, ..) else {
    fail("expected the reload to stay in flight")
  }
  inspect(buffered.length(), content="1")
}

///|
test "a snapshot drains buffered commits in sequence order" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation()
    // Out of arrival order on purpose; the drain sorts by sequence.
    ,
    sync: test_reloading([
      { sequence: 4, ts: None, item: @protocol.User({ content: "four" }) },
      { sequence: 3, ts: None, item: @protocol.User({ content: "three" }) },
    ]),
  })
  let (_, next) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[
        { kind: User, content: "one", ts: None },
        { kind: Assistant(is_danger=false), content: "two", ts: None },
      ],
      watermark=2,
      event_boundaries=[],
      generation=1,
    ),
    model,
  )
  inspect(next.active().messages.length(), content="4")
  inspect(next.active().messages[2].content, content="three")
  inspect(next.active().messages[3].content, content="four")
  inspect(next.active().watermark, content="4")
  assert_true(next.active().sync is Synced)
}

///|
test "a snapshot already containing the buffered commits drops them" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    sync: test_reloading([
      { sequence: 2, ts: None, item: @protocol.User({ content: "dup" }) },
    ]),
  })
  let (_, next) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[
        { kind: User, content: "one", ts: None },
        { kind: User, content: "dup", ts: None },
      ],
      watermark=2,
      event_boundaries=[],
      generation=1,
    ),
    model,
  )
  inspect(next.active().messages.length(), content="2")
  inspect(next.active().watermark, content="2")
  assert_true(next.active().sync is Synced)
}

///|
test "a snapshot with a still-gapped buffer keeps reloading" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    sync: test_reloading([
      { sequence: 9, ts: None, item: @protocol.User({ content: "far" }) },
    ]),
  })
  let (_, next) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[{ kind: User, content: "one", ts: None }],
      watermark=2,
      event_boundaries=[],
      generation=1,
    ),
    model,
  )
  inspect(next.active().watermark, content="2")
  guard next.active().sync is Reloading(buffered~, ..) else {
    fail("expected another reload for the remaining gap")
  }
  inspect(buffered.length(), content="1")
  inspect(buffered[0].sequence, content="9")
}

///|
test "background retries preserve buffered commits until a later success" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    messages: [{ kind: User, content: "kept", ts: None }],
    watermark: 1,
    sync: test_reloading([
      { sequence: 3, ts: None, item: @protocol.User({ content: "x" }) },
    ]),
  })
  let model = { ..model, transcript_request_generation: 1 }
  let failure = SessionRefreshFailed(session="desktop-test", generation=1)
  let (_, retrying2) = update_dev(dispatch, failure, model)
  guard retrying2.active().sync is Reloading(attempt=2, buffered=buffered2, ..) else {
    fail("expected the second background attempt")
  }
  inspect(buffered2.length(), content="1")
  let (_, retrying3) = update_dev(dispatch, failure, retrying2)
  guard retrying3.active().sync is Reloading(attempt=3, ..) else {
    fail("expected the third background attempt")
  }
  let (_, failed) = update_dev(dispatch, failure, retrying3)
  guard failed.active().sync is ReloadFailed(buffered=failed_buffer, ..) else {
    fail("expected bounded retry exhaustion")
  }
  inspect(failed_buffer.length(), content="1")
  inspect(failed.active().messages.length(), content="1")
  inspect(failed.active().overlay.length(), content="1")
  // The next commit starts a fresh generation without applying out of order.
  let (_, retrying) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.User({ content: "next" }),
    ),
    failed,
  )
  guard retrying.active().sync
    is Reloading(generation=2, buffered=retry_buffer, ..) else {
    fail("expected a new generation")
  }
  inspect(retry_buffer.length(), content="2")
  let (_, healed) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[{ kind: User, content: "kept", ts: None }],
      watermark=1,
      event_boundaries=[],
      generation=2,
    ),
    retrying,
  )
  inspect(healed.active().messages.length(), content="3")
  inspect(healed.active().messages[1].content, content="next")
  inspect(healed.active().messages[2].content, content="x")
  inspect(healed.active().watermark, content="3")
  inspect(healed.active().overlay.length(), content="0")
  assert_true(healed.active().sync is Synced)
}

///|
test "reopening an active failed reload retries and preserves other local notices" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    messages: [{ kind: User, content: "kept", ts: None }],
    watermark: 1,
    sync: ReloadFailed(generation=1, buffered=[
      { sequence: 2, ts: None, item: @protocol.User({ content: "two" }) },
    ]),
    overlay: [
      {
        kind: Assistant(is_danger=true),
        content: TranscriptRefreshFailedNotice,
        anchor: AfterMessages(1),
        reconciliation: Retained,
      },
      {
        kind: Assistant(is_danger=true),
        content: "local steer loss",
        anchor: AfterMessages(1),
        reconciliation: Retained,
      },
    ],
  })
  let model = { ..model, transcript_request_generation: 1 }
  let (_, reopened) = update(
    dispatch,
    OpenSession(@interop.ChannelId::Local, "desktop-test"),
    model,
  )
  assert_true(
    reopened.loading_conversation
    is Some({ channel: Local, session: "desktop-test" }),
  )
  guard reopened.active().sync
    is Reloading(generation=2, attempt=1, buffered~, ..) else {
    fail("expected the active click to restart the reload")
  }
  inspect(buffered.length(), content="1")
  let (_, loaded) = update_dev(
    dispatch,
    SessionLoaded(
      session="desktop-test",
      items=[{ kind: User, content: "kept", ts: None }],
      watermark=1,
      event_boundaries=[],
      generation=2,
    ),
    reopened,
  )
  assert_true(loaded.loading_conversation is None)
  inspect(loaded.active().messages.length(), content="2")
  inspect(loaded.active().watermark, content="2")
  // Success clears only the exact refresh-state warning.
  inspect(loaded.active().overlay.length(), content="1")
  inspect(loaded.active().overlay[0].content, content="local steer loss")
}

///|
test "stale and lower-watermark snapshots cannot overwrite current state" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    messages: [{ kind: User, content: "current", ts: None }],
    watermark: 5,
    sync: Reloading(
      generation=2,
      attempt=1,
      buffered=[
        { sequence: 6, ts: None, item: @protocol.User({ content: "six" }) },
      ],
      reload_after_current=false,
    ),
  })
  let (_, stale) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[{ kind: User, content: "stale generation", ts: None }],
      watermark=9,
      event_boundaries=[],
      generation=1,
    ),
    model,
  )
  inspect(stale.active().messages[0].content, content="current")
  inspect(stale.active().watermark, content="5")
  guard stale.active().sync is Reloading(generation=2, attempt=1, ..) else {
    fail("stale generation changed the active reload")
  }
  let (_, lower) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[{ kind: User, content: "older snapshot", ts: None }],
      watermark=4,
      event_boundaries=[],
      generation=2,
    ),
    stale,
  )
  inspect(lower.active().messages[0].content, content="current")
  inspect(lower.active().watermark, content="5")
  guard lower.active().sync is Reloading(generation=2, attempt=2, buffered~, ..) else {
    fail("lower watermark did not retry the current generation")
  }
  inspect(buffered.length(), content="1")
}

///|
test "tool decode semantics wait for their durable error tool result" {
  let dispatch = test_dispatch()
  let semantic = Engine(
    Some("r7"),
    ToolCallDecodeError(tool_name="edit", reason="invalid arguments"),
    session=None,
  )
  let commit = SessionCommitted(
    session="desktop-test",
    sequence=1,
    ts=None,
    item=@protocol.ToolResult({
      tool_call_id: "",
      tool_name: "edit",
      content: "invalid arguments",
      is_error: true,
      brief: None,
    }),
  )
  let (_, semantic_first) = update_dev(dispatch, semantic, running_model())
  inspect(semantic_first.active().messages.length(), content="0")
  inspect(semantic_first.active().overlay.length(), content="0")
  let (_, committed_after) = update_dev(dispatch, commit, semantic_first)
  inspect(committed_after.active().messages.length(), content="1")
  inspect(committed_after.active().overlay.length(), content="0")
  guard committed_after.active().messages[0].kind
    is Tool(name="edit", is_error=true, ..) else {
    fail("expected the canonical error tool result")
  }
  inspect(
    committed_after.active().messages[0].content,
    content="invalid arguments",
  )
  let (_, committed_first) = update_dev(dispatch, commit, running_model())
  let (_, semantic_after) = update_dev(dispatch, semantic, committed_first)
  inspect(semantic_after.active().messages.length(), content="1")
  inspect(semantic_after.active().overlay.length(), content="0")
}

///|
test "assistant semantic events wait for their durable commit" {
  let dispatch = test_dispatch()
  let (_, thought) = update_dev(
    dispatch,
    Engine(Some("r7"), ReasoningMessage("think"), session=None),
    running_model(),
  )
  let (_, answered) = update_dev(
    dispatch,
    Engine(Some("r7"), AssistantMessage("answer"), session=None),
    thought,
  )
  inspect(answered.active().messages.length(), content="0")
  inspect(answered.active().overlay.length(), content="0")
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.Assistant({
        content: "answer",
        tool_calls: None,
        reasoning_content: Some("think"),
      }),
    ),
    answered,
  )
  // One durable item projects as reasoning + answer exactly once.
  inspect(committed.active().messages.length(), content="2")
  inspect(committed.active().overlay.length(), content="0")
  inspect(committed.active().watermark, content="1")
}

///|
test "a committed tool result visibly changes its existing call row" {
  let (_, called) = running_conversation().apply_commit(
    1,
    @protocol.Assistant({
      content: "",
      tool_calls: Some([
        { id: "c1", name: "read", arguments: "{\"path\":\"moon.mod\"}" },
      ]),
      reasoning_content: None,
    }),
  )
  inspect(called.messages.length(), content="1")
  let (changed, completed) = called.apply_commit(
    2,
    @protocol.ToolResult({
      tool_call_id: "c1",
      tool_name: "read",
      content: "module contents",
      is_error: false,
      brief: Some("read moon.mod"),
    }),
  )
  assert_true(changed)
  inspect(completed.messages.length(), content="1")
  inspect(completed.messages[0].content, content="module contents")
}

///|
test "a delayed assistant commit never clears a newer live delta" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "newer turn fragment",
  })
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.Assistant({
        content: "older committed answer",
        tool_calls: None,
        reasoning_content: None,
      }),
    ),
    model,
  )
  inspect(committed.active().streaming_response, content="newer turn fragment")
}

///|
test "a delayed terminal commit never clears a newer live delta" {
  let dispatch = test_dispatch()
  let model = running_model().replace_conversation({
    ..running_conversation(),
    messages: [{ kind: User, content: "older prompt", ts: None }],
    watermark: 1,
    streaming_response: "next turn fragment",
  })
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.Terminal(@protocol.Finished("older answer")),
    ),
    model,
  )
  inspect(committed.active().streaming_response, content="next turn fragment")
}

///|
test "a fixed local notice stays before later durable turns" {
  let dispatch = test_dispatch()
  let conv = {
    ..test_conversation(),
    messages: [{ kind: User, content: "question", ts: None }],
    watermark: 1,
  }.append_local_notice(Assistant(is_danger=true), "local failure")
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=2,
      ts=None,
      item=@protocol.Assistant({
        content: "later answer",
        tool_calls: None,
        reasoning_content: None,
      }),
    ),
    test_model().replace_conversation(conv),
  )
  let visible = committed.active().visible_items()
  inspect(visible.length(), content="3")
  inspect(visible[0].content, content="question")
  inspect(visible[1].content, content="local failure")
  inspect(visible[2].content, content="later answer")
}

///|
test "a durable commit never retires a same-class local notice" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    overlay: [
      {
        kind: Assistant(is_danger=true),
        content: "local-only failure",
        anchor: AfterMessages(0),
        reconciliation: Retained,
      },
    ],
  })
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.Assistant({
        content: "durable answer",
        tool_calls: None,
        reasoning_content: None,
      }),
    ),
    model,
  )
  inspect(committed.active().messages.length(), content="1")
  inspect(committed.active().overlay.length(), content="1")
  inspect(committed.active().overlay[0].content, content="local-only failure")
}

///|
test "commit-first assistant semantics do not append again" {
  let dispatch = test_dispatch()
  let streaming = running_model().replace_conversation({
    ..running_conversation(),
    streaming_response: "answer",
  })
  let (_, committed) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=1,
      ts=None,
      item=@protocol.Assistant({
        content: "answer",
        tool_calls: None,
        reasoning_content: Some("think"),
      }),
    ),
    streaming,
  )
  let (_, thought) = update_dev(
    dispatch,
    Engine(Some("r7"), ReasoningMessage("think"), session=None),
    committed,
  )
  let (_, answered) = update_dev(
    dispatch,
    Engine(Some("r7"), AssistantMessage("answer"), session=None),
    thought,
  )
  inspect(answered.active().messages.length(), content="2")
  inspect(answered.active().overlay.length(), content="0")
  inspect(answered.active().watermark, content="1")
  inspect(answered.active().streaming_response, content="")
}

///|
test "a sequence-one commit materializes an unknown hidden conversation" {
  let dispatch = test_dispatch()
  let (_, next) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-elsewhere",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "hi" }),
    ),
    test_model(),
  )
  inspect(next.conversations.length(), content="2")
  inspect(next.active().messages.length(), content="0")
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-elsewhere")
    is Some(hidden) else {
    fail("unknown commit did not materialize its session")
  }
  inspect(hidden.messages.length(), content="1")
  inspect(hidden.messages[0].content, content="hi")
  inspect(hidden.watermark, content="1")
  inspect(next.dev().sessions_request_generation, content="1")
  let (_, repeated) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-elsewhere",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "hi" }),
    ),
    next,
  )
  inspect(repeated.dev().sessions_request_generation, content="1")
}

///|
test "a gapped commit for an unknown session materializes then reloads" {
  let dispatch = test_dispatch()
  let (_, next) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-gap",
      sequence=3,
      ts=None,
      item=@protocol.User({ content: "third" }),
    ),
    test_model(),
  )
  guard next.find_conversation(@interop.ChannelId::Local, "desktop-gap")
    is Some(hidden) else {
    fail("gapped commit did not materialize its session")
  }
  inspect(hidden.messages.length(), content="0")
  guard hidden.sync is Reloading(generation=1, buffered~, ..) else {
    fail("unknown gap did not start a snapshot recovery")
  }
  inspect(buffered.length(), content="1")
  inspect(buffered[0].sequence, content="3")
  inspect(next.active_session, content="desktop-test")
}

///|
test "a late commit cannot resurrect a locally known archived session" {
  let dispatch = test_dispatch()
  let model = test_model().with_dev(dev => {
    ..dev,
    archived: [
      {
        id: "desktop-archived",
        title: Some("archived"),
        workspace: None,
        workspace_name: "",
      },
    ],
  })
  let (_, next) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-archived",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "stale" }),
    ),
    model,
  )
  assert_true(
    next.find_conversation(@interop.ChannelId::Local, "desktop-archived")
    is None,
  )
  inspect(next.conversations.length(), content="1")
}

///|
test "an archive tombstone blocks commits before the archived list refreshes" {
  let dispatch = test_dispatch()
  let model = test_model().with_archive_override(
    @interop.ChannelId::Local,
    "desktop-tombstoned",
    true,
  )
  let (_, next) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-tombstoned",
      sequence=1,
      ts=None,
      item=@protocol.User({ content: "stale" }),
    ),
    model,
  )
  assert_true(
    next.find_conversation(@interop.ChannelId::Local, "desktop-tombstoned")
    is None,
  )
  inspect(next.conversations.length(), content="1")
}
