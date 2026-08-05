// The proton command extension: the desktop window's transport. Every
// catalog method is registered as one bridge op that feeds the shared
// dispatcher, so the webview and a remote browser speak the same names and
// payloads (docs/remote-protocol.md) — only the envelope differs. The op
// boundary stringifies raised errors into the rejection the webview
// displays.

///|
/// Command identities and their concrete payload/reply pairs live in
/// `internal/commands`; this package only binds them to native handlers.

///|
let connected_event : @proton_contract.Event[@protocol.ConnectedPayload] = @commands.extension_contract.event(
  @protocol.NotificationKind::AgentConnected.wire_name(),
)

///|
let started_event : @proton_contract.Event[@protocol.StartedPayload] = @commands.extension_contract.event(
  @protocol.NotificationKind::AgentStarted.wire_name(),
)

///|
let agent_event : @proton_contract.Event[@protocol.AgentEventPayload] = @commands.extension_contract.event(
  @protocol.NotificationKind::AgentEvent.wire_name(),
)

///|
let agent_error_event : @proton_contract.Event[@protocol.AgentErrorPayload] = @commands.extension_contract.event(
  @protocol.NotificationKind::AgentError.wire_name(),
)

///|
let finished_event : @proton_contract.Event[@protocol.FinishedPayload] = @commands.extension_contract.event(
  @protocol.NotificationKind::AgentFinished.wire_name(),
)

///|
let durable_event : @proton_contract.Event[@protocol.DurableBoundaryPayload] = @commands.extension_contract.event(
  @protocol.NotificationKind::AgentDurable.wire_name(),
)

///|
let session_event : @proton_contract.Event[@protocol.SessionCommitPayload] = @commands.extension_contract.event(
  @protocol.NotificationKind::SessionEvent.wire_name(),
)

///|
let session_changed_event : @proton_contract.Event[
  @protocol.SessionChangedPayload,
] = @commands.extension_contract.event(
  @protocol.NotificationKind::SessionChanged.wire_name(),
)

///|
let workspace_changed_event : @proton_contract.Event[
  @protocol.WorkspacesChangedPayload,
] = @commands.extension_contract.event(
  @protocol.NotificationKind::WorkspaceChanged.wire_name(),
)

///|
let settings_changed_event : @proton_contract.Event[
  @protocol.SettingsStatusPayload,
] = @commands.extension_contract.event(
  @protocol.NotificationKind::SettingsChanged.wire_name(),
)

///|
let skills_changed_event : @proton_contract.Event[@protocol.EmptyPayload] = @commands.extension_contract.event(
  @protocol.NotificationKind::SkillsChanged.wire_name(),
)

///|
let update_progress_event : @proton_contract.Event[
  @protocol.UpdateDownloadProgressPayload,
] = @commands.extension_contract.event(
  @protocol.NotificationKind::UpdateDownloadProgress.wire_name(),
)

///|
let update_downloaded_event : @proton_contract.Event[
  @protocol.UpdateDownloadedPayload,
] = @commands.extension_contract.event(
  @protocol.NotificationKind::UpdateDownloaded.wire_name(),
)

///|
let update_failed_event : @proton_contract.Event[
  @protocol.UpdateDownloadFailedPayload,
] = @commands.extension_contract.event(
  @protocol.NotificationKind::UpdateDownloadFailed.wire_name(),
)

///|
let auth_changed_event : @proton_contract.Event[@protocol.AuthStatusPayload] = @commands.extension_contract.event(
  @protocol.NotificationKind::AuthChanged.wire_name(),
)

///|
let diagnostics_event : @proton_contract.Event[@protocol.DiagnosticsPayload] = @commands.extension_contract.event(
  @protocol.NotificationKind::LspDiagnostics.wire_name(),
)

///|
let fs_changed_event : @proton_contract.Event[@protocol.FsChangedPayload] = @commands.extension_contract.event(
  @protocol.NotificationKind::FsChanged.wire_name(),
)

///|
let fs_watch_failed_event : @proton_contract.Event[
  @protocol.FsWatchFailedPayload,
] = @commands.extension_contract.event(
  @protocol.NotificationKind::FsWatchFailed.wire_name(),
)

///|
let terminal_output_event : @proton_contract.Event[
  @protocol.TerminalOutputPayload,
] = @commands.extension_contract.event(
  @protocol.NotificationKind::TerminalOutput.wire_name(),
)

