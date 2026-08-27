// Rabbita resource declarations for local Proton and remote WebSocket host
// connections. The payload carries only transport identity and an Event
// handler, never parent-frontend model or message types.

///|
priv suberror BridgeSubscription {
  LocalBridge(events~ : EventHandler)
  RemoteBridge(
    events~ : EventHandler,
    device_id~ : String,
    websocket_epoch~ : Int
  )
}

///|
/// Declare the desktop window's injected Proton connection.
pub fn local_connection(events : EventHandler) -> @sub.Sub {
  @sub.custom_sub(
    LocalBridgeKey,
    @sub.Global,
    LocalBridge(events~),
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
  events~ : EventHandler,
) -> @sub.Sub {
  @sub.custom_sub(
    RemoteBridgeSub::subscription_key(
      device_id, websocket_epoch, reconnect_attempt,
    ),
    @sub.Global,
    RemoteBridge(events~, device_id~, websocket_epoch~),
    bridge_sub_loader,
  )
}

///|
fn bridge_sub_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    LocalBridge(events~) => {
      let running = LocalBridgeSub(events)
      scheduler.add(running.install(0))
      Some({
        unload: _ => running.unload(),
        update_tagger: payload => {
          match payload {
            LocalBridge(events=next) => running.update_events(next)
            _ => ()
          }
        },
      })
    }
    RemoteBridge(events~, device_id~, websocket_epoch~) => {
      let running = RemoteBridgeSub(device_id, websocket_epoch, events)
      running.install(scheduler)
      Some({
        unload: _ => running.unload(),
        update_tagger: payload => {
          match payload {
            RemoteBridge(events=next, ..) => running.update_events(next)
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
}
