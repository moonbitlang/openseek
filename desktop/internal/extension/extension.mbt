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
/// The typed identity shared by every command and event exposed under
/// `window.__MoonBit__.openseek`.
let desktop_contract : @proton_contract.ExtensionContract = @proton_contract.extension(
  id=ExtensionId,
  js_namespace=ExtensionNamespace,
)

///|
/// The shared API catalog remains JSON-shaped because the browser and relay
/// transports both feed the same dynamic dispatcher.
let catalog_commands : Array[@proton_contract.Command[Json, Json]] = @api.method_names().map(fn(
    name,
  ) {
    desktop_contract.command(name)
  },
)

///|
let connect_command : @proton_contract.Command[Json, Json] = desktop_contract.command(
  ConnectMethod,
)

///|
let open_external_command : @proton_contract.Command[Json, Json] = desktop_contract.command(
  OpenExternalMethod,
)

///|
let connected_event : @proton_contract.Event[Json] = desktop_contract.event(
  "agent.connected",
)

///|
/// Proton requires one stable event descriptor per member name. Keep this list
/// aligned with the frontend listeners in `desktop/frontend/bridge.mbt`.
let notification_events : Map[String, @proton_contract.Event[Json]] = {
  "agent.connected": connected_event,
  "agent.started": desktop_contract.event("agent.started"),
  "agent.event": desktop_contract.event("agent.event"),
  "agent.error": desktop_contract.event("agent.error"),
  "agent.finished": desktop_contract.event("agent.finished"),
  "agent.durable": desktop_contract.event("agent.durable"),
  "session.event": desktop_contract.event("session.event"),
  "session.changed": desktop_contract.event("session.changed"),
  "workspace.changed": desktop_contract.event("workspace.changed"),
  "settings.changed": desktop_contract.event("settings.changed"),
  "skills.changed": desktop_contract.event("skills.changed"),
  "auth.changed": desktop_contract.event("auth.changed"),
  "lsp.diagnostics": desktop_contract.event("lsp.diagnostics"),
  "fs.changed": desktop_contract.event("fs.changed"),
  // PTY output and exit notifications originate from the connection-owned
  // terminal pump, but still need explicit Proton descriptors to reach xterm.
  "terminal.output": desktop_contract.event("terminal.output"),
  "terminal.exit": desktop_contract.event("terminal.exit"),
}

///|
/// The page connection and Proton's window lifecycle hook start independently.
/// Bound the short startup backlog rather than letting either side grow an
/// unbounded in-memory queue while it waits for the other.
const PendingNotificationCapacity = 64

///|
priv enum BridgeControl {
  PageConnected(@proton.CommandContext, @async.Queue[Unit])
  WindowReady(@proton.WindowEventEmitter)
  WindowClosed
}

///|
priv struct PageEventTarget {
  events : @proton.WindowEventEmitter
}

///|
async fn PageEventTarget::emit(
  self : PageEventTarget,
  notification : @api.Notification,
) -> Unit {
  // An undeclared event has no frontend listener either. Ignore it until both
  // explicit catalogs are updated instead of inventing a runtime route.
  if notification_events.get(notification.method_) is Some(event) {
    self.events.emit(event, notification.params)
  }
}

///|
/// Control work that must be ordered with notification delivery. The actor
/// holds a connect request only until it emits readiness and replies; it never
/// retains request-scoped state after the command returns.
priv enum BridgeInput {
  Control(BridgeControl)
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
  controls : @async.Queue[BridgeControl]
}

///|
pub fn DesktopBridgeActor::new(state : @api.ApiState) -> DesktopBridgeActor {
  {
    state,
    host_connection: @host.HostConnection::new(),
    // A page normally attaches once. A small bounded queue still permits a
    // reload to overlap the old page without allowing abandoned requests to
    // accumulate forever.
    controls: Queue(kind=Blocking(8)),
  }
}

///|
pub fn openseek_extension(
  state : @api.ApiState,
  bridge : DesktopBridgeActor,
) -> @proton_extension.Extension {
  let command_routes = catalog_commands.map(fn(command) {
    command.contract_route()
  })
  command_routes.push(connect_command.contract_route())
  command_routes.push(open_external_command.contract_route())
  @proton_extension.typed(desktop_contract, command_routes, fn(
    registrar,
  ) raise {
    for command in catalog_commands {
      let name = command.name()
      registrar.bind(command, async fn(_, params) {
        @api.dispatch(state, bridge.host_connection, name, params)
      })
    }
    registrar.bind(connect_command, async fn(context, _) {
      bridge.connect(context)
    })
    registrar.bind(open_external_command, async fn(_, params) {
      open_external(params)
    })
  })
}

///|
async fn DesktopBridgeActor::connect(
  self : DesktopBridgeActor,
  context : @proton.CommandContext,
) -> Json {
  // A reloaded page has no references to the previous page's emulator
  // instances, so its PTYs must not survive the new attachment.
  self.host_connection.close_terminals()
  let reply : @async.Queue[Unit] = Queue(kind=Blocking(1))
  self.controls.put(PageConnected(context, reply))
  reply.get()
  Json::empty_object()
}

///|
/// Installs the window-owned event destination used after the connect request
/// returns. Keeping it separate avoids retaining request-scoped task state.
pub async fn DesktopBridgeActor::window_ready(
  self : DesktopBridgeActor,
  events : @proton.WindowEventEmitter,
) -> Unit {
  self.controls.put(WindowReady(events))
}

///|
/// Detaches the event destination before the window-owned tasks are released.
pub async fn DesktopBridgeActor::window_closed(
  self : DesktopBridgeActor,
) -> Unit {
  self.controls.put(WindowClosed)
}

///|
/// Prefer pending lifecycle/control work over another notification. Once neither
/// lane is ready, race their blocking reads; `any` cancels the losing read.
async fn DesktopBridgeActor::next_input(
  self : DesktopBridgeActor,
  notifications : @async.Queue[@api.Notification],
  host_notifications : @async.Queue[@api.Notification],
) -> BridgeInput {
  if self.controls.try_get() is Some(control) {
    return Control(control)
  }
  @async.any([
    () => Control(self.controls.get()),
    () => Deliver(notifications.get()),
    () => Deliver(host_notifications.get()),
  ])
}

///|
/// Own the window notification subscription and forward notifications to
/// the latest attached page. The connect request emits its own readiness event
/// through its request-scoped sender; later notifications use the window-owned
/// sender installed by Proton's lifecycle hook.
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
    let mut connected = false
    let mut target : PageEventTarget? = None
    let pending : Array[@api.Notification] = []
    for ;; {
      match self.next_input(notifications, host_notifications) {
        Control(control) =>
          match control {
            PageConnected(context, reply) => {
              // Serialize readiness before subsequent delivery so the
              // frontend can use it as the resync boundary.
              context.emit(connected_event, Json::empty_object())
              connected = true
              reply.put(())
            }
            WindowReady(events) => {
              let next_target = PageEventTarget::{ events, }
              target = Some(next_target)
              if connected {
                for notification in pending {
                  next_target.emit(notification)
                }
              }
              pending.clear()
            }
            WindowClosed => {
              connected = false
              target = None
              pending.clear()
            }
          }
        Deliver(notification) =>
          if connected {
            if target is Some(target) {
              target.emit(notification)
            } else {
              if pending.length() == PendingNotificationCapacity {
                ignore(pending.remove(0))
              }
              pending.push(notification)
            }
          }
      }
    }
  })
}
