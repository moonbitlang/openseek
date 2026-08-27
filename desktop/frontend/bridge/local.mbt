// The desktop window's injected Proton connection. The request API and event
// actors appear independently, so installation waits for the complete surface
// before registering listeners or attaching to the host notification actor.

///|
priv struct LocalBridgeSub {
  mut dispatch : @cmd.Emit[Event]
  mut active : Bool
  unsubscribers : Array[@js.Value]
}

///|
fn LocalBridgeSub::LocalBridgeSub(
  dispatch : @cmd.Emit[Event],
) -> LocalBridgeSub {
  { dispatch, active: true, unsubscribers: [] }
}

///|
fn LocalBridgeSub::subscription_key() -> String {
  "host-bridge:local"
}

///|
/// Wait for Proton to inject the bridge, wire this connection's events, and
/// attach to the host. The 25ms retries add up to roughly three seconds.
/// Unloading makes every already queued retry harmless.
fn LocalBridgeSub::install(self : LocalBridgeSub, attempt : Int) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    guard self.active else { return }
    guard @interop.openseek_api() is Some(request_api) &&
      @interop.moonbit_bridge_root() is Some(root) &&
      @interop.js_prop(root, "events") is Some(extension_events) &&
      @interop.js_prop(root, "app") is Some(application_events) &&
      @interop.js_prop(request_api, "host.connect") is Some(_) &&
      @interop.js_prop(request_api, "agent.start") is Some(_) &&
      @interop.js_prop(extension_events, "on") is Some(_) &&
      @interop.js_prop(application_events, "on") is Some(_) else {
      if attempt > 120 {
        scheduler.add(
          (self.dispatch)(
            Event::Unavailable(
              channel=@interop.ChannelId::Local,
              message="Bridge unavailable",
            ),
          ),
        )
      } else {
        scheduler.add(@cmd.delay(self.install(attempt + 1), 25))
      }
      return
    }
    self.wire(scheduler, extension_events, application_events)
    self.open_host_connection(scheduler, request_api)
  })
}

///|
/// Attach this page to the host's app-lifetime notification actor. The call
/// resolves after the actor emits its readiness event.
fn LocalBridgeSub::open_host_connection(
  self : LocalBridgeSub,
  scheduler : &@cmd.Scheduler,
  api : @js.Value,
) -> Unit {
  @js.async_run(() => {
    let _ : @js.Value = @interop.js_method_promise(
      api,
      "host.connect",
      @js.Object::new().to_value(),
    ).wait() catch {
      error => {
        guard self.active else { return }
        scheduler.add(
          (self.dispatch)(
            Event::Unavailable(
              channel=@interop.ChannelId::Local,
              message=@interop.bridge_error_text(error),
            ),
          ),
        )
        return
      }
    }
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
/// Notification kinds exposed by the host extension. Proton needs one
/// listener per kind, so this derives directly from the shared catalog.
fn LocalBridgeSub::notification_kinds() -> Array[@protocol.NotificationKind] {
  @protocol.NotificationKind::all()
}

///|
/// Decode a Proton event's structured-clone payload back into JSON fields.
/// A payload-less event reads as empty fields; malformed values are dropped.
fn LocalBridgeSub::event_payload(
  self : LocalBridgeSub,
  event : @js.Value,
) -> Map[String, Json]? {
  guard self.active else { return None }
  guard @interop.js_prop(event, "payload") is Some(payload) else {
    return Some(Map([]))
  }
  let json = payload.to_json() catch { _ => return None }
  guard json is Object(fields) else { return None }
  Some(fields)
}

///|
fn LocalBridgeSub::wire(
  self : LocalBridgeSub,
  scheduler : &@cmd.Scheduler,
  extension_events : @js.Value,
  application_events : @js.Value,
) -> Unit {
  for kind_ in LocalBridgeSub::notification_kinds() {
    let method_ = kind_.wire_name()
    let handler = (event : @js.Value) => {
      guard self.event_payload(event) is Some(payload) &&
        @protocol.Notification::from_wire(method_, Json::object(payload))
        is Some(notification) else {
        return
      }
      scheduler.add(
        (self.dispatch)(
          Event::Notification(channel=@interop.ChannelId::Local, notification~),
        ),
      )
    }
    self.subscribe(extension_events, "openseek." + method_, handler)
  }
  // Native browser-view events are intentionally window-local rather than
  // shared protocol notifications. The parent frontend owns their UI decode.
  self.subscribe(extension_events, "openseek.browser.event", event => {
    guard self.event_payload(event) is Some(payload) else { return }
    scheduler.add((self.dispatch)(Event::BrowserEvent(payload~)))
  })
  // Application events use `__MoonBit__.app.on`; keep their command id typed
  // while leaving command policy to the parent frontend.
  self.subscribe(application_events, "menu.command", event => {
    guard self.event_payload(event) is Some(payload) &&
      payload.get("command_id") is Some(String(command_id)) else {
      return
    }
    scheduler.add((self.dispatch)(Event::MenuCommand(command_id~)))
  })
  // The notification extension stamps the owning run id in `payload`.
  self.subscribe(extension_events, "notification.click", event => {
    guard self.event_payload(event) is Some(payload) &&
      payload.get("payload") is Some(String(run_id)) &&
      !run_id.is_empty() else {
      return
    }
    scheduler.add((self.dispatch)(Event::NotificationClicked(run_id~)))
  })
}

///|
fn LocalBridgeSub::update_dispatch(
  self : LocalBridgeSub,
  dispatch : @cmd.Emit[Event],
) -> Unit {
  self.dispatch = dispatch
}

///|
/// Retire every Proton listener and make queued injection retries inert.
fn LocalBridgeSub::unload(self : LocalBridgeSub) -> Unit {
  self.active = false
  for unsubscribe in self.unsubscribers {
    let _ : @js.Value = unsubscribe.apply(([] : Array[@js.Value]))
  }
}

///|
test "local bridge listens to the shared host notification catalog" {
  let kinds = LocalBridgeSub::notification_kinds()
  assert_true(kinds.contains(@protocol.NotificationKind::CodexStatusChanged))
  assert_true(kinds.contains(@protocol.NotificationKind::CodexNotification))
  assert_true(kinds.contains(@protocol.NotificationKind::CodexServerRequest))
  assert_true(kinds.contains(@protocol.NotificationKind::AuthChanged))
  assert_true(kinds.contains(@protocol.NotificationKind::SkillsChanged))
  assert_true(kinds.contains(@protocol.NotificationKind::FsWatchFailed))
  assert_true(kinds.contains(@protocol.NotificationKind::SessionEvent))
  assert_true(kinds.contains(@protocol.NotificationKind::WorkspaceChanged))
  assert_true(kinds.contains(@protocol.NotificationKind::WorktreeChanged))
  assert_true(kinds.contains(@protocol.NotificationKind::UpdateDownloaded))
  assert_true(
    kinds.contains(@protocol.NotificationKind::UpdateDownloadProgress),
  )
  assert_true(kinds.contains(@protocol.NotificationKind::UpdateDownloadFailed))
}
