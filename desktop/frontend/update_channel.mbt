// Device connection, loss, and reconnect transitions.

///|
test "reconnect refresh is single-flight and preserves its commit buffer" {
  let dispatch = test_dispatch()
  let model = test_model().replace_conversation({
    ..test_conversation(),
    messages: [{ kind: User, content: "kept", ts: None }],
    watermark: 1,
  })
  let (_, refreshing) = update_dev(dispatch, BridgeReady, model)
  guard refreshing.active().sync is Reloading(generation=1, attempt=1, ..) else {
    fail("expected the first reconnect refresh")
  }
  let (_, buffered) = update_dev(
    dispatch,
    SessionCommitted(
      session="desktop-test",
      sequence=3,
      ts=None,
      item=@protocol.User({ content: "future" }),
    ),
    refreshing,
  )
  let (_, reconnected_again) = update_dev(dispatch, BridgeReady, buffered)
  guard reconnected_again.active().sync
    is Reloading(generation=1, attempt=1, buffered=commits, ..) else {
    fail("a second reconnect started another generation")
  }
  inspect(commits.length(), content="1")
  inspect(commits[0].sequence, content="3")
}

///|
test "BridgeReady clears every non-replayable stream and compaction phase" {
  let dispatch = test_dispatch()
  let active = {
    ..test_conversation(),
    streaming_response: "old answer",
    compaction: Queued,
  }
  let background = {
    ..empty_conversation(@interop.ChannelId::Local, "desktop-bg"),
    streaming_response: "background answer",
    compaction: Compacting,
  }
  let model = test_model()
    .replace_conversation(active)
    .replace_conversation(background)
  let (_, next) = update_dev(dispatch, BridgeReady, model)
  for conv in next.conversations {
    inspect(conv.streaming_response, content="")
    assert_true(conv.compaction is NotCompacting)
  }
}

///|
test "BridgeReady clears focused host settings until the refetch lands" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model(),
    api_provider: Custom,
    custom_api_url: "https://old.example/chat",
    custom_key_saved: true,
    setup_api_key: "old-key",
    host_settings_revision: 7,
  }
  let (_, next) = update_dev(dispatch, BridgeReady, model)
  assert_false(next.host_settings_loaded())
  assert_true(next.api_provider is Openseek)
  inspect(next.custom_api_url, content="")
  assert_false(next.custom_key_saved)
  inspect(next.setup_api_key, content="")
}

///|
test "BridgeReady resets only conversations owned by its channel" {
  let dispatch = test_dispatch()
  let background : @interop.ChannelId = Remote("d-bg")
  let local_conv = {
    ..empty_conversation(@interop.ChannelId::Local, "shared"),
    streaming_response: "local answer",
    compaction: Queued,
  }
  let remote = {
    ..empty_conversation(background, "shared"),
    streaming_response: "remote answer",
    compaction: Compacting,
  }
  let model = {
    ..test_model(),
    devices: [
      { ..empty_device_state(@interop.ChannelId::Local), bridge: Connected },
      { ..empty_device_state(background), bridge: Connected },
    ],
    active_session: "shared",
    conversations: [local_conv, remote],
  }
  let (_, next) = update(dispatch, FromDevice(background, BridgeReady), model)
  guard next.find_conversation(@interop.ChannelId::Local, "shared")
    is Some(kept) &&
    next.find_conversation(background, "shared") is Some(reset) else {
    fail("same-id conversations were not preserved")
  }
  inspect(kept.streaming_response, content="local answer")
  assert_true(kept.compaction is Queued)
  inspect(reset.streaming_response, content="")
  assert_true(reset.compaction is NotCompacting)
}

