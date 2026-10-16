// Typed desktop notifications. Strings and JSON exist only where a transport
// reads or writes the public wire format.

///|
/// The stable identity of one server-pushed event. Transport registration
/// uses this payload-free enum; `Notification` below carries the associated
/// typed payload once an event is decoded.
pub(all) enum NotificationKind {
  UserQuestions
  AgentApprovals
  AgentConnected
  AgentStarted
  AgentEvent
  AgentError
  AgentFinished
  AgentPrediction
  SessionEvent
  SessionShareProgress
  SubrunProgress
  WorkflowEntry
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
  CodexStatusChanged
  CodexNotification
  CodexServerRequest
  LspDiagnostics
  FsChanged
  FsWatchFailed
  TerminalOutput
  TerminalExit
  SemanticSearchProgress
} derive(Debug, Eq, Hash)

///|
/// The stable public name written at a transport boundary.
pub fn NotificationKind::wire_name(self : NotificationKind) -> String {
  match self {
    SessionShareProgress => "session.share_progress"
    UserQuestions => "user_questions.changed"
    AgentApprovals => HostNotificationKind::AgentApprovals.wire_name()
    AgentConnected => HostNotificationKind::AgentConnected.wire_name()
    AgentStarted => HostNotificationKind::AgentStarted.wire_name()
    AgentEvent => HostNotificationKind::AgentEvent.wire_name()
    AgentError => HostNotificationKind::AgentError.wire_name()
    AgentPrediction => HostNotificationKind::AgentPrediction.wire_name()
    AgentFinished => HostNotificationKind::AgentFinished.wire_name()
    SessionEvent => HostNotificationKind::SessionEvent.wire_name()
    SubrunProgress => HostNotificationKind::SubrunProgress.wire_name()
    WorkflowEntry => HostNotificationKind::WorkflowEntry.wire_name()
    SessionChanged => HostNotificationKind::SessionChanged.wire_name()
    WorkspaceChanged => HostNotificationKind::WorkspaceChanged.wire_name()
    WorkspaceSettingsChanged =>
      HostNotificationKind::WorkspaceSettingsChanged.wire_name()
    WorktreeChanged => HostNotificationKind::WorktreeChanged.wire_name()
    SettingsChanged => HostNotificationKind::SettingsChanged.wire_name()
    SkillsChanged => HostNotificationKind::SkillsChanged.wire_name()
    UpdateDownloadProgress => "update.download_progress"
    UpdateDownloaded => "update.downloaded"
    UpdateDownloadFailed => "update.download_failed"
    AuthChanged => "auth.changed"
    CodexStatusChanged => HostNotificationKind::CodexStatusChanged.wire_name()
    CodexNotification => HostNotificationKind::CodexNotification.wire_name()
    CodexServerRequest => HostNotificationKind::CodexServerRequest.wire_name()
    LspDiagnostics => HostNotificationKind::LspDiagnostics.wire_name()
    FsChanged => HostNotificationKind::FsChanged.wire_name()
    FsWatchFailed => HostNotificationKind::FsWatchFailed.wire_name()
    TerminalOutput => HostNotificationKind::TerminalOutput.wire_name()
    TerminalExit => HostNotificationKind::TerminalExit.wire_name()
    SemanticSearchProgress =>
      HostNotificationKind::SemanticSearchProgress.wire_name()
  }
}

///|
/// Every event exposed by the desktop transports, in registration order.
pub fn NotificationKind::all() -> Array[NotificationKind] {
  [
    UserQuestions,
    AgentApprovals,
    AgentConnected,
    AgentStarted,
    AgentEvent,
    AgentError,
    AgentFinished,
    AgentPrediction,
    SessionEvent,
    SessionShareProgress,
    SubrunProgress,
    WorkflowEntry,
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
    CodexStatusChanged,
    CodexNotification,
    CodexServerRequest,
    LspDiagnostics,
    FsChanged,
    FsWatchFailed,
    TerminalOutput,
    TerminalExit,
    SemanticSearchProgress,
  ]
}

///|
/// A server-pushed desktop event. Both the event case and its top-level
/// payload are compiler checked throughout the host and frontend. JSON is
/// introduced only by `from_wire`/`params` at the transport boundary.
pub(all) enum Notification {
  UserQuestions(UserQuestionSnapshot)
  AgentApprovals(ApprovalSnapshot)
  AgentConnected(ConnectedPayload)
  AgentStarted(StartedPayload)
  AgentEvent(AgentEventPayload)
  AgentError(AgentErrorPayload)
  AgentFinished(FinishedPayload)
  AgentPrediction(PredictionReadyPayload)
  SessionEvent(SessionCommitPayload)
  SessionShareProgress(SessionShareProgress)
  SubrunProgress(SubrunProgressPayload)
  WorkflowEntry(WorkflowEntryPayload)
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
  // Codex app-server owns its versioned payload schema. These three closed
  // Desktop event identities carry JSON only across that upstream boundary;
  // the frontend Codex package performs the method-specific decoding.
  CodexStatusChanged(Json)
  CodexNotification(Json)
  CodexServerRequest(Json)
  LspDiagnostics(DiagnosticsPayload)
  FsChanged(FsChangedPayload)
  FsWatchFailed(FsWatchFailedPayload)
  TerminalOutput(TerminalOutputPayload)
  TerminalExit(TerminalExitPayload)
  SemanticSearchProgress(SemanticSearchProgressPayload)
} derive(Debug, Eq)