///|
let terminal_exit_event : @proton_contract.Event[@protocol.TerminalExitPayload] = @commands.extension_contract.event(
  @protocol.NotificationKind::TerminalExit.wire_name(),
)

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
  notification : @protocol.Notification,
) -> Unit {
  // Matching the closed enum keeps each Proton descriptor paired with the
  // payload type that belongs to that event.
  match notification {
    AgentConnected(payload) => self.events.emit(connected_event, payload)
    AgentStarted(payload) => self.events.emit(started_event, payload)
    AgentEvent(payload) => self.events.emit(agent_event, payload)
    AgentError(payload) => self.events.emit(agent_error_event, payload)
    AgentFinished(payload) => self.events.emit(finished_event, payload)
    AgentDurable(payload) => self.events.emit(durable_event, payload)
    SessionEvent(payload) => self.events.emit(session_event, payload)
    SessionChanged(payload) => self.events.emit(session_changed_event, payload)
    WorkspaceChanged(payload) =>
      self.events.emit(workspace_changed_event, payload)
    SettingsChanged(payload) =>
      self.events.emit(settings_changed_event, payload)
    SkillsChanged => self.events.emit(skills_changed_event, NoPayload)
    UpdateDownloadProgress(payload) =>
      self.events.emit(update_progress_event, payload)
    UpdateDownloaded(payload) =>
      self.events.emit(update_downloaded_event, payload)
    UpdateDownloadFailed(payload) =>
      self.events.emit(update_failed_event, payload)
    AuthChanged(payload) => self.events.emit(auth_changed_event, payload)
    LspDiagnostics(payload) => self.events.emit(diagnostics_event, payload)
    FsChanged(payload) => self.events.emit(fs_changed_event, payload)
    FsWatchFailed(payload) => self.events.emit(fs_watch_failed_event, payload)
    TerminalOutput(payload) => self.events.emit(terminal_output_event, payload)
    TerminalExit(payload) => self.events.emit(terminal_exit_event, payload)
  }
}

///|
/// Control work that must be ordered with notification delivery. The actor
/// holds a connect request only until it emits readiness and replies; it never
/// retains request-scoped state after the command returns.
priv enum BridgeInput {
  Control(BridgeControl)
  Deliver(@protocol.Notification)
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
  let endpoints = @api.endpoints(state, bridge.host_connection)
  endpoints.push(
    @endpoint.Endpoint::window(@commands.host_connect, async fn(context, _) {
      bridge.connect(context)
    }),
  )
  endpoints.push(
    @endpoint.Endpoint::window(@commands.shell_open_external, async fn(
      _,
      payload,
    ) {
      open_external(payload)
    }),
  )
  @proton_extension.typed(
    @commands.extension_contract,
    endpoints.map(endpoint => endpoint.route()),
    registrar => {
      for endpoint in endpoints {
        endpoint.bind(registrar)
      }
    },
  )
}

///|
async fn DesktopBridgeActor::connect(
  self : DesktopBridgeActor,
  context : @proton.CommandContext,
) -> @protocol.EmptyReply {
  // A reloaded page has no references to the previous page's emulator
  // instances, so its PTYs must not survive the new attachment.
  self.host_connection.close_terminals()
  let reply : @async.Queue[Unit] = Queue(kind=Blocking(1))
  self.controls.put(PageConnected(context, reply))
  reply.get()
  Acknowledged
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
  notifications : @async.Queue[@protocol.Notification],
  host_notifications : @async.Queue[@protocol.Notification],
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
  let host_notifications : @async.Queue[@protocol.Notification] = Queue(
    kind=Blocking(64),
  )
  @async.with_task_group(group => {
    // The watcher and its queue belong to this bridge connection. Its events
    // never enter the process-wide hub, so a remote client's watch cannot
    // trigger desktop file refreshes (or vice versa).
    group.spawn_bg(allow_failure=true, () => {
      self.host_connection.run(notification => {
        host_notifications.put(notification)
      })
    })
    let mut connected = false
    let mut target : PageEventTarget? = None
    let pending : Array[@protocol.Notification] = []
    for ;; {
      match self.next_input(notifications, host_notifications) {
        Control(control) =>
          match control {
            PageConnected(context, reply) => {
              // Serialize readiness before subsequent delivery so the
              // frontend can use it as the resync boundary.
              context.emit(connected_event, { ready: None })
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
