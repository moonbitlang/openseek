// Rabbita resource declarations for local Proton and remote WebSocket host
// connections. The payload carries only transport identity and an Event
// emitter, never parent-frontend model or message types.

///|
priv suberror BridgeSubscription {
  LocalBridge(dispatch~ : @cmd.Emit[Event])
  RemoteBridge(
    dispatch~ : @cmd.Emit[Event],
    device_id~ : String,
    websocket_id~ : String
  )
}

///|
/// Declare the desktop window's injected Proton connection.
pub fn local_connection(dispatch : @cmd.Emit[Event]) -> @sub.Sub {
  @sub.custom_sub(
    LocalBridgeKey,
    @sub.Global,
    LocalBridge(dispatch~),
    bridge_sub_loader,
  )
}

///|
/// Declare one remote device connection. Replacing either identity replaces
/// the socket; ordinary model changes only refresh the event emitter.
pub fn remote_connection(
  device_id~ : String,
  websocket_id~ : String,
  reconnect_id~ : String,
  dispatch~ : @cmd.Emit[Event],
) -> @sub.Sub {
  @sub.custom_sub(
    RemoteBridgeSub::subscription_key(
      device_id, websocket_id, reconnect_id,
    ),
    @sub.Global,
    RemoteBridge(dispatch~, device_id~, websocket_id~),
    bridge_sub_loader,
  )
}

///|
fn bridge_sub_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    LocalBridge(dispatch~) => {
      let running = LocalBridgeSub(dispatch)
      scheduler.add(running.install(0))
      Some({
        unload: _ => running.unload(),
        update_tagger: payload => {
          match payload {
            LocalBridge(dispatch=next) => running.update_dispatch(next)
            _ => ()
          }
        },
      })
    }
    RemoteBridge(dispatch~, device_id~, websocket_id~) => {
      let running = RemoteBridgeSub(device_id, websocket_id, dispatch)
      running.install(scheduler)
      Some({
        unload: _ => running.unload(),
        update_tagger: payload => {
          match payload {
            RemoteBridge(dispatch=next, ..) => running.update_dispatch(next)
            _ => ()
          }
        },
      })
    }
    _ => None
  }
}

///|
test "bridge identity changes only when its resource must restart" {
  let remote = RemoteBridgeSub::subscription_key(
    "device-a", "websocket-a", "reconnect-a",
  )
  assert_eq(
    RemoteBridgeSub::subscription_key(
      "device-a", "websocket-a", "reconnect-a",
    ),
    remote,
  )
  assert_not_eq(
    RemoteBridgeSub::subscription_key(
      "device-a", "websocket-a", "reconnect-b",
    ),
    remote,
  )
  assert_not_eq(
    RemoteBridgeSub::subscription_key(
      "device-a", "websocket-b", "reconnect-a",
    ),
    remote,
  )
}