///|
test "socket losses mark the bridge lost at the third consecutive drop" {
  let dispatch = test_dispatch()
  let channel : @interop.ChannelId = Remote("d1")
  let model = {
    ..initial_model(),
    devices: [{ ..empty_device_state(channel), bridge: Connected }],
    focused: channel,
    terminal_panel: {
      ..@terminal.State::empty(),
      next_key: 2,
      tabs: [
        {
          key: 1,
          id: Some(1),
          workspace: @terminal.Project(
            channel,
            channel.test_resource("/remote"),
          ),
          workspace_label: "remote",
          session: "remote-session",
          workspace_path: Some(channel.test_resource("/remote")),
          status: @terminal.TabRunning,
        },
      ],
    },
  }
  let (_, one) = update(
    dispatch,
    FromDevice(channel, ChannelDown(websocket_epoch=0)),
    model,
  )
  // The first socket loss destroys this HostConnection's PTYs even though
  // the general page does not escalate to BridgeLost until the third loss.
  assert_true(one.terminal_panel.tabs.is_empty())
  let (_, two) = update(
    dispatch,
    FromDevice(channel, ChannelDown(websocket_epoch=0)),
    one,
  )
  inspect(two.dev().reconnect_failures, content="2")
  assert_true(two.bridge_state() is Connected)
  let (_, three) = update(
    dispatch,
    FromDevice(channel, ChannelDown(websocket_epoch=0)),
    two,
  )
  assert_true(three.bridge_state() is BridgeLost(_))
}

///|
test "BridgeReady resets the reconnect failure count" {
  let dispatch = test_dispatch()
  let channel : @interop.ChannelId = Remote("d1")
  let model = {
    ..initial_model(),
    devices: [
      {
        ..empty_device_state(channel),
        reconnect_failures: 2,
        bridge: BridgeLost("gone"),
      },
    ],
    focused: channel,
  }
  let (_, next) = update(dispatch, FromDevice(channel, BridgeReady), model)
  inspect(next.dev().reconnect_failures, content="0")
  assert_true(next.bridge_state() is Connected)
}

///|
test "late reconnect ticks cannot act on removed or re-added devices" {
  let dispatch = test_dispatch()
  let channel : @interop.ChannelId = Remote("gone")
  let model = test_model()
  let (_, next) = update(
    dispatch,
    FromDevice(channel, ReconnectDue(websocket_epoch=1)),
    model,
  )
  inspect(next.devices.length(), content="1")
  assert_true(next.device_state(channel) is None)
  // Reusing the relay id after sign-out is not reusing the connection. The
  // page-wide epoch survives account teardown and advances when the roster
  // adopts the same id again.
  let roster : Array[DeviceMeta] = [
    { id: "same", name: "Mac", hostname: None, online: true },
  ]
  let (_, signed) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    console_test_model(),
  )
  let (_, first) = update(
    dispatch,
    Console(RosterLoaded(roster, generation=1)),
    signed,
  )
  let same : @interop.ChannelId = Remote("same")
  guard first.device_state(same) is Some(first_dev) else {
    fail("first device connection missing")
  }
  inspect(first_dev.websocket_epoch, content="1")
  let (_, out) = update(dispatch, Console(MeUnauthorized), first)
  let (_, signed_again) = update(
    dispatch,
    Console(MeLoaded(login="o", avatar="")),
    out,
  )
  let (_, current) = update(
    dispatch,
    Console(RosterLoaded(roster, generation=2)),
    signed_again,
  )
  guard current.device_state(same) is Some(current_dev) else {
    fail("re-added device connection missing")
  }
  inspect(current_dev.websocket_epoch, content="2")
  let (_, stale) = update(
    dispatch,
    FromDevice(same, ReconnectDue(websocket_epoch=1)),
    current,
  )
  assert_true(stale.devices == current.devices)
  inspect(stale.websocket_epoch, content="2")
}