///|
/// Decode the event name and payload together at the WebSocket/Proton boundary.
/// Unknown events are deliberately ignored so newer hosts remain compatible
/// with older pages. Matching the wire name here avoids a second name-to-kind
/// table that would only be consumed by this decoder.
pub fn Notification::from_wire(name : String, params : Json) -> Notification? {
  match name {
    "session.share_progress" =>
      Some(
        SessionShareProgress(@json.from_json(params) catch { _ => return None }),
      )
    "user_questions.changed" =>
      Some(UserQuestions(@json.from_json(params) catch { _ => return None }))
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
    _ => HostNotification::from_wire(name, params).map(Notification::from_host)
  }
}

///|
/// The payload-free identity used by transport registration.
pub fn Notification::kind(self : Notification) -> NotificationKind {
  match self {
    UserQuestions(_) => UserQuestions
    AgentApprovals(_) => AgentApprovals
    AgentConnected(_) => AgentConnected
    AgentStarted(_) => AgentStarted
    AgentEvent(_) => AgentEvent
    AgentError(_) => AgentError
    AgentFinished(_) => AgentFinished
    AgentPrediction(_) => AgentPrediction
    SessionEvent(_) => SessionEvent
    SessionShareProgress(_) => SessionShareProgress
    SubrunProgress(_) => SubrunProgress
    WorkflowEntry(_) => WorkflowEntry
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
    CodexStatusChanged(_) => CodexStatusChanged
    CodexNotification(_) => CodexNotification
    CodexServerRequest(_) => CodexServerRequest
    LspDiagnostics(_) => LspDiagnostics
    FsChanged(_) => FsChanged
    FsWatchFailed(_) => FsWatchFailed
    TerminalOutput(_) => TerminalOutput
    TerminalExit(_) => TerminalExit
    SemanticSearchProgress(_) => SemanticSearchProgress
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
    UserQuestions(payload) => ToJson::to_json(payload)
    AgentApprovals(payload) => ToJson::to_json(payload)
    AgentConnected(payload) => ToJson::to_json(payload)
    AgentStarted(payload) => ToJson::to_json(payload)
    AgentEvent(payload) => ToJson::to_json(payload)
    AgentError(payload) => ToJson::to_json(payload)
    AgentFinished(payload) => ToJson::to_json(payload)
    AgentPrediction(payload) => ToJson::to_json(payload)
    SessionEvent(payload) => ToJson::to_json(payload)
    SessionShareProgress(payload) => ToJson::to_json(payload)
    SubrunProgress(payload) => ToJson::to_json(payload)
    WorkflowEntry(payload) => ToJson::to_json(payload)
    SessionChanged(payload) => ToJson::to_json(payload)
    WorkspaceChanged(payload) => ToJson::to_json(payload)
    WorkspaceSettingsChanged(payload) => ToJson::to_json(payload)
    WorktreeChanged(payload) => ToJson::to_json(payload)
    SettingsChanged(payload) => ToJson::to_json(payload)
    SkillsChanged => Json::empty_object()
    UpdateDownloadProgress(payload) => ToJson::to_json(payload)
    UpdateDownloaded(payload) => ToJson::to_json(payload)
    UpdateDownloadFailed(payload) => ToJson::to_json(payload)
    AuthChanged(payload) => ToJson::to_json(payload)
    CodexStatusChanged(payload) => payload
    CodexNotification(payload) => payload
    CodexServerRequest(payload) => payload
    LspDiagnostics(payload) => ToJson::to_json(payload)
    FsChanged(payload) => ToJson::to_json(payload)
    FsWatchFailed(payload) => ToJson::to_json(payload)
    TerminalOutput(payload) => ToJson::to_json(payload)
    TerminalExit(payload) => ToJson::to_json(payload)
    SemanticSearchProgress(payload) => ToJson::to_json(payload)
  }
}

///|
pub extend Notification with Debug::{to_repr}

///|
pub extend Notification with Eq::{equal, not_equal}

///|
pub extend NotificationKind with Debug::{to_repr}

///|
pub extend NotificationKind with Eq::{equal, not_equal}

///|
pub extend NotificationKind with Hash::{hash, hash_combine}

///|
/// Adapt service events to the desktop catalog without a JSON round trip.
pub fn Notification::from_host(event : HostNotification) -> Notification {
  match event {
    UserQuestions(payload) => UserQuestions(payload)
    AgentApprovals(payload) => AgentApprovals(payload)
    AgentConnected(payload) => AgentConnected(payload)
    AgentStarted(payload) => AgentStarted(payload)
    AgentEvent(payload) => AgentEvent(payload)
    AgentError(payload) => AgentError(payload)
    AgentPrediction(payload) => AgentPrediction(payload)
    AgentFinished(payload) => AgentFinished(payload)
    SessionEvent(payload) => SessionEvent(payload)
    SubrunProgress(payload) => SubrunProgress(payload)
    WorkflowEntry(payload) => WorkflowEntry(payload)
    SessionChanged(payload) => SessionChanged(payload)
    WorkspaceChanged(payload) => WorkspaceChanged(payload)
    WorkspaceSettingsChanged(payload) => WorkspaceSettingsChanged(payload)
    WorktreeChanged(payload) => WorktreeChanged(payload)
    SettingsChanged(payload) => SettingsChanged(payload)
    SkillsChanged => SkillsChanged
    CodexStatusChanged(payload) => CodexStatusChanged(payload)
    CodexNotification(payload) => CodexNotification(payload)
    CodexServerRequest(payload) => CodexServerRequest(payload)
    LspDiagnostics(payload) => LspDiagnostics(payload)
    FsChanged(payload) => FsChanged(payload)
    FsWatchFailed(payload) => FsWatchFailed(payload)
    TerminalOutput(payload) => TerminalOutput(payload)
    TerminalExit(payload) => TerminalExit(payload)
    SemanticSearchProgress(payload) => SemanticSearchProgress(payload)
  }
}
