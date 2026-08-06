// Typed payloads for the desktop API. Transport adapters alone turn these
// values into JSON; request and notification code carries closed types.

///|
pub(all) struct StartPayload {
  task : String
  // Optional client-minted lifecycle identity echoed with `agent.started`.
  // Blank ids and ids longer than 128 UTF-8 bytes are ignored.
  submission_id : String?
  model : String?
  max_steps : Int?
  session : String?
  // A registered workspace directory; absent means a scratch workspace. A
  // session bound to one of the workspace's worktrees (`worktree.create`
  // binds at creation) runs in that checkout — the start itself never names
  // or mutates worktrees.
  workspace : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct CancelPayload {
  run_id : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct SteerPayload {
  text : String
  run_id : String?
  // Optional client-minted lifecycle identity echoed on the steer receipt.
  submission_id : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct KnownRunPayload {
  session : String
  run_id : String?
  submission_id : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct RunsPayload {
  known : Array[KnownRunPayload]?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct CompactPayload {
  // Compaction addresses a durable conversation rather than a live run.
  session : String
  // A resumed conversation may need a new engine process with these settings.
  model : String?
  max_steps : Int?
  workspace : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct LoadSessionPayload {
  session : String
  // The workspace holding the session, when the client already knows it.
  workspace : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
/// `session.archive` / `session.unarchive` address a conversation by its
/// durable session id. Archiving takes the conversation's worktree with
/// it; `force` (archive only) discards that checkout's uncommitted
/// changes — the client sends it after its confirmation dialog.
pub(all) struct SessionPayload {
  session : String
  force : Bool?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct SettingsSetPayload {
  legacy_migration : Bool?
  provider : String?
  custom_api_url : String?
  deepseek_api_key : String?
  custom_api_key : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct WorkspacePayload {
  path : String
} derive(Debug, Eq, FromJson, ToJson)

///|
/// `worktree.list` names the workspace whose registry to read.
pub(all) struct WorktreeListPayload {
  workspace : String
} derive(Debug, Eq, FromJson, ToJson)

///|
/// `worktree.create` names the workspace and the NEW conversation the
/// worktree will be the execution environment of — creation is the binding,
/// and the session doubles as the idempotency key for retries. The host
/// generates the worktree's name and returns it in the reply.
pub(all) struct WorktreeCreatePayload {
  workspace : String
  session : String
} derive(Debug, Eq, FromJson, ToJson)

///|
/// `worktree.remove` — `force` discards uncommitted changes in the checkout;
/// the branch survives either way.
pub(all) struct WorktreeRemovePayload {
  workspace : String
  name : String
  force : Bool?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct InstallSkillPayload {
  module_name : String
  version : String
  package_path : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct UninstallSkillPayload {
  id : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct OpenPathPayload {
  session : String
  cwd : String?
  path : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct UpdateChannelPayload {
  channel : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct GitBranchPayload {
  session : String
  cwd : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct LaunchAppPayload {
  session : String
  cwd : String?
  app : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct ReadDirPayload {
  session : String
  path : String
  workspace : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct ListFilesPayload {
  session : String
  workspace : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct ReadFilePayload {
  session : String
  path : String
  workspace : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct StatFilesPayload {
  session : String
  paths : Array[String]
  workspace : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct WatchWorkspacePayload {
  session : String
  workspace : String?
  files : Array[String]?
  directories : Array[String]?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct BrowseDirectoryPayload {
  path : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct TerminalOpenPayload {
  session : String
  workspace : String?
  cols : Int
  rows : Int
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct TerminalInputPayload {
  id : Int
  data : String?
  data_base64 : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct TerminalResizePayload {
  id : Int
  cols : Int
  rows : Int
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct TerminalAckPayload {
  id : Int
  sequence : Int
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct TerminalClosePayload {
  id : Int
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct LspOpenPayload {
  path : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct LspHoverPayload {
  path : String
  line : Int
  character : Int
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct WorkspaceSymbolsPayload {
  session : String
  query : String
  workspace : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct MoonIdeNavigationPayload {
  path : String
  line : Int
  column : Int
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct ExternalLinkPayload {
  url : String
} derive(Debug, Eq, FromJson, ToJson)
// Notification payloads.

///|
pub(all) struct ConnectedPayload {
  ready : Bool?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct StartedPayload {
  run_id : String
  task : String?
  submission_id : String?
  engine : String?
  model : String?
  max_steps : Int?
  cwd : String?
  session : String?
  session_root : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct AgentEventPayload {
  run_id : String?
  session : String?
  event : AgentStreamEvent
} derive(Debug, Eq, FromJson, ToJson)

///|
/// A host failure report stays decodable even when one of its display fields
/// is absent or has the wrong JSON type. Errors are the one notification class
/// that must not disappear because the report describing them is malformed;
/// the frontend assigns the generic label for a missing or blank `message`.
pub(all) struct AgentErrorPayload {
  run_id : String?
  message : String?
  exit_code : Int?
  diagnostics : String?
} derive(Debug, Eq, ToJson)

///|
pub impl FromJson for AgentErrorPayload with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected agent error payload"))
  }
  {
    run_id: match fields.get("run_id") {
      Some(String(value)) => Some(value)
      _ => None
    },
    message: match fields.get("message") {
      Some(String(value)) => Some(value)
      _ => None
    },
    exit_code: match fields.get("exit_code") {
      Some(Number(value, ..)) => Some(value.to_int())
      _ => None
    },
    diagnostics: match fields.get("diagnostics") {
      Some(String(value)) => Some(value)
      _ => None
    },
  }
}

///|
pub(all) struct FinishedPayload {
  run_id : String
  status : String
  answer : String?
  exit_code : Int?
  durable_sequence : Int?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct DurableBoundaryPayload {
  run_id : String
  session : String
  sequence : Int
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct SessionCommitPayload {
  session : String
  sequence : Int
  event : SessionEvent
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct SessionChangedPayload {
  change : String
  session : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct WorkspacesChangedPayload {
  workspaces : Array[String]
} derive(Debug, Eq, FromJson, ToJson)

///|
/// One workspace's worktree list changed; sidebars re-join their name chips
/// and pickers refresh — the `workspace.changed` pattern, keyed by the
/// workspace the list belongs to.
pub(all) struct WorktreeChangedPayload {
  workspace : String
  worktrees : Array[WorktreeInfo]
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct SettingsStatusPayload {
  revision : Int
  provider : String
  custom_api_url : String?
  has_deepseek_key : Bool
  has_custom_key : Bool
} derive(Debug, Eq, FromJson, ToJson)

///|
/// Immutable identity of the installed desktop package. The native host reads
/// this from `proton-package.json`; it is not an editable engine setting.
pub(all) struct AppInfoReply {
  version : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct UpdateDownloadProgressPayload {
  downloaded_bytes : Int
  total_bytes : Int?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct UpdateDownloadedPayload {
  version : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct UpdateDownloadFailedPayload {
  message : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct AuthUserPayload {
  login : String
  avatar_url : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct AuthDevicePayload {
  id : String
  name : String
  url : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct AuthStatusPayload {
  connected : Bool
  server_url : String?
  managed_by_env : Bool?
  user : AuthUserPayload?
  device : AuthDevicePayload?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct DiagnosticsPayload {
  path : String
  diagnostics : Array[LspDiagnostic]
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct FsEventPayload {
  kind_ : String
  path : String
  old_path : String?
} derive (
  Debug,
  Eq,
  FromJson(fields(kind_(rename="kind"))),
  ToJson(fields(kind_(rename="kind"))),
)

///|
pub(all) struct FsChangedPayload {
  session : String?
  root : String?
  baseline : Bool?
  events : Array[FsEventPayload]?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct FsWatchFailedPayload {
  session : String
  root : String
  message : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct TerminalOutputPayload {
  id : Int
  sequence : Int
  data : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct TerminalExitPayload {
  id : Int
  code : Int
} derive(Debug, Eq, FromJson, ToJson)
