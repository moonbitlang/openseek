// The proton command extension: the desktop window's transport. Every
// catalog method is registered as one bridge op that feeds the shared
// dispatcher, so the webview and a remote browser speak the same names and
// payloads (docs/remote-protocol.md) — only the envelope differs. The op
// boundary stringifies raised errors into the rejection the webview
// displays.

///|
/// The extension id; the proton app enables it under this name.
pub const ExtensionId = "openseek-desktop"

///|
/// The `__MoonBit__` property the ops and events hang off:
/// `__MoonBit__.openseek["agent.start"](payload)`, events named
/// `openseek.<method>`.
const ExtensionNamespace = "openseek"

///|
/// The one bridge-only op: the webview calls it once to attach the current
/// page to the app-lifetime bridge actor. Not part of the wire catalog — a
/// WebSocket client's subscription is its connection.
const ConnectMethod = "host.connect"

///|
/// Open an external URL on the machine displaying the Proton window. Unlike
/// the shared host catalog, this command is deliberately local-only: a relay
/// browser must never make another device launch a URL.
const OpenExternalMethod = "shell.open_external"

///|
/// A page attachment waiting for the bridge actor to install it. The reply
/// makes `host.connect` a finite readiness handshake: success means the
/// actor has already emitted `agent.connected` to this page.
priv struct BridgeAttachment {
  context : @app.AppCommandExtensionContext
  reply : @async.Queue[Unit]
}

///|
priv enum BridgeInput {
  Attach(BridgeAttachment)
  Deliver(@api.Notification)
}

///|
/// The desktop window's bridge actor. It owns the hub subscription and the
/// current page attachment for the app's lifetime; extension ops only send
/// it messages and never retain resource-owning request tasks.
struct DesktopBridgeActor {
  state : @api.ApiState
  // The desktop page owns one filesystem watcher independently of every
  // remote WebSocket connection.
  host_connection : @host.HostConnection
  attachments : @async.Queue[BridgeAttachment]
}

///|
pub fn DesktopBridgeActor::new(state : @api.ApiState) -> DesktopBridgeActor {
  {
    state,
    host_connection: @host.HostConnection::new(),
    // A page normally attaches once. A small bounded queue still permits a
    // reload to overlap the old page without allowing abandoned requests to
    // accumulate forever.
    attachments: Queue(kind=Blocking(4)),
  }
}

///|
pub fn openseek_extension(
  state : @api.ApiState,
  bridge : DesktopBridgeActor,
) -> @app.AppCommandExtensionSpec {
  let descriptors = @api.method_names().map(name => {
    @app.AppCommandApiDescriptor::new(name)
  })
  descriptors.push(@app.AppCommandApiDescriptor::new(ConnectMethod))
  descriptors.push(@app.AppCommandApiDescriptor::new(OpenExternalMethod))
  @app.AppCommandExtensionSpec::new(
    ExtensionId,
    ExtensionNamespace,
    descriptors,
    context => {
      for name in @api.method_names() {
        context.op_async(name, (params : Json) => {
          @api.dispatch(state, bridge.host_connection, name, params)
        })
      }
      context.op_async(ConnectMethod, (_ : Json) => {
        bridge.attach(context)
        Json::empty_object()
      })
      context.op_async(OpenExternalMethod, open_external)
    },
  )
}

///|
async fn DesktopBridgeActor::attach(
  self : DesktopBridgeActor,
  context : @app.AppCommandExtensionContext,
) -> Unit {
  let reply : @async.Queue[Unit] = Queue(kind=Blocking(1))
  self.attachments.put({ context, reply })
  reply.get()
}

///|
/// Prefer a pending page attachment over another notification. Once neither
/// lane is ready, race their blocking reads; `any` cancels the losing read.
async fn DesktopBridgeActor::next_input(
  self : DesktopBridgeActor,
  notifications : @async.Queue[@api.Notification],
  host_notifications : @async.Queue[@api.Notification],
) -> BridgeInput {
  if (self.attachments.try_get() catch { _ => None }) is Some(attachment) {
    return Attach(attachment)
  }
  @async.any([
    () => Attach(self.attachments.get()),
    () => Deliver(notifications.get()),
    () => Deliver(host_notifications.get()),
  ])
}

///|
/// Own the window notification subscription and forward notifications to
/// the latest attached page. `agent.connected` is emitted while handling
/// Attach: the engine pump's original event may predate a load or reload,
/// so this is the page's readiness/resync signal.
pub async fn DesktopBridgeActor::run(self : DesktopBridgeActor) -> Unit {
  let notifications = self.state.subscribe()
  defer self.state.unsubscribe(notifications)
  let host_notifications : @async.Queue[@api.Notification] = Queue(
    kind=Blocking(64),
  )
  @async.with_task_group(group => {
    // The watcher and its queue belong to this bridge connection. Its events
    // never enter the process-wide hub, so a remote client's watch cannot
    // trigger desktop file refreshes (or vice versa).
    group.spawn_bg(allow_failure=true, () => {
      self.host_connection.run((method_, params) => {
        host_notifications.put({ method_, params })
      })
    })
    let mut attached : @app.AppCommandExtensionContext? = None
    for ;; {
      match self.next_input(notifications, host_notifications) {
        Attach({ context, reply }) => {
          context.emit("agent.connected", Json::empty_object())
          attached = Some(context)
          reply.put(())
        }
        Deliver(notification) =>
          if attached is Some(context) {
            context.emit(notification.method_, notification.params)
          }
      }
    }
  })
}
