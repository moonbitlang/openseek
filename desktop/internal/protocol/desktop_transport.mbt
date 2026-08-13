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
  SubrunProgress
  SessionChanged
  WorkspaceChanged
  WorkspaceSettingsChanged
  WorktreeChanged
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
    SubrunProgress => "subrun.progress"
    SessionChanged => "session.changed"
    WorkspaceChanged => "workspace.changed"
    WorkspaceSettingsChanged => "workspace.settings_changed"
    WorktreeChanged => "worktree.changed"
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
    SubrunProgress,
    SessionChanged,
    WorkspaceChanged,
    WorkspaceSettingsChanged,
    WorktreeChanged,
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
  SubrunProgress(SubrunProgressPayload)
  SessionChanged(SessionChangedPayload)
  WorkspaceChanged(WorkspacesChangedPayload)
  WorkspaceSettingsChanged(WorkspaceSettingsPayload)
  WorktreeChanged(WorktreeChangedPayload)
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
/// Decode the event name and payload together at the WebSocket/Proton boundary.
/// Unknown events are deliberately ignored so newer hosts remain compatible
/// with older pages. Matching the wire name here avoids a second name-to-kind
/// table that would only be consumed by this decoder.
pub fn Notification::from_wire(name : String, params : Json) -> Notification? {
  match name {
    "agent.connected" =>
      Some(AgentConnected(@json.from_json(params) catch { _ => return None }))
    "agent.started" =>
      Some(AgentStarted(@json.from_json(params) catch { _ => return None }))
    "agent.event" =>
      Some(AgentEvent(@json.from_json(params) catch { _ => return None }))
    "agent.error" =>
      Some(AgentError(@json.from_json(params) catch { _ => return None }))
    "agent.finished" =>
      Some(AgentFinished(@json.from_json(params) catch { _ => return None }))
    "agent.durable" =>
      Some(AgentDurable(@json.from_json(params) catch { _ => return None }))
    "session.event" =>
      Some(SessionEvent(@json.from_json(params) catch { _ => return None }))
    "subrun.progress" =>
      Some(SubrunProgress(@json.from_json(params) catch { _ => return None }))
    "session.changed" =>
      Some(SessionChanged(@json.from_json(params) catch { _ => return None }))
    "workspace.changed" =>
      Some(WorkspaceChanged(@json.from_json(params) catch { _ => return None }))
    "workspace.settings_changed" =>
      Some(
        WorkspaceSettingsChanged(
          @json.from_json(params) catch {
            _ => return None
          },
        ),
      )
    "worktree.changed" =>
      Some(WorktreeChanged(@json.from_json(params) catch { _ => return None }))
    "settings.changed" =>
      Some(SettingsChanged(@json.from_json(params) catch { _ => return None }))
    "skills.changed" => Some(SkillsChanged)
    "update.download_progress" =>
      Some(
        UpdateDownloadProgress(
          @json.from_json(params) catch {
            _ => return None
          },
        ),
      )
    "update.downloaded" =>
      Some(UpdateDownloaded(@json.from_json(params) catch { _ => return None }))
    "update.download_failed" =>
      Some(
        UpdateDownloadFailed(@json.from_json(params) catch { _ => return None }),
      )
    "auth.changed" =>
      Some(AuthChanged(@json.from_json(params) catch { _ => return None }))
    "lsp.diagnostics" =>
      Some(LspDiagnostics(@json.from_json(params) catch { _ => return None }))
    "fs.changed" =>
      Some(FsChanged(@json.from_json(params) catch { _ => return None }))
    "fs.watch_failed" =>
      Some(FsWatchFailed(@json.from_json(params) catch { _ => return None }))
    "terminal.output" =>
      Some(TerminalOutput(@json.from_json(params) catch { _ => return None }))
    "terminal.exit" =>
      Some(TerminalExit(@json.from_json(params) catch { _ => return None }))
    _ => None
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
    SubrunProgress(_) => SubrunProgress
    SessionChanged(_) => SessionChanged
    WorkspaceChanged(_) => WorkspaceChanged
    WorkspaceSettingsChanged(_) => WorkspaceSettingsChanged
    WorktreeChanged(_) => WorktreeChanged
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
    SubrunProgress(payload) => payload.to_json()
    SessionChanged(payload) => payload.to_json()
    WorkspaceChanged(payload) => payload.to_json()
    WorkspaceSettingsChanged(payload) => payload.to_json()
    WorktreeChanged(payload) => payload.to_json()
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
  let settings = Notification::from_wire("workspace.settings_changed", {
    "workspace": "/home/u/proj",
    "worktree_mode": true,
    "checkout_submodules": false,
  })
  guard settings is Some(settings) else {
    fail("workspace settings notification was rejected")
  }
  assert_eq(settings.wire_name(), "workspace.settings_changed")
  assert_eq(settings.params(), {
    "workspace": "/home/u/proj",
    "worktree_mode": true,
    "checkout_submodules": false,
  })
  assert_eq(Notification::from_wire("future.event", {}), None)
}

///|
test "malformed agent errors remain visible notifications" {
  let cases : Array[Json] = [{}, { "message": 42 }]
  for params in cases {
    guard Notification::from_wire("agent.error", params)
      is Some(AgentError(payload)) else {
      fail("malformed agent error was dropped")
    }
    assert_eq(payload.message, None)
  }
}
