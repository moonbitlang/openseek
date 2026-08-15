// Typed payloads for the desktop API. Transport adapters alone turn these
// values into JSON; request and notification code carries closed types.
//
// Every field described as an absolute filesystem path carries only the
// slash-rooted path component of an OpenSeek resource URI: `/home/u/work` on
// POSIX and `/C:/work` for a Windows drive. The owning device is already the
// request channel, so scheme and authority never appear in these strings.
// UNC paths are outside this contract. Workspace-relative fields remain
// slash-separated relative strings.

///|
pub(all) struct StartPayload {
  task : String
  // Optional client-minted lifecycle identity echoed with `agent.started`.
  // Blank ids and ids longer than 128 UTF-8 bytes are ignored.
  submission_id : String?
  model : String?
  max_steps : Int?
  // Every desktop run belongs to a durable conversation. The engine rejects
  // a blank id before it acquires that conversation's record lease.
  session : String
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
pub(all) struct GoalPayload {
  // Like compaction, a standing goal addresses a durable conversation rather
  // than a live run: the serve engine accepts one in any phase (idle append,
  // mid-turn steer, queued behind a compaction).
  session : String
  // The new standing goal; absent clears it.
  text : String?
  // Arms the engine's autonomous continuation for this goal. Optional, and
  // absent means manual, so a client that predates the toggle still decodes.
  // Meaningless without `text`: a clear disarms whatever was armed.
  auto : Bool?
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
/// Permanent deletion addresses one archived record in one exact store.
/// `workspace` is the host-reported project resource path, or `""` for the
/// global Scratch store; the host still validates project paths against its
/// registry instead of trusting the client to choose an arbitrary directory.
pub(all) struct ArchivedSessionPayload {
  session : String
  workspace : String
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
/// `worktree.create` names the workspace and exactly one conversation owner.
/// Existing clients send `session`; Codex sends `codex_thread`. Creation is
/// the binding, and that owner id doubles as the idempotency key for retries.
/// The host generates the worktree's name and returns it in the reply.
pub(all) struct WorktreeCreatePayload {
  workspace : String
  session : String?
  codex_thread : String?
} derive(Debug, Eq)

///|
pub impl FromJson for WorktreeCreatePayload with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected worktree creation payload"))
  }
  let workspace = match fields.get("workspace") {
    Some(String(value)) => value
    Some(_) =>
      raise JsonDecodeError((path.add_key("workspace"), "expected string"))
    None =>
      raise JsonDecodeError(
        (path.add_key("workspace"), "missing required field"),
      )
  }
  let session = match fields.get("session") {
    Some(String(value)) => Some(value)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("session"), "expected string or null"),
      )
  }
  let codex_thread = match fields.get("codex_thread") {
    Some(String(value)) => Some(value)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("codex_thread"), "expected string or null"),
      )
  }
  // Unknown fields remain forward-compatible, but ownership is deliberately
  // closed: a worktree belongs to one OpenSeek session or one Codex thread.
  if (session is Some(_)) == (codex_thread is Some(_)) {
    raise JsonDecodeError(
      (path, "expected exactly one of session or codex_thread"),
    )
  }
  { workspace, session, codex_thread }
}

///|
pub impl ToJson for WorktreeCreatePayload with fn to_json(self) {
  let fields : Map[String, Json] = { "workspace": Json::string(self.workspace) }
  if self.session is Some(session) {
    fields["session"] = Json::string(session)
  }
  if self.codex_thread is Some(codex_thread) {
    fields["codex_thread"] = Json::string(codex_thread)
  }
  Json::object(fields)
}

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
/// `base_hint` is the branch the diffstat should measure from, when the client
/// already knows it from the branch's pull request. Absent on the first probe,
/// and whenever there is no pull request to ask — the host then falls back to
/// the remote's default branch.
pub(all) struct GitBranchPayload {
  session : String
  cwd : String?
  base_hint : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
/// Address the same working directory as `git.branch` — the pull request is
/// looked up for whatever branch that directory has checked out, so the two
/// chips can never describe different branches. Codex-managed worktrees are
/// commonly detached; `branch_hint` is app-server's creation-time branch and
/// is accepted only when that local branch still points at the current HEAD.
pub(all) struct GitPullRequestPayload {
  session : String
  cwd : String?
  branch_hint : String?
} derive(Debug, Eq)

///|
pub impl FromJson for GitPullRequestPayload with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected Git pull-request payload"))
  }
  let session = match fields.get("session") {
    Some(String(value)) => value
    Some(_) =>
      raise JsonDecodeError((path.add_key("session"), "expected string"))
    None =>
      raise JsonDecodeError((path.add_key("session"), "missing required field"))
  }
  let cwd = match fields.get("cwd") {
    Some(String(value)) => Some(value)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError((path.add_key("cwd"), "expected string or null"))
  }
  let branch_hint = match fields.get("branch_hint") {
    Some(String(value)) => Some(value)
    Some(Null) | None => None
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("branch_hint"), "expected string or null"),
      )
  }
  { session, cwd, branch_hint }
}

