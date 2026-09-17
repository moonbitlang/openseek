// The desktop window's connection to its own host: the page's loopback
// origin's `/ws`, one JSON-RPC WebSocket exactly like a remote device's
// (docs/remote-protocol.md), with the same reconnect generations. On top of
// it ride the two things only Proton's injected runtime carries — application
// menu commands and system-notification clicks — as best-effort listeners: a
// page without the runtime (a test browser) still gets its host connection.

///|
priv struct LocalBridgeSub {
  websocket_epoch : Int
  mut dispatch : @cmd.Emit[Event]
  mut active : Bool
  unsubscribers : Array[@js.Value]
}

///|
fn LocalBridgeSub::LocalBridgeSub(
  websocket_epoch : Int,
  dispatch : @cmd.Emit[Event],
) -> LocalBridgeSub {
  { websocket_epoch, dispatch, active: true, unsubscribers: [], }
}

///|
fn LocalBridgeSub::subscription_key(
  websocket_epoch : Int,
  reconnect_attempt : Int,
) -> String {
  let channel : @interop.ChannelId = @interop.ChannelId::Local
  "host-bridge:\{channel.uri_authority()}:\{websocket_epoch}:\{reconnect_attempt}"
}

///|
fn LocalBridgeSub::install(
  self : LocalBridgeSub,
  scheduler : &@cmd.Scheduler,
) -> Unit {
  let channel : @interop.ChannelId = @interop.ChannelId::Local
  @interop.ws_connect(
    channel,
    on_notification=notification => {
      scheduler.add((self.dispatch)(Notification(channel~, notification~)))
    },
    on_down=() => {
      scheduler.add(
        (self.dispatch)(
          ChannelDown(channel~, websocket_epoch=self.websocket_epoch),
        ),
      )
    },
  )
  scheduler.add(self.wire_runtime_events(0))
}

///|
/// Wait for Proton to inject its runtime, then listen for the events only it
/// carries. The 25ms retries add up to roughly three seconds; a page that
/// never gets the runtime simply has no menu bar or system notifications.
/// Unloading makes every already queued retry harmless.
fn LocalBridgeSub::wire_runtime_events(
  self : LocalBridgeSub,
  attempt : Int,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    guard self.active else { return }
    guard @interop.moonbit_bridge_root() is Some(root) &&
      @interop.js_prop(root, "events") is Some(extension_events) &&
      @interop.js_prop(root, "app") is Some(application_events) &&
      @interop.js_prop(extension_events, "on") is Some(_) &&
      @interop.js_prop(application_events, "on") is Some(_) else {
      if attempt <= 120 {
        scheduler.add(@cmd.delay(self.wire_runtime_events(attempt + 1), 25))
      }
      return
    }
    // Application events use `__MoonBit__.app.on`; keep their command id
    // typed while leaving command policy to the parent frontend.
    self.subscribe(application_events, "menu.command", event => {
      guard event_payload(event) is Some(payload) &&
        payload.get("command_id") is Some(String(command_id)) else {
        return
      }
      scheduler.add((self.dispatch)(MenuCommand(command_id~)))
    })
    // The notification extension stamps the owning run id in `payload`.
    self.subscribe(extension_events, "notification.click", event => {
      guard event_payload(event) is Some(payload) &&
        payload.get("payload") is Some(String(run_id)) &&
        !run_id.is_empty() else {
        return
      }
      scheduler.add((self.dispatch)(NotificationClicked(run_id~)))
    })
  })
}

///|
/// Register one injected event listener and retain its unsubscribe function
/// for this connection's unload boundary.
fn LocalBridgeSub::subscribe(
  self : LocalBridgeSub,
  events : @js.Value,
  name : String,
  handler : (@js.Value) -> Unit,
) -> Unit {
  let unsubscribe : @js.Value = events.apply_with_string("on", [
    @js.Value::cast_from(name),
    @js.Value::cast_from(handler),
  ])
  self.unsubscribers.push(unsubscribe)
}

///|
/// Decode a Proton event's structured-clone payload back into JSON fields.
/// A payload-less event reads as empty fields; malformed values are dropped.
fn event_payload(event : @js.Value) -> Map[String, Json]? {
  guard @interop.js_prop(event, "payload") is Some(payload) else {
    return Some(Map([]))
  }
  let json = payload.to_json() catch { _ => return None }
  guard json is Object(fields) else { return None }
  Some(fields)
}

///|
fn LocalBridgeSub::update_dispatch(
  self : LocalBridgeSub,
  dispatch : @cmd.Emit[Event],
) -> Unit {
  self.dispatch = dispatch
}

///|
/// Close the socket without emitting a down event (replacing the generation
/// must not start another retry) and retire every runtime listener.
fn LocalBridgeSub::unload(self : LocalBridgeSub) -> Unit {
  self.active = false
  @interop.ws_close(@interop.ChannelId::Local)
  for unsubscribe in self.unsubscribers {
    let _ : @js.Value = unsubscribe.apply(([] : FixedArray[@js.Value]))
  }
}
