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
/// The desktop bundle on main still speaks the original Proton op/event
/// names. Keeping that page on a separate bridge profile lets this native
/// host land before the frontend transport change without changing the
/// JSON-RPC catalog exposed to remote clients.
priv enum BridgeProfile {
  Catalog
  LegacyDesktop
}

///|
/// A page attachment waiting for the bridge actor to install it. The reply
/// makes either connect op a finite readiness handshake: success means the
/// actor has already emitted that profile's readiness event to this page.
priv struct BridgeAttachment {
  context : @app.AppCommandExtensionContext
  profile : BridgeProfile
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
  // The legacy desktop model keys turns by Int. Remote protocol ids are
  // opaque host-wide strings, so this adapter assigns page-local Int ids
  // without weakening the WebSocket protocol's identity.
  legacy_ids : Map[String, Int]
  remote_ids : Map[Int, String]
  mut next_legacy_id : Int
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
    legacy_ids: Map([]),
    remote_ids: Map([]),
    next_legacy_id: 1,
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
  for name in bridge.legacy_method_names() {
    descriptors.push(@app.AppCommandApiDescriptor::new(name))
  }
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
        bridge.attach(context, Catalog)
        Json::empty_object()
      })
      bridge.bind_legacy_ops(context)
    },
  )
}

///|
async fn DesktopBridgeActor::attach(
  self : DesktopBridgeActor,
  context : @app.AppCommandExtensionContext,
  profile : BridgeProfile,
) -> Unit {
  let reply : @async.Queue[Unit] = Queue(kind=Blocking(1))
  self.attachments.put({ context, profile, reply })
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
    let mut attached : (@app.AppCommandExtensionContext, BridgeProfile)? = None
    for ;; {
      match self.next_input(notifications, host_notifications) {
        Attach({ context, profile, reply }) => {
          // Managed Proton contexts queue events without raising. Publishing
          // readiness before acknowledging the attachment preserves the
          // connect handshake while avoiding request-task ownership.
          match profile {
            Catalog => context.emit("agent.connected", Json::empty_object())
            LegacyDesktop => context.emit("connected", Json::empty_object())
          }
          attached = Some((context, profile))
          reply.put(())
        }
        Deliver(notification) =>
          if attached is Some((context, profile)) {
            match profile {
              Catalog => context.emit(notification.method_, notification.params)
              LegacyDesktop =>
                if self.legacy_notification(notification)
                  is Some(legacy_notification) {
                  context.emit(
                    legacy_notification.method_,
                    legacy_notification.params,
                  )
                }
            }
          }
      }
    }
  })
}
