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
let session_event : @proton_contract.Event[@protocol.SessionCommitPayload] = @commands.extension_contract.event(
  @protocol.NotificationKind::SessionEvent.wire_name(),
)

///|
let subrun_progress : @proton_contract.Event[@protocol.SubrunProgressPayload] = @commands.extension_contract.event(
  @protocol.NotificationKind::SubrunProgress.wire_name(),
)

///|
let workflow_entry : @proton_contract.Event[@protocol.WorkflowEntryPayload] = @commands.extension_contract.event(
  @protocol.NotificationKind::WorkflowEntry.wire_name(),
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
let workspace_settings_changed_event : @proton_contract.Event[
  @protocol.WorkspaceSettingsPayload,
] = @commands.extension_contract.event(
  @protocol.NotificationKind::WorkspaceSettingsChanged.wire_name(),
)

///|
let worktree_changed_event : @proton_contract.Event[
  @protocol.WorktreeChangedPayload,
] = @commands.extension_contract.event(
  @protocol.NotificationKind::WorktreeChanged.wire_name(),
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
let codex_status_changed_event : @proton_contract.Event[Json] = @commands.extension_contract.event(
  @protocol.NotificationKind::CodexStatusChanged.wire_name(),
)

///|
let codex_notification_event : @proton_contract.Event[Json] = @commands.extension_contract.event(
  @protocol.NotificationKind::CodexNotification.wire_name(),
)

///|
let codex_server_request_event : @proton_contract.Event[Json] = @commands.extension_contract.event(
  @protocol.NotificationKind::CodexServerRequest.wire_name(),
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
let semantic_search_progress_event : @proton_contract.Event[
  @protocol.SemanticSearchProgressPayload,
] = @commands.extension_contract.event(
  @protocol.NotificationKind::SemanticSearchProgress.wire_name(),
)

///|
/// Window-local native browser view events (navigation,
/// title, load state), pumped in by `App::on_view_event` through
/// `DesktopBridgeActor::notify_browser_event`. It deliberately has no
/// `NotificationKind` — the shared wire catalog must never carry it to a
/// relay client, which has no native views.
let browser_event : @proton_contract.Event[Json] = @commands.extension_contract.event(
  "browser.event",
)

///|
/// A window-local invalidation, not shared host state. The renderer queries
/// Proton's current titlebar area; no native coordinates enter the relay.
let window_chrome_changed : @proton_contract.Event[@protocol.EmptyPayload] = @commands.extension_contract.event(
  "window.chrome_changed",
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
  WindowChromeChanged
}

///|
/// What the actor delivers to the attached page: a hub notification from
/// the shared catalog, or this window's own browser view event — which has
/// a Proton descriptor but deliberately no place in the wire catalog.
priv enum PageNotification {
  Hub(@protocol.Notification)
  BrowserEvent(Json)
  WindowChromeChanged
}

///|
priv struct PageEventTarget {
  events : @proton.WindowEventEmitter
}

///|
async fn PageEventTarget::emit(
  self : PageEventTarget,
  notification : PageNotification,
) -> Unit {
  // Matching the closed enum keeps each Proton descriptor paired with the
  // payload type that belongs to that event.
  match notification {
    Hub(AgentConnected(payload)) => self.events.emit(connected_event, payload)
    Hub(AgentStarted(payload)) => self.events.emit(started_event, payload)
    Hub(AgentEvent(payload)) => self.events.emit(agent_event, payload)
    Hub(AgentError(payload)) => self.events.emit(agent_error_event, payload)
    Hub(AgentFinished(payload)) => self.events.emit(finished_event, payload)
    Hub(SessionEvent(payload)) => self.events.emit(session_event, payload)
    Hub(SubrunProgress(payload)) => self.events.emit(subrun_progress, payload)
    Hub(WorkflowEntry(payload)) => self.events.emit(workflow_entry, payload)
    Hub(SessionChanged(payload)) =>
      self.events.emit(session_changed_event, payload)
    Hub(WorkspaceChanged(payload)) =>
      self.events.emit(workspace_changed_event, payload)
    Hub(WorkspaceSettingsChanged(payload)) =>
      self.events.emit(workspace_settings_changed_event, payload)
    Hub(WorktreeChanged(payload)) =>
      self.events.emit(worktree_changed_event, payload)
    Hub(SettingsChanged(payload)) =>
      self.events.emit(settings_changed_event, payload)
    Hub(SkillsChanged) => self.events.emit(skills_changed_event, NoPayload)
    Hub(UpdateDownloadProgress(payload)) =>
      self.events.emit(update_progress_event, payload)
    Hub(UpdateDownloaded(payload)) =>
      self.events.emit(update_downloaded_event, payload)
    Hub(UpdateDownloadFailed(payload)) =>
      self.events.emit(update_failed_event, payload)
    Hub(AuthChanged(payload)) => self.events.emit(auth_changed_event, payload)
    Hub(CodexStatusChanged(payload)) =>
      self.events.emit(codex_status_changed_event, payload)
    Hub(CodexNotification(payload)) =>
      self.events.emit(codex_notification_event, payload)
    Hub(CodexServerRequest(payload)) =>
      self.events.emit(codex_server_request_event, payload)
    Hub(LspDiagnostics(payload)) => self.events.emit(diagnostics_event, payload)
    Hub(FsChanged(payload)) => self.events.emit(fs_changed_event, payload)
    Hub(FsWatchFailed(payload)) =>
      self.events.emit(fs_watch_failed_event, payload)
    Hub(TerminalOutput(payload)) =>
      self.events.emit(terminal_output_event, payload)
    Hub(TerminalExit(payload)) => self.events.emit(terminal_exit_event, payload)
    Hub(SemanticSearchProgress(payload)) =>
      self.events.emit(semantic_search_progress_event, payload)
    BrowserEvent(payload) => self.events.emit(browser_event, payload)
    WindowChromeChanged => self.events.emit(window_chrome_changed, NoPayload)
  }
}

///|
/// Control work that must be ordered with notification delivery. The actor
/// holds a connect request only until it emits readiness and replies; it never
/// retains request-scoped state after the command returns.
priv enum BridgeInput {
  Control(BridgeControl)
  Deliver(PageNotification)
  // The hub's log rolled past this subscription's cursor: at least one
  // notification is gone for good, so only the ordinary BridgeReady resync
  // can restore truthful state. The actor has already skipped the retained
  // remainder, which is no longer a complete stream.
  SubscriptionLagged
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
  // Window-local browser view events that must reach this page without
  // touching the process-wide hub — a relay client has no native views, so
  // it must never see them.
  browser_events : @async.Queue[Json]
}

///|
pub fn DesktopBridgeActor::DesktopBridgeActor(
  state : @api.ApiState,
) -> DesktopBridgeActor {
  {
    state,
    host_connection: HostConnection(),
    // A page normally attaches once. A small bounded queue still permits a
    // reload to overlap the old page without allowing abandoned requests to
    // accumulate forever.
    controls: Queue(kind=Blocking(8)),
    browser_events: Queue(kind=Blocking(64)),
  }
}

///|
/// Queue a window-local browser view event for the attached page. The
/// delivery rules (declared descriptor, connect-then-window-ready ordering,
/// the bounded startup backlog) are the actor loop's, same as hub
/// notifications.
pub async fn DesktopBridgeActor::notify_browser_event(
  self : DesktopBridgeActor,
  params : Json,
) -> Unit {
  self.browser_events.put(params)
}

///|
pub async fn DesktopBridgeActor::notify_window_chrome_changed(
  self : DesktopBridgeActor,
) -> Unit {
  self.controls.put(WindowChromeChanged)
}

///|
pub fn openseek_capability(
  state : @api.ApiState,
  bridge : DesktopBridgeActor,
  views : BrowserViews,
) -> @proton_extension.RendererCapability {
  let endpoints = @api.endpoints(state, bridge.host_connection)
  endpoints.push(
    @endpoint.Endpoint::window(@commands.host_connect, async fn(context, _) {
      // A reloaded page allocates browser ids from scratch; the previous
      // page's native views must not survive its attachment.
      views.close_all()
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
  endpoints.push(
    @endpoint.Endpoint::window(@commands.session_export, async fn(
      context,
      payload,
    ) {
      export_session(context, state, payload)
    }),
  )
  for endpoint in window_endpoints(views) {
    endpoints.push(endpoint)
  }
  @proton_extension.capability(
    @proton_extension.typed(
      @commands.extension_contract,
      endpoints.map(endpoint => endpoint.route()),
      registrar => {
        for endpoint in endpoints {
          endpoint.bind(registrar)
        }
      },
    ),
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
/// The next hub notification, or the lag that stands in for the ones this
/// subscription missed. Remote clients reconnect their socket over a lag;
/// the desktop bridge is process-local with no socket supervisor, so it
/// reports the lag as input and resyncs the page instead of ending its
/// app-lifetime actor. The notifications the log still retains are skipped
/// too: once one is missing, rendering the rest only paints stale state
/// before the resync replaces it.
async fn next_hub_input(
  notifications : @broadcast.Subscription[@protocol.Notification],
) -> BridgeInput {
  Deliver(Hub(notifications.next())) catch {
    @broadcast.Lagged(missed~) => {
      @xlog.warn(category="transport") <?
        {
          "event": "hub_subscription_lagged",
          "transport": "desktop",
          "missed": missed,
        }
      notifications.skip_to_head()
      SubscriptionLagged
    }
    error => raise error
  }
}

///|
/// Prefer pending lifecycle/control work over another notification. Once neither
/// lane is ready, race their blocking reads; `any` cancels the losing read.
async fn DesktopBridgeActor::next_input(
  self : DesktopBridgeActor,
  notifications : @broadcast.Subscription[@protocol.Notification],
  host_notifications : @async.Queue[@protocol.Notification],
) -> BridgeInput {
  if self.controls.try_get() is Some(control) {
    return Control(control)
  }
  @async.any([
    () => Control(self.controls.get()),
    () => next_hub_input(notifications),
    () => Deliver(Hub(host_notifications.get())),
    () => Deliver(BrowserEvent(self.browser_events.get())),
  ])
}

///|
/// Own the window notification subscription and forward notifications to
/// the latest attached page. The connect request emits its own readiness event
/// through its request-scoped sender; later notifications use the window-owned
/// sender installed by Proton's lifecycle hook.
pub async fn DesktopBridgeActor::run(self : DesktopBridgeActor) -> Unit {
  let notifications = self.state.subscribe()
  let host_notifications : @async.Queue[@protocol.Notification] = Queue(
    kind=Blocking(64),
  )
  @async.with_task_group(group => {
    // The watcher and its queue belong to this bridge connection. Its events
    // never enter the process-wide hub, so a remote client's watch cannot
    // trigger desktop file refreshes (or vice versa).
    group.spawn_bg(allow_failure=true, () => {
      self.host_connection.run(
        notification => host_notifications.put(notification),
        notification => {
          // Progress is disposable. Do not let a slow renderer or a full
          // connection queue stall moongrep's stdout reader and its final reply.
          ignore(host_notifications.try_put(notification) catch { _ => false })
        },
      )
    })
    let mut connected = false
    let mut target : PageEventTarget? = None
    let pending : Array[PageNotification] = []
    for ;; {
      match self.next_input(notifications, host_notifications) {
        Control(control) =>
          match control {
            PageConnected(context, reply) => {
              // Serialize readiness before subsequent delivery so the
              // frontend can use it as the resync boundary.
              context.emit(connected_event, { stage: Accepted, })
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
            WindowChromeChanged =>
              deliver_to_page(connected, target, pending, WindowChromeChanged)
          }
        Deliver(notification) =>
          deliver_to_page(connected, target, pending, notification)
        // Readiness is the frontend's resync boundary. The subscription
        // already sits at the log's head, so every notification published
        // from here on queues behind this boundary.
        SubscriptionLagged =>
          deliver_to_page(
            connected,
            target,
            pending,
            Hub(AgentConnected({ stage: Accepted, })),
          )
      }
    }
  })
}

///|
async fn deliver_to_page(
  connected : Bool,
  target : PageEventTarget?,
  pending : Array[PageNotification],
  notification : PageNotification,
) -> Unit {
  guard connected else { return }
  if target is Some(target) {
    target.emit(notification)
  } else {
    if pending.length() == PendingNotificationCapacity {
      ignore(pending.remove(0))
    }
    pending.push(notification)
  }
}

///|
async test "a lagged hub subscription becomes a reconnect boundary" {
  let channel : @broadcast.Channel[@protocol.Notification] = Channel(capacity=1)
  let notifications = channel.subscribe()
  channel.publish(AgentConnected({ stage: Serving, }))
  channel.publish(AgentConnected({ stage: Serving, }))
  assert_true(next_hub_input(notifications) is SubscriptionLagged)
  // The retained Serving notification was skipped with the lag; the same
  // subscription keeps serving from the head.
  channel.publish(AgentConnected({ stage: Accepted, }))
  assert_true(
    next_hub_input(notifications)
    is Deliver(Hub(AgentConnected({ stage: Accepted, }))),
  )
}