///|
pub impl ToJson for GitPullRequestPayload with fn to_json(self) {
  let fields : Map[String, Json] = { "session": Json::string(self.session) }
  if self.cwd is Some(cwd) {
    fields["cwd"] = Json::string(cwd)
  }
  if self.branch_hint is Some(branch_hint) {
    fields["branch_hint"] = Json::string(branch_hint)
  }
  Json::object(fields)
}

///|
/// Address the Git working tree belonging to one conversation. The optional
/// workspace hint follows the filesystem operations' trust boundary: the host
/// accepts it only when it names a registered workspace and still routes a
/// worktree-bound conversation into its own checkout.
pub(all) struct GitChangesPayload {
  session : String
  workspace : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
/// Read one workspace-relative path from the supplied commit, falling back to
/// `HEAD` for older clients that omit `revision`. For a rename or copy, callers
/// pass the change row's `original_path` (the current `path` does not exist in
/// that commit); all other rows pass `path`. The host validates the path again
/// before passing it to Git.
pub(all) struct GitOriginalFilePayload {
  session : String
  workspace : String?
  path : String
  revision : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct LaunchAppPayload {
  session : String
  cwd : String?
  app : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct ReadDirPayload {
  path : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct SearchFilesPayload {
  path : String
  // One Quick Open cache session. The first request populates it; subsequent
  // queries reuse it until `fs.clear_file_search_cache` retires the key.
  cache_key : String
  query : String
  // Zero warms the cache without returning rows; interactive queries use the
  // picker limit. The Host applies its own hard upper bound.
  max_results : Int
  // Monotonic within the page. It identifies one cancellable query, not a
  // cache generation.
  generation : Int
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct CancelSearchFilesPayload {
  cache_key : String
  generation : Int
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct ClearFileSearchCachePayload {
  cache_key : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct ReadFilePayload {
  // Without `root`, `path` is absolute. With `root`, `root` is absolute and
  // `path` is relative to it; the host validates that pair before opening.
  path : String
  root : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct StatFilesPayload {
  paths : Array[String]
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct WatchWorkspacePayload {
  path : String
  files : Array[String]
  directories : Array[String]
  // Keep every non-ignored descendant observable while a workspace-wide file
  // index is live. Shallow mode remains sufficient for open files and the
  // explorer's explicitly listed directories.
  recursive : Bool?
  // Concrete watcher/failure identity. Clients change it for every desired
  // configuration so a replaced watcher's delayed failure is stale.
  generation : String
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
  session : String
  root : String
  path : String
} derive(Debug, Eq)

///|
pub impl FromJson for LspOpenPayload with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected LSP open payload"))
  }
  let session = match fields.get("session") {
    Some(String(value)) => value
    Some(_) =>
      raise JsonDecodeError((path.add_key("session"), "expected string"))
    None =>
      raise JsonDecodeError((path.add_key("session"), "missing required field"))
  }
  let root = match fields.get("root") {
    Some(String(value)) => value
    Some(_) => raise JsonDecodeError((path.add_key("root"), "expected string"))
    None =>
      raise JsonDecodeError((path.add_key("root"), "missing required field"))
  }
  let file_path = match fields.get("path") {
    Some(String(value)) => value
    Some(_) => raise JsonDecodeError((path.add_key("path"), "expected string"))
    None =>
      raise JsonDecodeError((path.add_key("path"), "missing required field"))
  }
  { session, root, path: file_path }
}

///|
pub impl ToJson for LspOpenPayload with fn to_json(self) {
  { "session": self.session, "root": self.root, "path": self.path }
}

///|
pub(all) struct LspHoverPayload {
  session : String
  root : String
  path : String
  line : Int
  character : Int
} derive(Debug, Eq)

///|
pub impl FromJson for LspHoverPayload with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected LSP hover payload"))
  }
  let session = match fields.get("session") {
    Some(String(value)) => value
    Some(_) =>
      raise JsonDecodeError((path.add_key("session"), "expected string"))
    None =>
      raise JsonDecodeError((path.add_key("session"), "missing required field"))
  }
  let root = match fields.get("root") {
    Some(String(value)) => value
    Some(_) => raise JsonDecodeError((path.add_key("root"), "expected string"))
    None =>
      raise JsonDecodeError((path.add_key("root"), "missing required field"))
  }
  let file_path = match fields.get("path") {
    Some(String(value)) => value
    Some(_) => raise JsonDecodeError((path.add_key("path"), "expected string"))
    None =>
      raise JsonDecodeError((path.add_key("path"), "missing required field"))
  }
  let line = match fields.get("line") {
    Some(Number(value, ..)) => value.to_int()
    Some(_) => raise JsonDecodeError((path.add_key("line"), "expected integer"))
    None =>
      raise JsonDecodeError((path.add_key("line"), "missing required field"))
  }
  let character = match fields.get("character") {
    Some(Number(value, ..)) => value.to_int()
    Some(_) =>
      raise JsonDecodeError((path.add_key("character"), "expected integer"))
    None =>
      raise JsonDecodeError(
        (path.add_key("character"), "missing required field"),
      )
  }
  { session, root, path: file_path, line, character }
}

///|
pub impl ToJson for LspHoverPayload with fn to_json(self) {
  {
    "session": self.session,
    "root": self.root,
    "path": self.path,
    "line": self.line,
    "character": self.character,
  }
}

///|
pub(all) struct WorkspaceSymbolsPayload {
  session : String
  root : String
  query : String
} derive(Debug, Eq)

///|
pub impl FromJson for WorkspaceSymbolsPayload with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected workspace-symbol payload"))
  }
  let session = match fields.get("session") {
    Some(String(value)) => value
    Some(_) =>
      raise JsonDecodeError((path.add_key("session"), "expected string"))
    None =>
      raise JsonDecodeError((path.add_key("session"), "missing required field"))
  }
  let root = match fields.get("root") {
    Some(String(value)) => value
    Some(_) => raise JsonDecodeError((path.add_key("root"), "expected string"))
    None =>
      raise JsonDecodeError((path.add_key("root"), "missing required field"))
  }
  let query = match fields.get("query") {
    Some(String(value)) => value
    Some(_) => raise JsonDecodeError((path.add_key("query"), "expected string"))
    None =>
      raise JsonDecodeError((path.add_key("query"), "missing required field"))
  }
  { session, root, query }
}

///|
pub impl ToJson for WorkspaceSymbolsPayload with fn to_json(self) {
  { "session": self.session, "root": self.root, "query": self.query }
}

///|
pub(all) struct MoonIdeNavigationPayload {
  session : String
  root : String
  path : String
  line : Int
  column : Int
} derive(Debug, Eq)

///|
pub impl FromJson for MoonIdeNavigationPayload with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected Moon IDE navigation payload"))
  }
  let session = match fields.get("session") {
    Some(String(value)) => value
    Some(_) =>
      raise JsonDecodeError((path.add_key("session"), "expected string"))
    None =>
      raise JsonDecodeError((path.add_key("session"), "missing required field"))
  }
  let root = match fields.get("root") {
    Some(String(value)) => value
    Some(_) => raise JsonDecodeError((path.add_key("root"), "expected string"))
    None =>
      raise JsonDecodeError((path.add_key("root"), "missing required field"))
  }
  let file_path = match fields.get("path") {
    Some(String(value)) => value
    Some(_) => raise JsonDecodeError((path.add_key("path"), "expected string"))
    None =>
      raise JsonDecodeError((path.add_key("path"), "missing required field"))
  }
  let line = match fields.get("line") {
    Some(Number(value, ..)) => value.to_int()
    Some(_) => raise JsonDecodeError((path.add_key("line"), "expected integer"))
    None =>
      raise JsonDecodeError((path.add_key("line"), "missing required field"))
  }
  let column = match fields.get("column") {
    Some(Number(value, ..)) => value.to_int()
    Some(_) =>
      raise JsonDecodeError((path.add_key("column"), "expected integer"))
    None =>
      raise JsonDecodeError((path.add_key("column"), "missing required field"))
  }
  { session, root, path: file_path, line, column }
}

///|
pub impl ToJson for MoonIdeNavigationPayload with fn to_json(self) {
  {
    "session": self.session,
    "root": self.root,
    "path": self.path,
    "line": self.line,
    "column": self.column,
  }
}

///|
pub(all) struct ExternalLinkPayload {
  url : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct BrowserOpenPayload {
  id : Int
  url : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct BrowserIdPayload {
  id : Int
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct BrowserBoundsPayload {
  id : Int
  x : Int
  y : Int
  width : Int
  height : Int
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct BrowserVisiblePayload {
  id : Int
  visible : Bool
} derive(Debug, Eq, FromJson, ToJson)
// Notification payloads.

///|
pub(all) struct ConnectedPayload {
  ready : Bool?
  // Device-native scratch base encoded as a frontend resource path. A host
  // cannot announce readiness without it: every Scratch conversation derives
  // its concrete filesystem and language-server root from this value.
  scratch_root : String
  // The global durable session store root, same encoding. Naming it on
  // connect lets clients classify any broadcast store root exactly — equal
  // to this value means the Scratch store, anything else a project store —
  // even while the projects registry reply is still in flight.
  session_root : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct StartedPayload {
  run_id : String
  submission_id : String?
  engine : String?
  model : String?
  max_steps : Int?
  session : String
  session_root : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct AgentEventPayload {
  run_id : String?
  // Engine events always belong to the durable session that owns the process;
  // only `run_id` may be absent for between-turn lifecycle events.
  session : String
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
  // The durable store root this commit was read from, as a frontend resource
  // path. Session ids are not globally unique across stores, so the
  // broadcast names the store half of the identity beside the id.
  session_root : String
} derive(Debug, Eq, FromJson, ToJson)

///|
/// One running sub-run's progress, as the host reads it from the child's own
/// durable record. `id` is the `sr-N` the `subrun_started` bracket carried,
/// which is what pairs this with the sub-run a client already knows about;
/// `session` names the child transcript it was read from. `steps` counts the
/// turns the child has recorded and `activity` is its last tool call — both
/// newest-fact, never a history: a client shows them and forgets them.
pub(all) struct SubrunProgressPayload {
  id : String
  session : String
  steps : Int
  activity : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct SessionChangedPayload {
  change : String
  session : String
  // The project store owning this record, or "" for Scratch. Session ids are
  // not globally unique across stores, so every invalidation carries both
  // halves of the durable identity.
  workspace : String
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
/// `workspace.settings_get` names the workspace whose desktop-owned
/// settings file to read.
pub(all) struct WorkspaceSettingsGetPayload {
  workspace : String
} derive(Debug, Eq, FromJson, ToJson)

///|
/// `workspace.settings_set` patches one workspace's settings; absent fields
/// stay unchanged. The committed state comes back in the reply and in the
/// `workspace.settings_changed` broadcast.
pub(all) struct WorkspaceSettingsSetPayload {
  workspace : String
  worktree_mode : Bool?
  checkout_submodules : Bool?
  submodule_checkout_timeout_seconds : Int?
} derive(Debug, Eq, FromJson, ToJson)

///|
/// One workspace's desktop-owned settings: the reply to both settings
/// methods and the `workspace.settings_changed` payload. `worktree_mode` is
/// where a NEW conversation in this workspace starts — the workspace root,
/// or a fresh git worktree bound to that conversation. The frontend and host
/// ship together, so reply and broadcast fields evolve in lockstep.
pub(all) struct WorkspaceSettingsPayload {
  workspace : String
  worktree_mode : Bool
  checkout_submodules : Bool
  submodule_checkout_timeout_seconds : Int
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
  root : String
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
  root : String
  baseline : Bool
  events : Array[FsEventPayload]
  // Identifies the concrete activated watcher that produced this batch.
  generation : String
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct FsWatchFailedPayload {
  root : String
  message : String
  // Identifies the concrete watcher that produced this failure.
  generation : String
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
