// Rabbita resource declarations for the desktop window's local host
// connection and remote device connections. The payload carries only
// transport identity and an Event emitter, never parent-frontend model or
// message types.

///|
priv suberror BridgeSubscription {
  LocalBridge(dispatch~ : @cmd.Emit[Event], websocket_epoch~ : Int)
  RemoteBridge(
    dispatch~ : @cmd.Emit[Event],
    device_id~ : String,
    websocket_epoch~ : Int
  )
}

///|
/// Declare the desktop window's connection to its own host. Advancing either
/// generation replaces the socket, exactly as for a remote device.
pub fn local_connection(
  websocket_epoch~ : Int,
  reconnect_attempt~ : Int,
  dispatch~ : @cmd.Emit[Event],
) -> @sub.Sub {
  @sub.custom_sub(
    LocalBridgeSub::subscription_key(websocket_epoch, reconnect_attempt),
    @sub.Global,
    LocalBridge(dispatch~, websocket_epoch~),
    bridge_sub_loader,
  )
}

///|
/// Declare one remote device connection. Advancing either generation replaces
/// the socket; ordinary model changes only refresh the event emitter.
pub fn remote_connection(
  device_id~ : String,
  websocket_epoch~ : Int,
  reconnect_attempt~ : Int,
  dispatch~ : @cmd.Emit[Event],
) -> @sub.Sub {
  @sub.custom_sub(
    RemoteBridgeSub::subscription_key(
      device_id, websocket_epoch, reconnect_attempt,
    ),
    @sub.Global,
    RemoteBridge(dispatch~, device_id~, websocket_epoch~),
    bridge_sub_loader,
  )
}

///|
fn bridge_sub_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    LocalBridge(dispatch~, websocket_epoch~) => {
      let running = LocalBridgeSub(websocket_epoch, dispatch)
      running.install(scheduler)
      Some({
        unload: _ => running.unload(),
        update_tagger: payload => {
          match payload {
            LocalBridge(dispatch=next, ..) => running.update_dispatch(next)
            _ => ()
          }
        },
      })
    }
    RemoteBridge(dispatch~, device_id~, websocket_epoch~) => {
      let running = RemoteBridgeSub(device_id, websocket_epoch, dispatch)
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
  let remote = RemoteBridgeSub::subscription_key("device-a", 0, 0)
  assert_eq(RemoteBridgeSub::subscription_key("device-a", 0, 0), remote)
  assert_not_eq(RemoteBridgeSub::subscription_key("device-a", 0, 1), remote)
  assert_not_eq(RemoteBridgeSub::subscription_key("device-a", 1, 0), remote)
  let here = LocalBridgeSub::subscription_key(0, 0)
  assert_eq(LocalBridgeSub::subscription_key(0, 0), here)
  assert_not_eq(LocalBridgeSub::subscription_key(0, 1), here)
  assert_not_eq(LocalBridgeSub::subscription_key(1, 0), here)
  assert_not_eq(here, remote)
}
