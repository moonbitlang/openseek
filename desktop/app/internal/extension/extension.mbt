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
let user_questions_event : @proton_contract.Event[
  @protocol.UserQuestionSnapshot,
] = @commands.extension_contract.event(
  @protocol.NotificationKind::UserQuestions.wire_name(),
)

///|
let approvals_event : @proton_contract.Event[@protocol.ApprovalSnapshot] = @commands.extension_contract.event(
  @protocol.NotificationKind::AgentApprovals.wire_name(),
)

///|
let share_progress_event : @proton_contract.Event[
  @protocol.SessionShareProgress,
] = @commands.extension_contract.event(
  @protocol.NotificationKind::SessionShareProgress.wire_name(),
)

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
let prediction_event : @proton_contract.Event[@protocol.PredictionReadyPayload] = @commands.extension_contract.event(
  @protocol.NotificationKind::AgentPrediction.wire_name(),
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
let session_artifacts_changed_event : @proton_contract.Event[
  @protocol.SessionArtifactsChangedPayload,
] = @commands.extension_contract.event(
  @protocol.NotificationKind::SessionArtifactsChanged.wire_name(),
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
/// Invalidate only the local page's system preference, never a relay client.
let system_appearance_changed : @proton_contract.Event[@protocol.EmptyPayload] = @commands.extension_contract.event(
  "app.system_appearance_changed",
)

///|
priv enum BridgeControl {
  PageConnected(@proton.CommandContext, @async.Queue[Unit])
  WindowReady(@proton.WindowEventEmitter)
  WindowClosed
  WindowChromeChanged
  SystemAppearanceChanged
}

///|
/// What the actor delivers to the attached page: a hub notification from
/// the shared catalog, or this window's own browser view event — which has
/// a Proton descriptor but deliberately no place in the wire catalog.
priv enum PageNotification {
  Hub(@protocol.Notification)
  BrowserEvent(Json)
  WindowChromeChanged
  SystemAppearanceChanged
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
    Hub(UserQuestions(payload)) =>
      self.events.emit(user_questions_event, payload)
    Hub(AgentApprovals(payload)) => self.events.emit(approvals_event, payload)
    Hub(AgentConnected(payload)) => self.events.emit(connected_event, payload)
    Hub(AgentStarted(payload)) => self.events.emit(started_event, payload)
    Hub(AgentEvent(payload)) => self.events.emit(agent_event, payload)
    Hub(AgentError(payload)) => self.events.emit(agent_error_event, payload)
    Hub(AgentFinished(payload)) => self.events.emit(finished_event, payload)
    Hub(AgentPrediction(payload)) => self.events.emit(prediction_event, payload)
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
    Hub(SessionArtifactsChanged(payload)) =>
      self.events.emit(session_artifacts_changed_event, payload)
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
    Hub(SessionShareProgress(payload)) =>
      self.events.emit(share_progress_event, payload)
    Hub(SemanticSearchProgress(payload)) =>
      self.events.emit(semantic_search_progress_event, payload)
    BrowserEvent(payload) => self.events.emit(browser_event, payload)
    WindowChromeChanged => self.events.emit(window_chrome_changed, NoPayload)
    SystemAppearanceChanged =>
      self.events.emit(system_appearance_changed, NoPayload)
  }
}

///|
/// Control work that must be ordered with notification delivery. The actor
/// holds a connect request only until it emits readiness and replies; it never
/// retains request-scoped state after the command returns.
priv enum BridgeInput {
  Control(BridgeControl)
  Deliver(PageNotification)
  // The inbox filled. Hub delivery stays paused until this marker reaches
  // the consumer, which resumes the subscription before triggering resync.
  SubscriptionLagged(@broadcast.Subscription[@protocol.Notification])
}

///|
/// Preserve the former hub log's burst allowance now that notifications go
/// straight into the window inbox instead of waiting in that shared log.
const BridgeInboxCapacity = 4096

///|
/// The desktop window's bridge actor. It owns the hub subscription and the
/// current page attachment for the app's lifetime; extension ops only send
/// it messages and never retain resource-owning request tasks.
struct DesktopBridgeActor {
  state : @api.ApiState
  // The desktop page owns one filesystem watcher independently of every
  // remote WebSocket connection.
  host_connection : @host.HostConnection
  // All producers write directly to this window-owned mailbox. Local
  // control, browser, filesystem and terminal events never enter the hub.
  inbox : @async.Queue[BridgeInput]
}

///|
pub fn DesktopBridgeActor::DesktopBridgeActor(
  state : @api.ApiState,
) -> DesktopBridgeActor {
  {
    state,
    host_connection: HostConnection(),
    inbox: Queue(kind=Blocking(BridgeInboxCapacity)),
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
  self.inbox.put(Deliver(BrowserEvent(params)))
}

///|
pub async fn DesktopBridgeActor::notify_window_chrome_changed(
  self : DesktopBridgeActor,
) -> Unit {
  self.inbox.put(Control(WindowChromeChanged))
}

///|
pub async fn DesktopBridgeActor::notify_system_appearance_changed(
  self : DesktopBridgeActor,
) -> Unit {
  self.inbox.put(Control(SystemAppearanceChanged))
}

///|
pub fn openseek_capability(
  state : @api.ApiState,
  bridge : DesktopBridgeActor,
  views : BrowserViews,
) -> @proton_extension.RendererCapability {
  let endpoints = @api.endpoints(
    state,
    bridge.host_connection,
    local_share=true,
    on_share_progress=payload => {
      bridge.inbox.put(Deliver(Hub(SessionShareProgress(payload))))
    },
  )
  let window_only = [
    WindowEndpoint(@commands.host_open_path_preview, (_, payload) => {
      @host.open_path_preview(payload)
    }),
    WindowEndpoint(@commands.host_connect, (context, _) => {
      // A reloaded page allocates browser ids from scratch; the previous
      // page's native views must not survive its attachment.
      views.close_all()
      let reply = bridge.connect(context)
      views.page_is_connected()
      reply
    }),
    WindowEndpoint(@commands.shell_open_external, (_, payload) => {
      open_external(payload, allow_file=true)
    }),
    WindowEndpoint(@commands.account_session, (_, _) => {
      session: state.auth_store().account(),
    }),
    WindowEndpoint(@commands.session_snapshot_save, (context, payload) => {
      save_export(context, payload.session, payload.html)
    }),
    WindowEndpoint(@commands.session_export, (context, payload) => {
      export_session(context, state, payload)
    }),
    WindowEndpoint(@commands.host_pick_attachment, (context, _) => {
      pick_attachment(context)
    }),
  ]
  for endpoint in window_endpoints(views) {
    window_only.push(endpoint)
  }
  @proton_extension.capability(
    @proton_extension.typed(@commands.extension_contract, registrar => {
      for endpoint in endpoints {
        bind_shared(registrar, endpoint)
      }
      for endpoint in window_only {
        endpoint.bind(registrar)
      }
    }),
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
  self.inbox.put(Control(PageConnected(context, reply)))
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
  self.inbox.put(Control(WindowReady(events)))
}

///|
/// Detaches the event destination before the window-owned tasks are released.
pub async fn DesktopBridgeActor::window_closed(
  self : DesktopBridgeActor,
) -> Unit {
  self.inbox.put(Control(WindowClosed))
}

///|
/// Register the window inbox directly with the hub. Overflow schedules at
/// most one recovery marker: the subscription is paused before this handler
/// runs, and stays paused until the actor consumes the marker. Only recovery
/// waits for mailbox space; ordinary hub publication always stays synchronous.
fn DesktopBridgeActor::subscribe(
  self : DesktopBridgeActor,
  group : @async.TaskGroup[Unit],
) -> @broadcast.Subscription[@protocol.Notification] {
  self.state.subscribe(
    self.inbox,
    map=notification => Some(Deliver(Hub(notification))),
    on_lag=subscription => {
      @xlog.warn(category="transport") <?
        { "event": "hub_subscription_lagged", "transport": "desktop" }
      group.spawn_bg(() => self.inbox.put(SubscriptionLagged(subscription)))
    },
  )
}

///|
/// Own the window notification subscription and forward notifications to
/// the latest attached page. The connect request emits its own readiness event
/// through its request-scoped sender; later notifications use the window-owned
/// sender installed by Proton's lifecycle hook.
pub async fn DesktopBridgeActor::run(self : DesktopBridgeActor) -> Unit {
  @async.with_task_group(group => {
    let subscription = self.subscribe(group)
    defer subscription.close()
    // The watcher and the inbox belong to this bridge connection. Its events
    // never enter the process-wide hub, so a remote client's watch cannot
    // trigger desktop file refreshes (or vice versa).
    group.spawn_bg(allow_failure=true, () => {
      self.host_connection.run(
        notification => self.inbox.put(Deliver(Hub(notification))),
        notification => {
          // Progress is disposable. Do not let a slow renderer or a full
          // connection queue stall moongrep's stdout reader and its final reply.
          ignore(
            self.inbox.try_put(Deliver(Hub(notification))) catch {
              _ => false
            },
          )
        },
      )
    })
    let mut connected = false
    let mut target : PageEventTarget? = None
    let pending : Array[PageNotification] = []
    for ;; {
      match self.inbox.get() {
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
            SystemAppearanceChanged =>
              deliver_to_page(
                connected,
                target,
                pending,
                SystemAppearanceChanged,
              )
          }
        Deliver(notification) =>
          deliver_to_page(connected, target, pending, notification)
        SubscriptionLagged(subscription) => {
          // Resume before emitting readiness: snapshot requests made by the
          // frontend cannot race a still-paused subscription. Every later
          // publication is queued behind this boundary.
          subscription.resume_delivery()
          deliver_to_page(
            connected,
            target,
            pending,
            Hub(AgentConnected({ stage: Accepted, })),
          )
        }
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
async test "a full inbox preserves local events before the hub resync boundary" {
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      let state = @api.ApiState(engine="unused")
      let bridge = DesktopBridgeActor(state)
      let subscription = bridge.subscribe(group)
      defer subscription.close()
      for value in 0..<BridgeInboxCapacity {
        bridge.notify_browser_event(Json(value))
      }
      state.publish(AgentConnected({ stage: Serving, }))
      // Further publications must not schedule extra recovery tasks/markers.
      state.publish(AgentConnected({ stage: Serving, }))
      for value in 0..<BridgeInboxCapacity {
        assert_true(
          bridge.inbox.get() is Deliver(BrowserEvent(actual)) &&
          actual == Json(value),
        )
      }
      guard bridge.inbox.get() is SubscriptionLagged(paused) else {
        fail("missing resync boundary after the full inbox")
      }
      paused.resume_delivery()
      state.publish(AgentConnected({ stage: Accepted, }))
      assert_true(
        bridge.inbox.get() is Deliver(Hub(AgentConnected({ stage: Accepted, }))),
      )
      assert_true(bridge.inbox.try_get() is None)
    })
  })
}
