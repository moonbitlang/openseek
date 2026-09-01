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
/// The one window-local event: native browser view events (navigation,
/// title, load state), pumped in by `App::on_view_event` through
/// `DesktopBridgeActor::notify_browser_event`. It deliberately has no
/// `NotificationKind` — the shared wire catalog must never carry it to a
/// relay client, which has no native views.
let browser_event : @proton_contract.Event[Json] = @commands.extension_contract.event(
  "browser.event",
)

///|
/// A window-local notification-stream discontinuity. The Proton request
/// transport is still alive, so this is deliberately distinct from
/// `agent.connected`: the page must resync host state without abandoning
/// ownership of requests whose promises can still settle.
let notification_gap_event : @proton_contract.Event[@protocol.EmptyPayload] = @commands.extension_contract.event(
  "notification.gap",
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
/// What the actor delivers to the attached page: a hub notification from
/// the shared catalog, or this window's own browser view event — which has
/// a Proton descriptor but deliberately no place in the wire catalog.
priv enum PageNotification {
  Hub(@protocol.Notification)
  BrowserEvent(Json)
  NotificationGap
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
    NotificationGap => self.events.emit(notification_gap_event, NoPayload)
  }
}

///|
/// Control work that must be ordered with notification delivery. The actor
/// holds a connect request only until it emits readiness and replies; it never
/// retains request-scoped state after the command returns.
priv enum BridgeInput {
  Control(BridgeControl)
  Deliver(PageNotification)
  // The process-wide hub evicted this subscriber after its bounded queue
  // filled. At least one notification is missing, so only a fresh subscription
  // followed by a notification-gap resync can restore truthful state without
  // pretending the still-live Proton request transport also disconnected.
  SubscriptionDropped
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
  // Monotonic observability for the app-lifetime subscription owner. Besides
  // making repeated recovery diagnosable, this lets the actor test wait for a
  // real overflow/resubscribe boundary without exposing hub internals.
  subscription_generation : Ref[Int]
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
    subscription_generation: Ref(0),
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
async fn next_hub_input(
  notifications : @async.Queue[@protocol.Notification],
) -> BridgeInput {
  Deliver(Hub(notifications.get())) catch {
    error if @async.is_being_cancelled() => raise error
    _ => SubscriptionDropped
  }
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
    () => next_hub_input(notifications),
    () => Deliver(Hub(host_notifications.get())),
    () => Deliver(BrowserEvent(self.browser_events.get())),
  ])
}

///|
async fn deliver_to_page(
  connected : Bool,
  target : PageEventTarget?,
  pending : Array[PageNotification],
  notification : PageNotification,
) -> Unit {
  if connected {
    if target is Some(target) {
      target.emit(notification)
    } else if notification is NotificationGap {
      // Everything already buffered belongs to the now-incomplete prefix.
      // Keep the boundary first so WindowReady resyncs before any frame from
      // the replacement subscription.
      pending.clear()
      pending.push(notification)
    } else {
      if pending.length() == PendingNotificationCapacity {
        // A gap is control state, not a disposable data frame. Keep it at
        // the front while bounding the post-gap startup backlog.
        if pending[0] is NotificationGap {
          ignore(pending.remove(1))
        } else {
          ignore(pending.remove(0))
        }
      }
      pending.push(notification)
    }
  }
}

///|
/// Own the window notification subscription and forward notifications to
/// the latest attached page. The connect request emits its own readiness event
/// through its request-scoped sender; later notifications use the window-owned
/// sender installed by Proton's lifecycle hook.
pub async fn DesktopBridgeActor::run(self : DesktopBridgeActor) -> Unit {
  // The single-slot owner follows the current subscription, so final cleanup
  // reaches the replacement without retaining every evicted queue (and its
  // full-size allocation) for the rest of the app lifetime.
  let subscription = [self.state.subscribe()]
  defer self.state.unsubscribe(subscription[0])
  let mut notifications = subscription[0]
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
          }
        Deliver(notification) =>
          deliver_to_page(connected, target, pending, notification)
        SubscriptionDropped => {
          // Remote clients reconnect their socket when the hub closes a slow
          // subscription. The desktop bridge is process-local and has no
          // socket supervisor, so renew it here instead of silently ending its
          // app-lifetime actor. Subscribe before publishing the gap boundary:
          // any concurrent notification then queues behind that resync signal.
          self.state.unsubscribe(notifications)
          notifications = self.state.subscribe()
          subscription[0] = notifications
          self.subscription_generation.val += 1
          deliver_to_page(connected, target, pending, NotificationGap)
        }
      }
    }
  })
}

///|
async test "a closed hub subscription becomes a reconnect boundary" {
  let notifications : @async.Queue[@protocol.Notification] = Queue(
    kind=Blocking(1),
  )
  notifications.close(clear=true)
  assert_true(next_hub_input(notifications) is SubscriptionDropped)
}

///|
async test "the pre-window backlog cannot evict its notification gap" {
  let pending : Array[PageNotification] = []
  for _ in 0..<8 {
    deliver_to_page(
      true,
      None,
      pending,
      Hub(AgentConnected({ stage: Serving, })),
    )
  }
  deliver_to_page(true, None, pending, NotificationGap)
  // The incomplete pre-gap prefix is gone and the marker stays first even
  // after more than one full startup backlog arrives behind it.
  for _ in 0..<(PendingNotificationCapacity * 2) {
    deliver_to_page(true, None, pending, Hub(SkillsChanged))
  }
  assert_eq(pending.length(), PendingNotificationCapacity)
  assert_true(pending[0] is NotificationGap)
}

///|
async test "the bridge actor resubscribes after a real hub eviction" {
  let state = @api.ApiState(engine="unused")
  let bridge = DesktopBridgeActor(state)
  @async.with_task_group(group => {
    group.spawn_bg(allow_failure=true, () => bridge.run())
    // Let the actor subscribe and park in its input race. Publishing below is
    // synchronous, so the woken reader cannot drain again before the burst
    // exceeds the hub's 1024-frame bound.
    @async.sleep(0)
    for _ in 0..<2048 {
      state.publish(SkillsChanged)
    }
    for _ in 0..<100 {
      if bridge.subscription_generation.val == 1 {
        group.return_immediately(())
        return
      }
      @async.sleep(1)
    }
    fail("the bridge actor did not replace its evicted subscription")
  })
}
