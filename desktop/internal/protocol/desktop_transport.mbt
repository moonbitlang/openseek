// Typed desktop notifications. Strings and JSON exist only where a transport
// reads or writes the public wire format.

///|
/// The stable identity of one server-pushed event. Transport registration
/// uses this payload-free enum; `Notification` below carries the associated
/// typed payload once an event is decoded.
pub(all) enum NotificationKind {
  AgentConnected
  AgentStarted
  AgentEvent
  AgentError
  AgentFinished
  AgentDurable
  SessionEvent
  SessionChanged
  WorkspaceChanged
  SettingsChanged
  SkillsChanged
  UpdateDownloadProgress
  UpdateDownloaded
  UpdateDownloadFailed
  AuthChanged
  LspDiagnostics
  FsChanged
  FsWatchFailed
  TerminalOutput
  TerminalExit
} derive(Debug, Eq, Hash)

///|
/// The stable public name written at a transport boundary.
pub fn NotificationKind::wire_name(self : NotificationKind) -> String {
  match self {
    AgentConnected => "agent.connected"
    AgentStarted => "agent.started"
    AgentEvent => "agent.event"
    AgentError => "agent.error"
    AgentFinished => "agent.finished"
    AgentDurable => "agent.durable"
    SessionEvent => "session.event"
    SessionChanged => "session.changed"
    WorkspaceChanged => "workspace.changed"
    SettingsChanged => "settings.changed"
    SkillsChanged => "skills.changed"
    UpdateDownloadProgress => "update.download_progress"
    UpdateDownloaded => "update.downloaded"
    UpdateDownloadFailed => "update.download_failed"
    AuthChanged => "auth.changed"
    LspDiagnostics => "lsp.diagnostics"
    FsChanged => "fs.changed"
    FsWatchFailed => "fs.watch_failed"
    TerminalOutput => "terminal.output"
    TerminalExit => "terminal.exit"
  }
}

///|
/// Decode an event name immediately after it crosses a transport.
pub fn NotificationKind::from_wire(name : String) -> NotificationKind? {
  match name {
    "agent.connected" => Some(AgentConnected)
    "agent.started" => Some(AgentStarted)
    "agent.event" => Some(AgentEvent)
    "agent.error" => Some(AgentError)
    "agent.finished" => Some(AgentFinished)
    "agent.durable" => Some(AgentDurable)
    "session.event" => Some(SessionEvent)
    "session.changed" => Some(SessionChanged)
    "workspace.changed" => Some(WorkspaceChanged)
    "settings.changed" => Some(SettingsChanged)
    "skills.changed" => Some(SkillsChanged)
    "update.download_progress" => Some(UpdateDownloadProgress)
    "update.downloaded" => Some(UpdateDownloaded)
    "update.download_failed" => Some(UpdateDownloadFailed)
    "auth.changed" => Some(AuthChanged)
    "lsp.diagnostics" => Some(LspDiagnostics)
    "fs.changed" => Some(FsChanged)
    "fs.watch_failed" => Some(FsWatchFailed)
    "terminal.output" => Some(TerminalOutput)
    "terminal.exit" => Some(TerminalExit)
    _ => None
  }
}

///|
/// Every event exposed by the desktop transports, in registration order.
pub fn NotificationKind::all() -> Array[NotificationKind] {
  [
    AgentConnected,
    AgentStarted,
    AgentEvent,
    AgentError,
    AgentFinished,
    AgentDurable,
    SessionEvent,
    SessionChanged,
    WorkspaceChanged,
    SettingsChanged,
    SkillsChanged,
    UpdateDownloadProgress,
    UpdateDownloaded,
    UpdateDownloadFailed,
    AuthChanged,
    LspDiagnostics,
    FsChanged,
    FsWatchFailed,
    TerminalOutput,
    TerminalExit,
  ]
}

///|
/// A server-pushed desktop event. Both the event case and its top-level
/// payload are compiler checked throughout the host and frontend. JSON is
/// introduced only by `from_wire`/`params` at the transport boundary.
pub(all) enum Notification {
  AgentConnected(ConnectedPayload)
  AgentStarted(StartedPayload)
  AgentEvent(AgentEventPayload)
  AgentError(AgentErrorPayload)
  AgentFinished(FinishedPayload)
  AgentDurable(DurableBoundaryPayload)
  SessionEvent(SessionCommitPayload)
  SessionChanged(SessionChangedPayload)
  WorkspaceChanged(WorkspacesChangedPayload)
  SettingsChanged(SettingsStatusPayload)
  SkillsChanged
  UpdateDownloadProgress(UpdateDownloadProgressPayload)
  UpdateDownloaded(UpdateDownloadedPayload)
  UpdateDownloadFailed(UpdateDownloadFailedPayload)
  AuthChanged(AuthStatusPayload)
  LspDiagnostics(DiagnosticsPayload)
  FsChanged(FsChangedPayload)
  FsWatchFailed(FsWatchFailedPayload)
  TerminalOutput(TerminalOutputPayload)
  TerminalExit(TerminalExitPayload)
} derive(Debug, Eq)