///|
test "BridgeReady fences an awaiting initial after disconnected canonical items" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    {
      ..test_conversation(),
      run: Starting(submission_id="reconnect-prompt"),
      messages: [{ kind: User, content: "before disconnect", ts: None }],
      watermark: 1,
    },
    "reconnect-prompt",
    "prompt sent near disconnect",
  )
  let (_, reconnected) = update_dev(
    dispatch,
    BridgeReady,
    test_model().replace_conversation(conv),
  )
  assert_true(reconnected.active().input_ledger[0].state is Unconfirmed)
  assert_true(
    reconnected.active().overlay[0].anchor is SnapshotCut(snapshot_generation=1),
  )
  assert_true(reconnected.active().sync is Reloading(generation=1, ..))
  let (_, reconciled) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[
        { kind: User, content: "before disconnect", ts: None },
        { kind: User, content: "canonical prompt from the gap", ts: None },
        {
          kind: Assistant(is_danger=false),
          content: "canonical answer from the gap",
          ts: None,
        },
      ],
      watermark=3,
      event_boundaries=[(1, false, 1), (2, false, 2), (3, false, 3)],
      generation=1,
    ),
    reconnected,
  )
  assert_true(reconciled.active().overlay[0].anchor is AfterMessages(3))
  let visible = reconciled.active().visible_items()
  inspect(visible.length(), content="4")
  inspect(visible[2].content, content="canonical answer from the gap")
  assert_true(visible[3].content.contains("prompt sent near disconnect"))
}

///|
test "BridgeReady fences an awaiting steer after disconnected canonical items" {
  let dispatch = test_dispatch()
  let conv = with_pending_steers(
    {
      ..running_conversation(),
      messages: [{ kind: User, content: "before disconnect", ts: None }],
      watermark: 1,
    },
    ["steer sent near disconnect"],
  )
  let (_, reconnected) = update_dev(
    dispatch,
    BridgeReady,
    running_model().replace_conversation(conv),
  )
  assert_true(reconnected.active().input_ledger[0].state is Unconfirmed)
  assert_true(
    reconnected.active().overlay[0].anchor is SnapshotCut(snapshot_generation=1),
  )
  assert_true(reconnected.active().sync is Reloading(generation=1, ..))
  let (_, reconciled) = update_dev(
    dispatch,
    SessionRefreshed(
      session="desktop-test",
      items=[
        { kind: User, content: "before disconnect", ts: None },
        { kind: User, content: "canonical steer from the gap", ts: None },
        {
          kind: Assistant(is_danger=false),
          content: "canonical output from the gap",
          ts: None,
        },
      ],
      watermark=3,
      event_boundaries=[(1, false, 1), (2, false, 2), (3, false, 3)],
      generation=1,
    ),
    reconnected,
  )
  assert_true(reconciled.active().overlay[0].anchor is AfterMessages(3))
  let visible = reconciled.active().visible_items()
  inspect(visible.length(), content="4")
  inspect(visible[2].content, content="canonical output from the gap")
  assert_true(visible[3].content.contains("steer sent near disconnect"))
}

///|
test "an explicit rejected fresh start does not force reconnect reloads" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="rejected-id") },
    "rejected-id",
    "try this",
  )
  let (_, rejected) = update_dev(
    dispatch,
    StartRejected(
      session="desktop-test",
      submission_id="rejected-id",
      message="host refused",
    ),
    test_model().replace_conversation(conv),
  )
  inspect(rejected.active().input_ledger.length(), content="0")
  let (_, reconnected) = update_dev(dispatch, BridgeReady, rejected)
  assert_true(reconnected.active().sync is Synced)
  inspect(reconnected.transcript_request_generation, content="0")
}

///|
test "an unconfirmed empty start forces reconnect recovery" {
  let dispatch = test_dispatch()
  let conv = with_initial_submission(
    { ..test_conversation(), run: Starting(submission_id="unknown-id") },
    "unknown-id",
    "maybe accepted",
  )
  let (_, uncertain) = update_dev(
    dispatch,
    StartUndelivered(
      session="desktop-test",
      submission_id="unknown-id",
      message="connection lost",
    ),
    test_model().replace_conversation(conv),
  )
  let (_, reconnected) = update_dev(dispatch, BridgeReady, uncertain)
  guard reconnected.active().sync is Reloading(generation=1, ..) else {
    fail("unconfirmed start did not force a durable reload")
  }
}
