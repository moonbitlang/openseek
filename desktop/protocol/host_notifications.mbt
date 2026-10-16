// Working-machine notifications, independent of desktop and relay state.

///|
pub(all) enum HostNotificationKind {
  UserQuestions
  AgentApprovals
  AgentConnected
  AgentStarted
  AgentEvent
  AgentError
  AgentPrediction
  AgentFinished
  SessionEvent
  SubrunProgress
  WorkflowEntry
  SessionChanged
  WorkspaceChanged
  WorkspaceSettingsChanged
  WorktreeChanged
  SettingsChanged
  SkillsChanged
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
pub fn HostNotificationKind::wire_name(self : HostNotificationKind) -> String {
  match self {
    UserQuestions => "user_questions.changed"
    AgentApprovals => "agent.approvals"
    AgentConnected => "agent.connected"
    AgentStarted => "agent.started"
    AgentEvent => "agent.event"
    AgentError => "agent.error"
    AgentPrediction => "agent.prediction"
    AgentFinished => "agent.finished"
    SessionEvent => "session.event"
    SubrunProgress => "subrun.progress"
    WorkflowEntry => "workflow.entry"
    SessionChanged => "session.changed"
    WorkspaceChanged => "workspace.changed"
    WorkspaceSettingsChanged => "workspace.settings_changed"
    WorktreeChanged => "worktree.changed"
    SettingsChanged => "settings.changed"
    SkillsChanged => "skills.changed"
    CodexStatusChanged => "codex.status_changed"
    CodexNotification => "codex.notification"
    CodexServerRequest => "codex.server_request"
    LspDiagnostics => "lsp.diagnostics"
    FsChanged => "fs.changed"
    FsWatchFailed => "fs.watch_failed"
    TerminalOutput => "terminal.output"
    TerminalExit => "terminal.exit"
    SemanticSearchProgress => "semantic.search_progress"
  }
}

///|
pub fn HostNotificationKind::all() -> Array[HostNotificationKind] {
  [
    UserQuestions,
    AgentApprovals,
    AgentConnected,
    AgentStarted,
    AgentEvent,
    AgentError,
    AgentPrediction,
    AgentFinished,
    SessionEvent,
    SubrunProgress,
    WorkflowEntry,
    SessionChanged,
    WorkspaceChanged,
    WorkspaceSettingsChanged,
    WorktreeChanged,
    SettingsChanged,
    SkillsChanged,
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
pub(all) enum HostNotification {
  UserQuestions(UserQuestionSnapshot)
  AgentApprovals(ApprovalSnapshot)
  AgentConnected(ConnectedPayload)
  AgentStarted(StartedPayload)
  AgentEvent(AgentEventPayload)
  AgentError(AgentErrorPayload)
  AgentPrediction(PredictionReadyPayload)
  AgentFinished(FinishedPayload)
  SessionEvent(SessionCommitPayload)
  SubrunProgress(SubrunProgressPayload)
  WorkflowEntry(WorkflowEntryPayload)
  SessionChanged(SessionChangedPayload)
  WorkspaceChanged(WorkspacesChangedPayload)
  WorkspaceSettingsChanged(WorkspaceSettingsPayload)
  WorktreeChanged(WorktreeChangedPayload)
  SettingsChanged(SettingsStatusPayload)
  SkillsChanged
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
pub fn HostNotification::from_wire(
  name : String,
  params : Json,
) -> HostNotification? {
  match name {
    "user_questions.changed" =>
      Some(UserQuestions(@json.from_json(params) catch { _ => return None }))
    "agent.approvals" =>
      Some(AgentApprovals(@json.from_json(params) catch { _ => return None }))
    "agent.connected" =>
      Some(AgentConnected(@json.from_json(params) catch { _ => return None }))
    "agent.started" =>
      Some(AgentStarted(@json.from_json(params) catch { _ => return None }))
    "agent.event" =>
      Some(AgentEvent(@json.from_json(params) catch { _ => return None }))
    "agent.error" =>
      Some(AgentError(@json.from_json(params) catch { _ => return None }))
    "agent.prediction" =>
      Some(AgentPrediction(@json.from_json(params) catch { _ => return None }))
    "agent.finished" =>
      Some(AgentFinished(@json.from_json(params) catch { _ => return None }))
    "session.event" =>
      Some(SessionEvent(@json.from_json(params) catch { _ => return None }))
    "subrun.progress" =>
      Some(SubrunProgress(@json.from_json(params) catch { _ => return None }))
    "workflow.entry" =>
      Some(WorkflowEntry(@json.from_json(params) catch { _ => return None }))
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
    "codex.status_changed" => Some(CodexStatusChanged(params))
    "codex.notification" => Some(CodexNotification(params))
    "codex.server_request" => Some(CodexServerRequest(params))
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
    "semantic.search_progress" =>
      Some(
        SemanticSearchProgress(
          @json.from_json(params) catch {
            _ => return None
          },
        ),
      )
    _ => None
  }
}

///|
pub fn HostNotification::kind(self : HostNotification) -> HostNotificationKind {
  match self {
    UserQuestions(_) => UserQuestions
    AgentApprovals(_) => AgentApprovals
    AgentConnected(_) => AgentConnected
    AgentStarted(_) => AgentStarted
    AgentEvent(_) => AgentEvent
    AgentError(_) => AgentError
    AgentPrediction(_) => AgentPrediction
    AgentFinished(_) => AgentFinished
    SessionEvent(_) => SessionEvent
    SubrunProgress(_) => SubrunProgress
    WorkflowEntry(_) => WorkflowEntry
    SessionChanged(_) => SessionChanged
    WorkspaceChanged(_) => WorkspaceChanged
    WorkspaceSettingsChanged(_) => WorkspaceSettingsChanged
    WorktreeChanged(_) => WorktreeChanged
    SettingsChanged(_) => SettingsChanged
    SkillsChanged => SkillsChanged
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
pub fn HostNotification::wire_name(self : HostNotification) -> String {
  self.kind().wire_name()
}

///|
pub fn HostNotification::params(self : HostNotification) -> Json {
  match self {
    UserQuestions(payload) => payload.to_json()
    AgentApprovals(payload) => payload.to_json()
    AgentConnected(payload) => payload.to_json()
    AgentStarted(payload) => payload.to_json()
    AgentEvent(payload) => payload.to_json()
    AgentError(payload) => payload.to_json()
    AgentPrediction(payload) => payload.to_json()
    AgentFinished(payload) => payload.to_json()
    SessionEvent(payload) => payload.to_json()
    SubrunProgress(payload) => payload.to_json()
    WorkflowEntry(payload) => payload.to_json()
    SessionChanged(payload) => payload.to_json()
    WorkspaceChanged(payload) => payload.to_json()
    WorkspaceSettingsChanged(payload) => payload.to_json()
    WorktreeChanged(payload) => payload.to_json()
    SettingsChanged(payload) => payload.to_json()
    SkillsChanged => Json::empty_object()
    CodexStatusChanged(payload) => payload
    CodexNotification(payload) => payload
    CodexServerRequest(payload) => payload
    LspDiagnostics(payload) => payload.to_json()
    FsChanged(payload) => payload.to_json()
    FsWatchFailed(payload) => payload.to_json()
    TerminalOutput(payload) => payload.to_json()
    TerminalExit(payload) => payload.to_json()
    SemanticSearchProgress(payload) => payload.to_json()
  }
}

///|
pub extend HostNotification with Debug::{to_repr}

///|
pub extend HostNotification with Eq::{equal, not_equal}

///|
pub extend HostNotificationKind with Debug::{to_repr}

///|
pub extend HostNotificationKind with Eq::{equal, not_equal}

///|
pub extend HostNotificationKind with Hash::{hash, hash_combine}