///|
/// Decode the event name at the WebSocket/Proton boundary. Unknown events are
/// deliberately ignored so newer hosts remain compatible with older pages.
pub fn Notification::from_wire(name : String, params : Json) -> Notification? {
  guard NotificationKind::from_wire(name) is Some(kind_) else { return None }
  match kind_ {
    AgentConnected =>
      Some(AgentConnected(@json.from_json(params) catch { _ => return None }))
    AgentStarted =>
      Some(AgentStarted(@json.from_json(params) catch { _ => return None }))
    AgentEvent =>
      Some(AgentEvent(@json.from_json(params) catch { _ => return None }))
    AgentError =>
      Some(AgentError(@json.from_json(params) catch { _ => return None }))
    AgentFinished =>
      Some(AgentFinished(@json.from_json(params) catch { _ => return None }))
    AgentDurable =>
      Some(AgentDurable(@json.from_json(params) catch { _ => return None }))
    SessionEvent =>
      Some(SessionEvent(@json.from_json(params) catch { _ => return None }))
    SessionChanged =>
      Some(SessionChanged(@json.from_json(params) catch { _ => return None }))
    WorkspaceChanged =>
      Some(WorkspaceChanged(@json.from_json(params) catch { _ => return None }))
    SettingsChanged =>
      Some(SettingsChanged(@json.from_json(params) catch { _ => return None }))
    SkillsChanged => Some(SkillsChanged)
    UpdateDownloadProgress =>
      Some(
        UpdateDownloadProgress(
          @json.from_json(params) catch {
            _ => return None
          },
        ),
      )
    UpdateDownloaded =>
      Some(UpdateDownloaded(@json.from_json(params) catch { _ => return None }))
    UpdateDownloadFailed =>
      Some(
        UpdateDownloadFailed(@json.from_json(params) catch { _ => return None }),
      )
    AuthChanged =>
      Some(AuthChanged(@json.from_json(params) catch { _ => return None }))
    LspDiagnostics =>
      Some(LspDiagnostics(@json.from_json(params) catch { _ => return None }))
    FsChanged =>
      Some(FsChanged(@json.from_json(params) catch { _ => return None }))
    FsWatchFailed =>
      Some(FsWatchFailed(@json.from_json(params) catch { _ => return None }))
    TerminalOutput =>
      Some(TerminalOutput(@json.from_json(params) catch { _ => return None }))
    TerminalExit =>
      Some(TerminalExit(@json.from_json(params) catch { _ => return None }))
  }
}

///|
/// The payload-free identity used by transport registration.
pub fn Notification::kind(self : Notification) -> NotificationKind {
  match self {
    AgentConnected(_) => AgentConnected
    AgentStarted(_) => AgentStarted
    AgentEvent(_) => AgentEvent
    AgentError(_) => AgentError
    AgentFinished(_) => AgentFinished
    AgentDurable(_) => AgentDurable
    SessionEvent(_) => SessionEvent
    SessionChanged(_) => SessionChanged
    WorkspaceChanged(_) => WorkspaceChanged
    SettingsChanged(_) => SettingsChanged
    SkillsChanged => SkillsChanged
    UpdateDownloadProgress(_) => UpdateDownloadProgress
    UpdateDownloaded(_) => UpdateDownloaded
    UpdateDownloadFailed(_) => UpdateDownloadFailed
    AuthChanged(_) => AuthChanged
    LspDiagnostics(_) => LspDiagnostics
    FsChanged(_) => FsChanged
    FsWatchFailed(_) => FsWatchFailed
    TerminalOutput(_) => TerminalOutput
    TerminalExit(_) => TerminalExit
  }
}

///|
/// The stable event name written only by transport adapters.
pub fn Notification::wire_name(self : Notification) -> String {
  self.kind().wire_name()
}

///|
/// Encode the typed payload only when a transport writes the public event.
pub fn Notification::params(self : Notification) -> Json {
  match self {
    AgentConnected(payload) => payload.to_json()
    AgentStarted(payload) => payload.to_json()
    AgentEvent(payload) => payload.to_json()
    AgentError(payload) => payload.to_json()
    AgentFinished(payload) => payload.to_json()
    AgentDurable(payload) => payload.to_json()
    SessionEvent(payload) => payload.to_json()
    SessionChanged(payload) => payload.to_json()
    WorkspaceChanged(payload) => payload.to_json()
    SettingsChanged(payload) => payload.to_json()
    SkillsChanged => Json::empty_object()
    UpdateDownloadProgress(payload) => payload.to_json()
    UpdateDownloaded(payload) => payload.to_json()
    UpdateDownloadFailed(payload) => payload.to_json()
    AuthChanged(payload) => payload.to_json()
    LspDiagnostics(payload) => payload.to_json()
    FsChanged(payload) => payload.to_json()
    FsWatchFailed(payload) => payload.to_json()
    TerminalOutput(payload) => payload.to_json()
    TerminalExit(payload) => payload.to_json()
  }
}

///|
test "desktop notifications round-trip at the wire edge" {
  let event = Notification::from_wire("terminal.exit", { "id": 1, "code": 0 })
  guard event is Some(event) else { fail("known notification was rejected") }
  assert_eq(event.wire_name(), "terminal.exit")
  assert_eq(event.params(), { "id": 1, "code": 0 })
  assert_eq(Notification::from_wire("future.event", {}), None)
}
