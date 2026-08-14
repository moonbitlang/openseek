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
    AgentConnected => "agent.connected"
    AgentStarted => "agent.started"
    AgentEvent => "agent.event"
    AgentError => "agent.error"
    AgentFinished => "agent.finished"
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
/// Every event exposed by the desktop transports, in registration order.
pub fn NotificationKind::all() -> Array[NotificationKind] {
  [
    AgentConnected,
    AgentStarted,
    AgentEvent,
    AgentError,
    AgentFinished,
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
  AgentConnected(ConnectedPayload)
  AgentStarted(StartedPayload)
  AgentEvent(AgentEventPayload)
  AgentError(AgentErrorPayload)
  AgentFinished(FinishedPayload)
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
/// The payload-free identity used by transport registration.
pub fn Notification::kind(self : Notification) -> NotificationKind {
  match self {
    AgentConnected(_) => AgentConnected
    AgentStarted(_) => AgentStarted
    AgentEvent(_) => AgentEvent
    AgentError(_) => AgentError
    AgentFinished(_) => AgentFinished
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
    AgentConnected(payload) => ToJson::to_json(payload)
    AgentStarted(payload) => ToJson::to_json(payload)
    AgentEvent(payload) => ToJson::to_json(payload)
    AgentError(payload) => ToJson::to_json(payload)
    AgentFinished(payload) => ToJson::to_json(payload)
    SessionEvent(payload) => ToJson::to_json(payload)
    SubrunProgress(payload) => ToJson::to_json(payload)
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
test "desktop notifications round-trip at the wire edge" {
  let event = Notification::from_wire("terminal.exit", { "id": 1, "code": 0 })
  guard event is Some(event) else { fail("known notification was rejected") }
  assert_eq(event.wire_name(), "terminal.exit")
  assert_eq(event.params(), { "id": 1, "code": 0 })
  let settings = Notification::from_wire("workspace.settings_changed", {
    "workspace": "/home/u/proj",
    "worktree_mode": true,
    "checkout_submodules": false,
    "submodule_checkout_timeout_seconds": 30,
  })
  guard settings is Some(settings) else {
    fail("workspace settings notification was rejected")
  }
  assert_eq(settings.wire_name(), "workspace.settings_changed")
  assert_eq(settings.params(), {
    "workspace": "/home/u/proj",
    "worktree_mode": true,
    "checkout_submodules": false,
    "submodule_checkout_timeout_seconds": 30,
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

///|
test "semantic search progress notifications round-trip at the wire edge" {
  let wire : Json = {
    "root": "/work",
    "session_key": "semantic-search:local:one:/work",
    "generation": 3,
    "matches": [
      {
        "path": "src/main.mbt",
        "rule_id": "pattern",
        "description": "a desc",
        "start_line": 1,
        "start_column": 1,
        "end_line": 1,
        "end_column": 5,
        "matched_source": "moon",
        "source_context": [{ "line": 1, "text": "moon", "is_match": true }],
      },
    ],
    "match_count": 1,
    "file_count": 1,
  }
  guard Notification::from_wire("semantic.search_progress", wire)
    is Some(SemanticSearchProgress(payload)) else {
    fail("known notification was rejected")
  }
  assert_eq(payload.root, "/work")
  assert_eq(payload.session_key, "semantic-search:local:one:/work")
  assert_eq(payload.generation, 3)
  assert_eq(payload.match_count, 1)
  assert_eq(payload.file_count, 1)
  assert_eq(payload.matches.length(), 1)
  assert_eq(payload.matches[0].path, "src/main.mbt")
  assert_eq(Notification::SemanticSearchProgress(payload).params(), wire)
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
