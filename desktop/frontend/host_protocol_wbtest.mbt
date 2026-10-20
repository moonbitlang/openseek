///|
test "agent.connected admits only this build's protocol revision" {
  let channel : @interop.ChannelId = Remote("d1")
  assert_true(
    device_msg(
      channel,
      AgentConnected({ protocol: Some(@protocol.HostProtocolRevision), }),
    )
    is Some(BridgeReady),
  )
  for protocol in [Some(@protocol.HostProtocolRevision + 1), Some(0), None] {
    assert_true(
      device_msg(channel, AgentConnected({ protocol, })) is Some(HostMismatched),
    )
  }
}

///|
test "a browser gates an incompatible host without sending it requests" {
  let dispatch = test_dispatch()
  let channel : @interop.ChannelId = Remote("d1")
  let model = {
    ..initial_model(desktop=false),
    devices: [{ ..empty_device_state(channel), bridge: Connecting, }],
    focused: channel,
  }
  let (_, incompatible) = update(
    dispatch,
    FromDevice(channel, HostMismatched),
    model,
  )
  assert_true(incompatible.bridge_state() is HostIncompatible)
  assert_true(incompatible.display_status() is Unavailable(_))
  // Every non-Cloud page shows the gate, not only a conversation header.
  assert_true(incompatible.host_incompatible())
  assert_true(incompatible.is_console_gated())
  assert_false(model.host_incompatible())
}

///|
test "the desktop window treats its own host as ready whatever it reports" {
  let dispatch = test_dispatch()
  let model = { ..test_model(), is_desktop: true, }
  let (_, next) = update_dev(dispatch, HostMismatched, model)
  assert_true(next.bridge_state() is Connected)
  assert_false(next.host_incompatible())
}
