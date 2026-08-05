// Typed replies and nested wire documents for the desktop API. JSON exists
// only while a transport or an external process encodes/decodes these values;
// request handlers and frontend code exchange the closed types below.

///|
/// Object-shaped input for methods with no arguments.
pub(all) enum EmptyPayload {
  NoPayload
} derive(Debug, Eq)

///|
pub impl ToJson for EmptyPayload with fn to_json(_self) {
  Json::empty_object()
}

///|
pub impl FromJson for EmptyPayload with fn from_json(json, path) {
  guard json is Object(_) else {
    raise JsonDecodeError((path, "expected empty object payload"))
  }
  NoPayload
}

///|
/// Object-shaped acknowledgement for methods whose successful result has no
/// additional data.
pub(all) enum EmptyReply {
  Acknowledged
} derive(Debug, Eq)

///|
pub impl ToJson for EmptyReply with fn to_json(_self) {
  Json::empty_object()
}

///|
pub impl FromJson for EmptyReply with fn from_json(json, path) {
  guard json is Object(_) else {
    raise JsonDecodeError((path, "expected empty object reply"))
  }
  Acknowledged
}

///|
pub(all) struct StartReply {
  run_id : String
  status : String
  exit_code : Int
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct CancelReply {
  cancelled : Bool
  run_id : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct SteerReply {
  steered : Bool
  run_id : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct CompactReply {
  compacting : Bool
} derive(Debug, Eq, FromJson, ToJson)

///|
/// One reconnect-safe completion returned by `agent.runs`.
pub(all) struct RunSettlementPayload {
  run_id : String
  session : String
  submission_id : String?
  status : String
  exit_code : Int?
  durable_sequence : Int?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct RunsReply {
  runs : Array[StartedPayload]
  settled : Array[RunSettlementPayload]
} derive(Debug, Eq, FromJson, ToJson)

///|
/// The subset of `sessions list --format=json` consumed by Desktop.
pub(all) struct SessionListEntry {
  id : String
  title : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
/// Decode the engine's session-list rows at the process adapter. A malformed
/// row is skipped without discarding other conversations in the same store.
pub fn SessionListEntry::array_from_wire(
  json : Json,
) -> Array[SessionListEntry] {
  guard json is Array(items) else { return [] }
  let sessions : Array[SessionListEntry] = []
  for item in items {
    let session : SessionListEntry = @json.from_json(item) catch {
      _ => continue
    }
    if !session.id.is_empty() {
      sessions.push(session)
    }
  }
  sessions
}

///|
pub(all) struct SessionGroup {
  workspace : String
  name : String
  session_root : String
  sessions : Array[SessionListEntry]
  error : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct SessionsReply {
  groups : Array[SessionGroup]
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct SessionToolCall {
  id : String
  name : String
  arguments : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct SessionUserMessage {
  content : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct SessionAssistantMessage {
  content : String
  tool_calls : Array[SessionToolCall]?
  reasoning_content : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct SessionToolResult {
  tool_call_id : String
  tool_name : String
  content : String
  is_error : Bool
  brief : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct SessionRuntimeNotice {
  content : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct SessionSummary {
  content : String
  from_sequence : Int
  to_sequence : Int
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) enum SessionTerminal {
  Finished(String)
  Aborted(String)
  Interrupted(String)
  Failed(String)
} derive(Debug, Eq)

///|
pub impl ToJson for SessionTerminal with fn to_json(self) {
  match self {
    Finished(message) => { "kind": "finished", "message": message }
    Aborted(message) => { "kind": "aborted", "message": message }
    Interrupted(message) => { "kind": "interrupted", "message": message }
    Failed(message) => { "kind": "failed", "message": message }
  }
}

///|
pub impl FromJson for SessionTerminal with fn from_json(json, path) {
  guard json is Object(fields) &&
    fields.get("kind") is Some(String(kind_)) &&
    fields.get("message") is Some(String(message)) else {
    raise JsonDecodeError((path, "expected session terminal"))
  }
  match kind_ {
    "finished" => Finished(message)
    "aborted" => Aborted(message)
    "interrupted" => Interrupted(message)
    "failed" => Failed(message)
    _ => raise JsonDecodeError((path.add_key("kind"), "unknown terminal kind"))
  }
}

///|
/// The durable session item's tagged payload. Its manual codec preserves the
/// engine store's `{kind,payload}` representation while exposing a closed enum.
pub(all) enum SessionItem {
  User(SessionUserMessage)
  Assistant(SessionAssistantMessage)
  ToolResult(SessionToolResult)
  RuntimeNotice(SessionRuntimeNotice)
  Summary(SessionSummary)
  Terminal(SessionTerminal)
} derive(Debug, Eq)

///|
pub impl ToJson for SessionItem with fn to_json(self) {
  match self {
    User(payload) => { "kind": "user", "payload": payload }
    Assistant(payload) => { "kind": "assistant", "payload": payload }
    ToolResult(payload) => { "kind": "tool_result", "payload": payload }
    RuntimeNotice(payload) => { "kind": "runtime_notice", "payload": payload }
    Summary(payload) => { "kind": "summary", "payload": payload }
    Terminal(payload) => { "kind": "terminal", "payload": payload }
  }
}

///|
pub impl FromJson for SessionItem with fn from_json(json, path) {
  guard json is Object(fields) &&
    fields.get("kind") is Some(String(kind_)) &&
    fields.get("payload") is Some(payload) else {
    raise JsonDecodeError((path, "expected session item"))
  }
  match kind_ {
    "user" => User(@json.from_json(payload, path=path.add_key("payload")))
    "assistant" =>
      Assistant(@json.from_json(payload, path=path.add_key("payload")))
    "tool_result" =>
      ToolResult(@json.from_json(payload, path=path.add_key("payload")))
    "runtime_notice" =>
      RuntimeNotice(@json.from_json(payload, path=path.add_key("payload")))
    "summary" => Summary(@json.from_json(payload, path=path.add_key("payload")))
    "terminal" =>
      Terminal(@json.from_json(payload, path=path.add_key("payload")))
    _ =>
      raise JsonDecodeError((path.add_key("kind"), "unknown session item kind"))
  }
}

///|
/// One append-only durable event. `ts` is optional for compatibility with old
/// stores and test fixtures written before timestamps were added.
pub(all) struct SessionEvent {
  sequence : Int
  ts : Double?
  item : SessionItem
} derive(Debug, Eq, FromJson, ToJson)

///|
/// The session document returned by the engine. Metadata added by newer
/// engines stays optional; Desktop's transcript is defined by `events`.
pub(all) struct SessionDocument {
  version : Int?
  id : String?
  system_prompt : String?
  events : Array[SessionEvent]?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct LoadSessionReply {
  session : SessionDocument
  watermark : Int?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct WorkspacesReply {
  workspaces : Array[String]
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct OpenPathReply {
  opened : Bool
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct ApplyUpdateReply {
  applied : Bool
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct AppEntry {
  id : String
  name : String
  icon : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct ListAppsReply {
  apps : Array[AppEntry]
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct LaunchAppReply {
  launched : Bool
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct MarketSkill {
  name : String
  module_name : String
  package_path : String
  version : String
  description : String
  author : String
  repository : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct InstalledSkill {
  id : String
  name : String
  description : String
  source : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct SkillsCatalogReply {
  skills : Array[MarketSkill]
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct InstalledSkillsReply {
  skills : Array[InstalledSkill]
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct InstallSkillReply {
  installed : InstalledSkill
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct UninstallSkillReply {
  removed : Bool
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct GitBranchReply {
  branch : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct DirEntry {
  name : String
  is_dir : Bool
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct ReadDirReply {
  entries : Array[DirEntry]
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct ListFilesReply {
  files : Array[String]
  truncated : Bool
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) enum ReadFileReply {
  Binary
  Oversized
  Content(content~ : String, absolute~ : String, sig~ : String)
} derive(Debug, Eq)

///|
pub impl ToJson for ReadFileReply with fn to_json(self) {
  match self {
    Binary => { "kind": "binary" }
    Oversized => { "kind": "oversized" }
    Content(content~, absolute~, sig~) =>
      {
        "kind": "content",
        "content": content,
        "absolute": absolute,
        "sig": sig,
      }
  }
}

///|
pub impl FromJson for ReadFileReply with fn from_json(json, path) {
  guard json is Object(fields) && fields.get("kind") is Some(String(kind_)) else {
    raise JsonDecodeError((path, "expected file reply"))
  }
  match kind_ {
    "binary" => Binary
    "oversized" => Oversized
    "content" => {
      guard fields.get("content") is Some(String(content)) &&
        fields.get("absolute") is Some(String(absolute)) &&
        fields.get("sig") is Some(String(sig)) else {
        raise JsonDecodeError((path, "malformed file content reply"))
      }
      Content(content~, absolute~, sig~)
    }
    _ =>
      raise JsonDecodeError((path.add_key("kind"), "unknown file reply kind"))
  }
}

///|
pub(all) struct FileStat {
  path : String
  sig : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct StatFilesReply {
  stats : Array[FileStat]
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct BrowseDirectoryReply {
  path : String
  parent : String?
  entries : Array[String]
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct TerminalOpenReply {
  id : Int
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct MoonIdeLocation {
  path : String
  start_line : Int
  start_column : Int
  end_line : Int
  end_column : Int
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct MoonIdeLocationsReply {
  locations : Array[MoonIdeLocation]
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct LspPosition {
  line : Int
  character : Int
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct LspRange {
  start : LspPosition
  end : LspPosition
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct LspDiagnostic {
  range : LspRange
  message : String
  severity : Int?
  tags : Array[Int]?
} derive(Debug, Eq, FromJson, ToJson)

///|
/// Decode the LSP's open-ended diagnostics array at the LSP adapter. Unknown
/// fields are ignored by `FromJson`; malformed rows are skipped independently
/// so one server extension cannot hide otherwise valid diagnostics.
pub fn LspDiagnostic::array_from_wire(json : Json) -> Array[LspDiagnostic] {
  guard json is Array(items) else { return [] }
  let diagnostics : Array[LspDiagnostic] = []
  for item in items {
    let decoded : LspDiagnostic = @json.from_json(item) catch { _ => continue }
    diagnostics.push(decoded)
  }
  diagnostics
}

///|
pub(all) struct LspDiagnosticsReply {
  diagnostics : Array[LspDiagnostic]
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct LspHoverReply {
  value : String
  markdown : Bool
  has_range : Bool
  start_line : Int
  start_character : Int
  end_line : Int
  end_character : Int
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct SymbolPosition {
  line : Int
  col : Int
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct SymbolRange {
  start : SymbolPosition
  end : SymbolPosition
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct SymbolItem {
  name : String
  kind : Int?
  container : String?
  path : String
  range : SymbolRange
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct WorkspaceSymbolsReply {
  symbols : Array[SymbolItem]
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) enum CheckUpdateReply {
  UpToDate
  Available(
    version~ : String,
    installable~ : Bool,
    unavailable_reason~ : String?
  )
  Unreachable(reason~ : String)
  Malformed(reason~ : String)
  Broken(version~ : String, reason~ : String)
} derive(Debug, Eq)

///|
pub impl ToJson for CheckUpdateReply with fn to_json(self) {
  match self {
    UpToDate => { "kind": "up_to_date" }
    Available(version~, installable~, unavailable_reason~) => {
      let fields : Map[String, Json] = Map::from_array([
        ("kind", Json::string("available")),
        ("version", Json::string(version)),
        ("installable", Json::boolean(installable)),
      ])
      if unavailable_reason is Some(reason) {
        fields["unavailable_reason"] = Json::string(reason)
      } else {
        fields["unavailable_reason"] = Json::null()
      }
      Json::object(fields)
    }
    Unreachable(reason~) => { "kind": "unreachable", "reason": reason }
    Malformed(reason~) => { "kind": "malformed", "reason": reason }
    Broken(version~, reason~) =>
      { "kind": "broken", "version": version, "reason": reason }
  }
}

///|
pub impl FromJson for CheckUpdateReply with fn from_json(json, path) {
  guard json is Object(fields) && fields.get("kind") is Some(String(kind_)) else {
    raise JsonDecodeError((path, "expected update reply"))
  }
  match kind_ {
    "up_to_date" => UpToDate
    "available" => {
      guard fields.get("version") is Some(String(version)) else {
        raise JsonDecodeError((path, "malformed available update"))
      }
      let installable = match fields.get("installable") {
        Some(True) => true
        Some(False) => false
        _ => raise JsonDecodeError((path, "malformed available update"))
      }
      let unavailable_reason = match fields.get("unavailable_reason") {
        Some(String(reason)) => Some(reason)
        _ => None
      }
      Available(version~, installable~, unavailable_reason~)
    }
    "unreachable" => {
      guard fields.get("reason") is Some(String(reason)) else {
        raise JsonDecodeError((path, "malformed unreachable update"))
      }
      Unreachable(reason~)
    }
    "malformed" => {
      guard fields.get("reason") is Some(String(reason)) else {
        raise JsonDecodeError((path, "malformed update metadata reply"))
      }
      Malformed(reason~)
    }
    "broken" => {
      guard fields.get("version") is Some(String(version)) &&
        fields.get("reason") is Some(String(reason)) else {
        raise JsonDecodeError((path, "malformed broken update"))
      }
      Broken(version~, reason~)
    }
    _ =>
      raise JsonDecodeError((path.add_key("kind"), "unknown update reply kind"))
  }
}

///|
pub(all) struct DownloadUpdateAcceptedReply {
  accepted : Bool
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct OpenExternalReply {
  opened : Bool
} derive(Debug, Eq, FromJson, ToJson)

///|
/// An engine event plus Desktop's optional steer-submission correlation.
pub(all) struct AgentStreamEvent {
  event : @wire.Event
  submission_id : String?
} derive(Debug, Eq)

///|
pub impl ToJson for AgentStreamEvent with fn to_json(self) {
  let raw = self.event.to_json()
  guard raw is Object(fields) else { return raw }
  if self.submission_id is Some(submission_id) {
    let fields = fields.copy()
    fields["submission_id"] = Json::string(submission_id)
    return Json::object(fields)
  }
  raw
}

///|
pub impl FromJson for AgentStreamEvent with fn from_json(json, path) {
  guard @wire.parse(json) is Some(event) else {
    raise JsonDecodeError((path, "unknown engine event"))
  }
  let submission_id = if json is Object(fields) &&
    fields.get("submission_id") is Some(String(value)) {
    Some(value)
  } else {
    None
  }
  { event, submission_id }
}

///|
/// Keep the transient lifecycle information a remote client needs while
/// removing durable transcript text that arrives separately as session
/// commits. `None` means the stream event has no remaining remote purpose.
pub fn AgentStreamEvent::remote_lifecycle(
  self : AgentStreamEvent,
) -> AgentStreamEvent? {
  match self.event {
    ReasoningMessage(..) =>
      Some({ ..self, event: ReasoningMessage(content="") })
    AssistantMessage(..) =>
      Some({ ..self, event: AssistantMessage(content="") })
    ToolResult(..)
    | AutoCompactionFinished(..)
    | AgentFinished(..)
    | ContextYield(..) => None
    CompactionFinished(from_sequence~, to_sequence~, ..) =>
      Some({
        ..self,
        event: CompactionFinished(from_sequence~, to_sequence~, summary=""),
      })
    _ => Some(self)
  }
}
