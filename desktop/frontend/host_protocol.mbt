///|
/// Ask a remote host which protocol revision it was built for. A failed
/// request leaves the connection alone: a lost socket reports itself.
fn check_host_protocol(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  connection_generation : Int32,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let reply = @interop.bridge_request(
        channel,
        @commands.app_info,
        @protocol.EmptyPayload::NoPayload,
      ) catch {
        _ => return
      }
      scheduler.add(
        dispatch(
          HostProtocolChecked(connection_generation~, protocol=reply.protocol),
        ),
      )
    })
    |> ignore
  })
}

///|
test "a browser marks a host on another protocol revision incompatible" {
  let dispatch = test_dispatch()
  let channel : @interop.ChannelId = Remote("d1")
  let model = {
    ..initial_model(desktop=false),
    devices: [
      {
        ..empty_device_state(channel),
        bridge: Connected,
        connection_generation: 3,
      },
    ],
    focused: channel,
  }
  let check = (protocol : Int32?, connection_generation : Int32) => {
    let (_, next) = update(
      dispatch,
      FromDevice(
        channel,
        HostProtocolChecked(connection_generation~, protocol~),
      ),
      model,
    )
    next
  }
  assert_true(
    check(Some(@protocol.HostProtocolRevision), 3).bridge_state() is Connected,
  )
  // A reply from an earlier connection is stale.
  assert_true(check(Some(0), 2).bridge_state() is Connected)
  let incompatible = check(Some(0), 3)
  assert_true(incompatible.bridge_state() is HostIncompatible)
  assert_true(incompatible.display_status() is Unavailable(_))
  // Every non-Cloud page shows the gate, not only a conversation header.
  assert_true(incompatible.host_incompatible())
  assert_true(incompatible.is_console_gated())
  assert_false(model.host_incompatible())
  assert_true(check(None, 3).bridge_state() is HostIncompatible)
}
