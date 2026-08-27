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
/// OpenSeek's closed reasoning setting. Keeping the wire values typed in the
/// protocol package makes every Desktop command reject schema drift before an
/// engine's current phase can affect how the request is handled.
pub(all) enum OpenSeekThinking {
  ThinkingOff
  ThinkingHigh
  ThinkingMax
} derive(Debug, Eq)

///|
pub fn OpenSeekThinking::wire(self : OpenSeekThinking) -> String {
  match self {
    ThinkingOff => "no"
    ThinkingHigh => "high"
    ThinkingMax => "max"
  }
}

///|
/// Parse the same wire spelling from non-JSON configuration such as the
/// inherited OPENSEEK_THINKING environment variable.
pub fn OpenSeekThinking::parse(value : String) -> OpenSeekThinking? {
  match value {
    "no" => Some(ThinkingOff)
    "high" => Some(ThinkingHigh)
    "max" => Some(ThinkingMax)
    _ => None
  }
}

///|
pub(all) struct StartPayload {
  task : String
  // Optional client-minted lifecycle identity echoed with `agent.started`.
  // Blank ids and ids longer than 128 UTF-8 bytes are ignored.
  submission_id : String?
  model : String?
  // Optional keeps older clients compatible; a present value is decoded into
  // the closed protocol type before the command reaches the host operation.
  thinking : OpenSeekThinking?
  max_steps : Int?
  // Every desktop run belongs to a durable conversation. The engine rejects
  // a blank id before it acquires that conversation's record lease.
  session : String
  // The registered workspace directory this conversation works in. A
  // session bound to one of that workspace's worktrees (`worktree.create`
  // binds at creation) runs in that checkout — the start itself never names
  // or mutates worktrees.
  workspace : String?
} derive(Debug, Eq)

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
/// One answer to an engine's `approval_requested`, addressed by the id that
/// event carried. `run_id` guards the same race a steer's does: a decision
/// minted against one run must not settle a question in the next.
pub(all) struct ApprovalPayload {
  id : String
  allow : Bool
  run_id : String?
} derive(Debug, Eq)

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
  thinking : OpenSeekThinking?
  max_steps : Int?
  workspace : String?
} derive(Debug, Eq)

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
  thinking : OpenSeekThinking?
  max_steps : Int?
  workspace : String?
} derive(Debug, Eq)

///|
pub(all) struct LoadSessionPayload {
  session : String
  // The workspace holding the session, when the client already knows it.
  workspace : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
/// Export one exact conversation from one registered workspace. The native
/// window chooses the destination; no filesystem destination crosses this
/// protocol boundary.
pub(all) struct SessionExportPayload {
  session : String
  workspace : String
  title : String
  archived : Bool
} derive(Debug, Eq)

///|
/// Decode the exact store identity and display metadata needed by an export.
/// Every field is required and typed; unknown fields are ignored so a newer
/// frontend can add metadata without breaking an older host.
pub impl FromJson for SessionExportPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session export payload")
  {
    session: object.required_string("session"),
    workspace: object.required_string("workspace"),
    title: object.required_string("title"),
    archived: object.required_bool("archived"),
  }
}

///|
pub impl ToJson for SessionExportPayload with fn to_json(self) {
  {
    "session": self.session,
    "workspace": self.workspace,
    "title": self.title,
    "archived": self.archived,
  }
}

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
/// `workspace` is the host-reported project resource path; the host validates
/// it against its registry instead of trusting the client to choose an
/// arbitrary directory.
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
  let object = JsonObject::of(fields, path)
  let workspace = object.required_string("workspace")
  let session = object.optional_string("session")
  let codex_thread = object.optional_string("codex_thread")
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
  let object = JsonObject::of(fields, path)
  let session = object.required_string("session")
  let cwd = object.optional_string("cwd")
  let branch_hint = object.optional_string("branch_hint")
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
/// Read one immutable page of repository history. The first request omits
/// `snapshot`; the host captures the selected refs as full commit identities
/// and echoes them back. Later pages resend that snapshot so moving refs cannot
/// duplicate or skip commits mid-scroll.
pub(all) struct GitHistoryPayload {
  session : String
  workspace : String?
  snapshot : GitHistorySnapshot?
  skip : Int
  limit : Int
} derive(Debug, Eq)

///|
/// List the paths changed by one immutable commit, scoped to the conversation
/// workspace. Merge commits compare against their first parent; root commits
/// compare against Git's empty tree.
pub(all) struct GitCommitChangesPayload {
  session : String
  workspace : String?
  commit : String
} derive(Debug, Eq)

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
/// Search workspace text through the Host's bundled ripgrep. `session_key`
/// names one panel/search lifetime; generations are monotonic inside it, so a
/// newer request can cancel an older process without affecting another panel.
pub(all) struct SearchTextPayload {
  root : String
  query : String
  regex : Bool
  case_sensitive : Bool
  whole_word : Bool
  include_glob : String
  exclude_glob : String
  session_key : String
  generation : Int
  max_results : Int
} derive(Debug, Eq)

///|
/// Cancel one text-search generation. The Host also remembers the cancelled
/// frontier so cancel-before-search message ordering remains safe.
pub(all) struct CancelSearchTextPayload {
  session_key : String
  generation : Int
} derive(Debug, Eq)

///|
/// Search workspace MoonBit code with structural patterns through the Host's
/// moongrep provider. `session_key` and `generation` follow the text-search
/// contract exactly, so one panel can own both modes without replaying an old
/// semantic reply as current text results. `patterns` contains one or more
/// anonymous structural moongrep patterns.
pub(all) struct SearchSemanticPayload {
  root : String
  patterns : Array[String]
  include_glob : String
  exclude_glob : String
  session_key : String
  generation : Int
  max_results : Int
} derive(Debug, Eq)

///|
/// Cancel one semantic-search generation. The Host also remembers the
/// cancelled frontier so cancel-before-search message ordering remains safe.
pub(all) struct CancelSearchSemanticPayload {
  session_key : String
  generation : Int
} derive(Debug, Eq)

///|
/// One batch of an in-flight semantic search, pushed as a connection
/// notification so the client can render hits before the final reply arrives.
/// The reply remains authoritative: `matches` are the Host's partial
/// accumulation and the client replaces them when `SearchSemanticReply`
/// lands. `session_key`/`generation` carry the same fence as the reply so a
/// stale stream can never overwrite a newer search.
pub(all) struct SemanticSearchProgressPayload {
  root : String
  session_key : String
  generation : Int
  matches : Array[SemanticSearchHit]
  match_count : Int
  file_count : Int
} derive(Debug, Eq)

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
/// Create one direct child of a directory already reached through the project
/// picker. Keeping the parent and leaf separate lets the host reject path
/// traversal before touching the filesystem.
pub(all) struct CreateDirectoryPayload {
  parent : String
  name : String
} derive(Debug, Eq)

///|
pub impl FromJson for CreateDirectoryPayload with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected directory creation payload"))
  }
  let parent = match fields.get("parent") {
    Some(String(value)) => value
    Some(Null) =>
      raise JsonDecodeError(
        (path.add_key("parent"), "required field cannot be null"),
      )
    Some(_) =>
      raise JsonDecodeError((path.add_key("parent"), "expected string"))
    None =>
      raise JsonDecodeError((path.add_key("parent"), "missing required field"))
  }
  let name = match fields.get("name") {
    Some(String(value)) => value
    Some(Null) =>
      raise JsonDecodeError(
        (path.add_key("name"), "required field cannot be null"),
      )
    Some(_) => raise JsonDecodeError((path.add_key("name"), "expected string"))
    None =>
      raise JsonDecodeError((path.add_key("name"), "missing required field"))
  }
  // Unknown fields are intentionally ignored for forward compatibility; the
  // host still validates the two required path components before mutation.
  { parent, name }
}

///|
pub impl ToJson for CreateDirectoryPayload with fn to_json(self) {
  { "parent": self.parent, "name": self.name }
}

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
  let object = JsonObject::of(fields, path)
  let session = object.required_string("session")
  let root = object.required_string("root")
  let file_path = object.required_string("path")
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
  let object = JsonObject::of(fields, path)
  let session = object.required_string("session")
  let root = object.required_string("root")
  let file_path = object.required_string("path")
  let line = object.required_int("line")
  let character = object.required_int("character")
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
  let object = JsonObject::of(fields, path)
  let session = object.required_string("session")
  let root = object.required_string("root")
  let query = object.required_string("query")
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
  let object = JsonObject::of(fields, path)
  let session = object.required_string("session")
  let root = object.required_string("root")
  let file_path = object.required_string("path")
  let line = object.required_int("line")
  let column = object.required_int("column")
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
  dark : Bool
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct BrowserIdPayload {
  id : Int
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct BrowserThemePayload {
  id : Int
  dark : Bool
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
/// How much of the host is up behind an `agent.connected`. Both spellings
/// ask the client for the same thing — this connection is live, re-read your
/// state — and differ only in whether a run can start yet.
pub(all) enum ConnectedStage {
  /// A transport accepted this client. The engine pump may still be between
  /// generations, so a start can be refused until `Serving` follows.
  Accepted
  /// The engine pump entered a serving generation and accepts runs.
  Serving
} derive(Debug, Eq)

///|
pub impl ToJson for ConnectedStage with fn to_json(self) {
  match self {
    Accepted => "accepted"
    Serving => "serving"
  }
}

///|
/// The stage is a bare string, and an unrecognized one is refused rather than
/// read as the weaker of the two: a client acts on this field to decide
/// whether a start can be refused, and a spelling this build does not know is
/// a host it cannot reason about. Host and clients ship together, so a third
/// stage arrives with the code that understands it.
pub impl FromJson for ConnectedStage with fn from_json(json, path) {
  guard json is String(stage) else {
    raise JsonDecodeError((path, "expected connected stage"))
  }
  match stage {
    "accepted" => Accepted
    "serving" => Serving
    _ => raise JsonDecodeError((path, "unknown connected stage"))
  }
}

///|
/// `agent.connected` is a signal rather than a description: every client
/// answers it by re-reading its state. `stage` says how much of the host is
/// up, which is all a client can act on beyond that.
pub(all) struct ConnectedPayload {
  stage : ConnectedStage
} derive(Debug, Eq)

///|
pub impl ToJson for ConnectedPayload with fn to_json(self) {
  { "stage": ToJson::to_json(self.stage) }
}

///|
/// `stage` is the whole payload: a notification carrying none, or one this
/// build cannot read, says nothing a client can act on, so it is refused
/// rather than guessed at — `Notification::from_wire` drops it. Fields this
/// build does not know are ignored, leaving the wire room to grow.
pub impl FromJson for ConnectedPayload with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected connected payload"))
  }
  guard fields.get("stage") is Some(stage) else {
    raise JsonDecodeError((path.add_key("stage"), "missing required field"))
  }
  { stage: @json.from_json(stage, path=path.add_key("stage")) }
}

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
/// A run's one lifecycle close. `run_id` and `status` are the message: a
/// report missing either names no run or no outcome, and is refused rather
/// than settled as something. The two optionals are evidence a close may
/// simply not have — a failed turn has no answer, a turn that ended without
/// the process dying has no exit code — so absent, `null` and a value of the
/// wrong type all mean the same "not reported", the answer an older or newer
/// host gives for a field it does not write.
pub(all) struct FinishedPayload {
  run_id : String
  status : String
  answer : String?
  exit_code : Int?
} derive(Debug, Eq)

///|
pub impl ToJson for FinishedPayload with fn to_json(self) {
  let fields = {
    "run_id": Json::string(self.run_id),
    "status": Json::string(self.status),
  }
  if self.answer is Some(answer) {
    fields["answer"] = Json::string(answer)
  }
  if self.exit_code is Some(exit_code) {
    fields["exit_code"] = Json::number(exit_code.to_double())
  }
  Json::object(fields)
}

///|
pub impl FromJson for FinishedPayload with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected finished payload"))
  }
  guard fields.get("run_id") is Some(String(run_id)) else {
    raise JsonDecodeError((path.add_key("run_id"), "expected a run id"))
  }
  guard fields.get("status") is Some(String(status)) else {
    raise JsonDecodeError((path.add_key("status"), "expected a run status"))
  }
  {
    run_id,
    status,
    answer: match fields.get("answer") {
      Some(String(value)) => Some(value)
      _ => None
    },
    exit_code: match fields.get("exit_code") {
      Some(Number(value, ..)) => Some(value.to_int())
      _ => None
    },
  }
}

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
  // The project store owning this record. Session ids are not globally
  // unique across stores, so every invalidation carries both halves of the
  // durable identity.
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

///|
pub extend AgentErrorPayload with Debug::{to_repr}

///|
pub extend AgentErrorPayload with FromJson::{from_json}

///|
pub extend AgentErrorPayload with Eq::{equal, not_equal}

///|
pub extend AgentErrorPayload with ToJson::{to_json}

///|
pub extend AgentEventPayload with Debug::{to_repr}

///|
pub extend AgentEventPayload with FromJson::{from_json}

///|
pub extend AgentEventPayload with Eq::{equal, not_equal}

///|
pub extend AgentEventPayload with ToJson::{to_json}

///|
pub extend AppInfoReply with Debug::{to_repr}

///|
pub extend AppInfoReply with FromJson::{from_json}

///|
pub extend AppInfoReply with Eq::{equal, not_equal}

///|
pub extend AppInfoReply with ToJson::{to_json}

///|
pub extend ApprovalPayload with Debug::{to_repr}

///|
pub extend ApprovalPayload with FromJson::{from_json}

///|
pub extend ApprovalPayload with Eq::{equal, not_equal}

///|
pub extend ApprovalPayload with ToJson::{to_json}

///|
pub extend ArchivedSessionPayload with Debug::{to_repr}

///|
pub extend ArchivedSessionPayload with FromJson::{from_json}

///|
pub extend ArchivedSessionPayload with Eq::{equal, not_equal}

///|
pub extend ArchivedSessionPayload with ToJson::{to_json}

///|
pub extend AuthDevicePayload with Debug::{to_repr}

///|
pub extend AuthDevicePayload with FromJson::{from_json}

///|
pub extend AuthDevicePayload with Eq::{equal, not_equal}

///|
pub extend AuthDevicePayload with ToJson::{to_json}

///|
pub extend AuthStatusPayload with Debug::{to_repr}

///|
pub extend AuthStatusPayload with FromJson::{from_json}

///|
pub extend AuthStatusPayload with Eq::{equal, not_equal}

///|
pub extend AuthStatusPayload with ToJson::{to_json}

///|
pub extend AuthUserPayload with Debug::{to_repr}

///|
pub extend AuthUserPayload with FromJson::{from_json}

///|
pub extend AuthUserPayload with Eq::{equal, not_equal}

///|
pub extend AuthUserPayload with ToJson::{to_json}

///|
pub extend BrowseDirectoryPayload with Debug::{to_repr}

///|
pub extend BrowseDirectoryPayload with FromJson::{from_json}

///|
pub extend BrowseDirectoryPayload with Eq::{equal, not_equal}

///|
pub extend BrowseDirectoryPayload with ToJson::{to_json}

///|
pub extend BrowserBoundsPayload with Debug::{to_repr}

///|
pub extend BrowserBoundsPayload with FromJson::{from_json}

///|
pub extend BrowserBoundsPayload with Eq::{equal, not_equal}

///|
pub extend BrowserBoundsPayload with ToJson::{to_json}

///|
pub extend BrowserIdPayload with Debug::{to_repr}

///|
pub extend BrowserIdPayload with FromJson::{from_json}

///|
pub extend BrowserIdPayload with Eq::{equal, not_equal}

///|
pub extend BrowserIdPayload with ToJson::{to_json}

///|
pub extend BrowserOpenPayload with Debug::{to_repr}

///|
pub extend BrowserOpenPayload with FromJson::{from_json}

///|
pub extend BrowserOpenPayload with Eq::{equal, not_equal}

///|
pub extend BrowserOpenPayload with ToJson::{to_json}

///|
pub extend BrowserVisiblePayload with Debug::{to_repr}

///|
pub extend BrowserVisiblePayload with FromJson::{from_json}

///|
pub extend BrowserVisiblePayload with Eq::{equal, not_equal}

///|
pub extend BrowserVisiblePayload with ToJson::{to_json}

///|
pub extend CancelPayload with Debug::{to_repr}

///|
pub extend CancelPayload with FromJson::{from_json}

///|
pub extend CancelPayload with Eq::{equal, not_equal}

///|
pub extend CancelPayload with ToJson::{to_json}

///|
pub extend CancelSearchFilesPayload with Debug::{to_repr}

///|
pub extend CancelSearchFilesPayload with FromJson::{from_json}

///|
pub extend CancelSearchFilesPayload with Eq::{equal, not_equal}

///|
pub extend CancelSearchFilesPayload with ToJson::{to_json}

///|
pub extend CancelSearchTextPayload with Debug::{to_repr}

///|
pub extend CancelSearchTextPayload with FromJson::{from_json}

///|
pub extend CancelSearchTextPayload with Eq::{equal, not_equal}

///|
pub extend CancelSearchTextPayload with ToJson::{to_json}

///|
pub extend ClearFileSearchCachePayload with Debug::{to_repr}

///|
pub extend ClearFileSearchCachePayload with FromJson::{from_json}

///|
pub extend ClearFileSearchCachePayload with Eq::{equal, not_equal}

///|
pub extend ClearFileSearchCachePayload with ToJson::{to_json}

///|
pub extend CompactPayload with Debug::{to_repr}

///|
pub extend CompactPayload with FromJson::{from_json}

///|
pub extend CompactPayload with Eq::{equal, not_equal}

///|
pub extend CompactPayload with ToJson::{to_json}

///|
pub extend ConnectedPayload with Debug::{to_repr}

///|
pub extend ConnectedPayload with FromJson::{from_json}

///|
pub extend ConnectedPayload with Eq::{equal, not_equal}

///|
pub extend ConnectedPayload with ToJson::{to_json}

///|
pub extend ConnectedStage with Debug::{to_repr}

///|
pub extend ConnectedStage with FromJson::{from_json}

///|
pub extend ConnectedStage with Eq::{equal, not_equal}

///|
pub extend ConnectedStage with ToJson::{to_json}

///|
pub extend DiagnosticsPayload with Debug::{to_repr}

///|
pub extend DiagnosticsPayload with FromJson::{from_json}

///|
pub extend DiagnosticsPayload with Eq::{equal, not_equal}

///|
pub extend DiagnosticsPayload with ToJson::{to_json}

///|
pub extend ExternalLinkPayload with Debug::{to_repr}

///|
pub extend ExternalLinkPayload with FromJson::{from_json}

///|
pub extend ExternalLinkPayload with Eq::{equal, not_equal}

///|
pub extend ExternalLinkPayload with ToJson::{to_json}

///|
pub extend FinishedPayload with Debug::{to_repr}

///|
pub extend FinishedPayload with FromJson::{from_json}

///|
pub extend FinishedPayload with Eq::{equal, not_equal}

///|
pub extend FinishedPayload with ToJson::{to_json}

///|
pub extend FsChangedPayload with Debug::{to_repr}

///|
pub extend FsChangedPayload with FromJson::{from_json}

///|
pub extend FsChangedPayload with Eq::{equal, not_equal}

///|
pub extend FsChangedPayload with ToJson::{to_json}

///|
pub extend FsEventPayload with Debug::{to_repr}

///|
pub extend FsEventPayload with FromJson::{from_json}

///|
pub extend FsEventPayload with Eq::{equal, not_equal}

///|
pub extend FsEventPayload with ToJson::{to_json}

///|
pub extend FsWatchFailedPayload with Debug::{to_repr}

///|
pub extend FsWatchFailedPayload with FromJson::{from_json}

///|
pub extend FsWatchFailedPayload with Eq::{equal, not_equal}

///|
pub extend FsWatchFailedPayload with ToJson::{to_json}

///|
pub extend GitBranchPayload with Debug::{to_repr}

///|
pub extend GitBranchPayload with FromJson::{from_json}

///|
pub extend GitBranchPayload with Eq::{equal, not_equal}

///|
pub extend GitBranchPayload with ToJson::{to_json}

///|
pub extend GitChangesPayload with Debug::{to_repr}

///|
pub extend GitChangesPayload with FromJson::{from_json}

///|
pub extend GitChangesPayload with Eq::{equal, not_equal}

///|
pub extend GitChangesPayload with ToJson::{to_json}

///|
pub extend GitCommitChangesPayload with Debug::{to_repr}

///|
pub extend GitCommitChangesPayload with FromJson::{from_json}

///|
pub extend GitCommitChangesPayload with Eq::{equal, not_equal}

///|
pub extend GitCommitChangesPayload with ToJson::{to_json}

///|
pub extend GitHistoryPayload with Debug::{to_repr}

///|
pub extend GitHistoryPayload with FromJson::{from_json}

///|
pub extend GitHistoryPayload with Eq::{equal, not_equal}

///|
pub extend GitHistoryPayload with ToJson::{to_json}

///|
pub extend GitOriginalFilePayload with Debug::{to_repr}

///|
pub extend GitOriginalFilePayload with FromJson::{from_json}

///|
pub extend GitOriginalFilePayload with Eq::{equal, not_equal}

///|
pub extend GitOriginalFilePayload with ToJson::{to_json}

///|
pub extend GitPullRequestPayload with Debug::{to_repr}

///|
pub extend GitPullRequestPayload with FromJson::{from_json}

///|
pub extend GitPullRequestPayload with Eq::{equal, not_equal}

///|
pub extend GitPullRequestPayload with ToJson::{to_json}

///|
pub extend GoalPayload with Debug::{to_repr}

///|
pub extend GoalPayload with FromJson::{from_json}

///|
pub extend GoalPayload with Eq::{equal, not_equal}

///|
pub extend GoalPayload with ToJson::{to_json}

///|
pub extend InstallSkillPayload with Debug::{to_repr}

///|
pub extend InstallSkillPayload with FromJson::{from_json}

///|
pub extend InstallSkillPayload with Eq::{equal, not_equal}

///|
pub extend InstallSkillPayload with ToJson::{to_json}

///|
pub extend KnownRunPayload with Debug::{to_repr}

///|
pub extend KnownRunPayload with FromJson::{from_json}

///|
pub extend KnownRunPayload with Eq::{equal, not_equal}

///|
pub extend KnownRunPayload with ToJson::{to_json}

///|
pub extend LoadSessionPayload with Debug::{to_repr}

///|
pub extend LoadSessionPayload with FromJson::{from_json}

///|
pub extend LoadSessionPayload with Eq::{equal, not_equal}

///|
pub extend LoadSessionPayload with ToJson::{to_json}

///|
pub extend SessionExportPayload with Debug::{to_repr}

///|
pub extend SessionExportPayload with FromJson::{from_json}

///|
pub extend SessionExportPayload with Eq::{equal, not_equal}

///|
pub extend SessionExportPayload with ToJson::{to_json}

///|
pub extend LspHoverPayload with Debug::{to_repr}

///|
pub extend LspHoverPayload with FromJson::{from_json}

///|
pub extend LspHoverPayload with Eq::{equal, not_equal}

///|
pub extend LspHoverPayload with ToJson::{to_json}

///|
pub extend LspOpenPayload with Debug::{to_repr}

///|
pub extend LspOpenPayload with FromJson::{from_json}

///|
pub extend LspOpenPayload with Eq::{equal, not_equal}

///|
pub extend LspOpenPayload with ToJson::{to_json}

///|
pub extend MoonIdeNavigationPayload with Debug::{to_repr}

///|
pub extend MoonIdeNavigationPayload with FromJson::{from_json}

///|
pub extend MoonIdeNavigationPayload with Eq::{equal, not_equal}

///|
pub extend MoonIdeNavigationPayload with ToJson::{to_json}

///|
pub extend OpenSeekThinking with Debug::{to_repr}

///|
pub extend OpenSeekThinking with FromJson::{from_json}

///|
pub extend OpenSeekThinking with Eq::{equal, not_equal}

///|
pub extend OpenSeekThinking with ToJson::{to_json}

///|
pub extend OpenPathPayload with Debug::{to_repr}

///|
pub extend OpenPathPayload with FromJson::{from_json}

///|
pub extend OpenPathPayload with Eq::{equal, not_equal}

///|
pub extend OpenPathPayload with ToJson::{to_json}

///|
pub extend ReadDirPayload with Debug::{to_repr}

///|
pub extend ReadDirPayload with FromJson::{from_json}

///|
pub extend ReadDirPayload with Eq::{equal, not_equal}

///|
pub extend ReadDirPayload with ToJson::{to_json}

///|
pub extend ReadFilePayload with Debug::{to_repr}

///|
pub extend ReadFilePayload with FromJson::{from_json}

///|
pub extend ReadFilePayload with Eq::{equal, not_equal}

///|
pub extend ReadFilePayload with ToJson::{to_json}

///|
pub extend RunsPayload with Debug::{to_repr}

///|
pub extend RunsPayload with FromJson::{from_json}

///|
pub extend RunsPayload with Eq::{equal, not_equal}

///|
pub extend RunsPayload with ToJson::{to_json}

///|
pub extend SearchFilesPayload with Debug::{to_repr}

///|
pub extend SearchFilesPayload with FromJson::{from_json}

///|
pub extend SearchFilesPayload with Eq::{equal, not_equal}

///|
pub extend SearchFilesPayload with ToJson::{to_json}

///|
pub extend SearchTextPayload with Debug::{to_repr}

///|
pub extend SearchTextPayload with FromJson::{from_json}

///|
pub extend SearchTextPayload with Eq::{equal, not_equal}

///|
pub extend SearchTextPayload with ToJson::{to_json}

///|
pub extend SessionChangedPayload with Debug::{to_repr}

///|
pub extend SessionChangedPayload with FromJson::{from_json}

///|
pub extend SessionChangedPayload with Eq::{equal, not_equal}

///|
pub extend SessionChangedPayload with ToJson::{to_json}

///|
pub extend SessionCommitPayload with Debug::{to_repr}

///|
pub extend SessionCommitPayload with FromJson::{from_json}

///|
pub extend SessionCommitPayload with Eq::{equal, not_equal}

///|
pub extend SessionCommitPayload with ToJson::{to_json}

///|
pub extend SessionPayload with Debug::{to_repr}

///|
pub extend SessionPayload with FromJson::{from_json}

///|
pub extend SessionPayload with Eq::{equal, not_equal}

///|
pub extend SessionPayload with ToJson::{to_json}

///|
pub extend SettingsSetPayload with Debug::{to_repr}

///|
pub extend SettingsSetPayload with FromJson::{from_json}

///|
pub extend SettingsSetPayload with Eq::{equal, not_equal}

///|
pub extend SettingsSetPayload with ToJson::{to_json}

///|
pub extend SettingsStatusPayload with Debug::{to_repr}

///|
pub extend SettingsStatusPayload with FromJson::{from_json}

///|
pub extend SettingsStatusPayload with Eq::{equal, not_equal}

///|
pub extend SettingsStatusPayload with ToJson::{to_json}

///|
pub extend StartPayload with Debug::{to_repr}

///|
pub extend StartPayload with FromJson::{from_json}

///|
pub extend StartPayload with Eq::{equal, not_equal}

///|
pub extend StartPayload with ToJson::{to_json}

///|
pub extend StartedPayload with Debug::{to_repr}

///|
pub extend StartedPayload with FromJson::{from_json}

///|
pub extend StartedPayload with Eq::{equal, not_equal}

///|
pub extend StartedPayload with ToJson::{to_json}

///|
pub extend StatFilesPayload with Debug::{to_repr}

///|
pub extend StatFilesPayload with FromJson::{from_json}

///|
pub extend StatFilesPayload with Eq::{equal, not_equal}

///|
pub extend StatFilesPayload with ToJson::{to_json}

///|
pub extend SteerPayload with Debug::{to_repr}

///|
pub extend SteerPayload with FromJson::{from_json}

///|
pub extend SteerPayload with Eq::{equal, not_equal}

///|
pub extend SteerPayload with ToJson::{to_json}

///|
pub extend SubrunProgressPayload with Debug::{to_repr}

///|
pub extend SubrunProgressPayload with FromJson::{from_json}

///|
pub extend SubrunProgressPayload with Eq::{equal, not_equal}

///|
pub extend SubrunProgressPayload with ToJson::{to_json}

///|
pub extend TerminalAckPayload with Debug::{to_repr}

///|
pub extend TerminalAckPayload with FromJson::{from_json}

///|
pub extend TerminalAckPayload with Eq::{equal, not_equal}

///|
pub extend TerminalAckPayload with ToJson::{to_json}

///|
pub extend TerminalClosePayload with Debug::{to_repr}

///|
pub extend TerminalClosePayload with FromJson::{from_json}

///|
pub extend TerminalClosePayload with Eq::{equal, not_equal}

///|
pub extend TerminalClosePayload with ToJson::{to_json}

///|
pub extend TerminalExitPayload with Debug::{to_repr}

///|
pub extend TerminalExitPayload with FromJson::{from_json}

///|
pub extend TerminalExitPayload with Eq::{equal, not_equal}

///|
pub extend TerminalExitPayload with ToJson::{to_json}

///|
pub extend TerminalInputPayload with Debug::{to_repr}

///|
pub extend TerminalInputPayload with FromJson::{from_json}

///|
pub extend TerminalInputPayload with Eq::{equal, not_equal}

///|
pub extend TerminalInputPayload with ToJson::{to_json}

///|
pub extend TerminalOpenPayload with Debug::{to_repr}

///|
pub extend TerminalOpenPayload with FromJson::{from_json}

///|
pub extend TerminalOpenPayload with Eq::{equal, not_equal}

///|
pub extend TerminalOpenPayload with ToJson::{to_json}

///|
pub extend TerminalOutputPayload with Debug::{to_repr}

///|
pub extend TerminalOutputPayload with FromJson::{from_json}

///|
pub extend TerminalOutputPayload with Eq::{equal, not_equal}

///|
pub extend TerminalOutputPayload with ToJson::{to_json}

///|
pub extend TerminalResizePayload with Debug::{to_repr}

///|
pub extend TerminalResizePayload with FromJson::{from_json}

///|
pub extend TerminalResizePayload with Eq::{equal, not_equal}

///|
pub extend TerminalResizePayload with ToJson::{to_json}

///|
pub extend UninstallSkillPayload with Debug::{to_repr}

///|
pub extend UninstallSkillPayload with FromJson::{from_json}

///|
pub extend UninstallSkillPayload with Eq::{equal, not_equal}

///|
pub extend UninstallSkillPayload with ToJson::{to_json}

///|
pub extend UpdateDownloadFailedPayload with Debug::{to_repr}

///|
pub extend UpdateDownloadFailedPayload with FromJson::{from_json}

///|
pub extend UpdateDownloadFailedPayload with Eq::{equal, not_equal}

///|
pub extend UpdateDownloadFailedPayload with ToJson::{to_json}

///|
pub extend UpdateDownloadProgressPayload with Debug::{to_repr}

///|
pub extend UpdateDownloadProgressPayload with FromJson::{from_json}

///|
pub extend UpdateDownloadProgressPayload with Eq::{equal, not_equal}

///|
pub extend UpdateDownloadProgressPayload with ToJson::{to_json}

///|
pub extend UpdateDownloadedPayload with Debug::{to_repr}

///|
pub extend UpdateDownloadedPayload with FromJson::{from_json}

///|
pub extend UpdateDownloadedPayload with Eq::{equal, not_equal}

///|
pub extend UpdateDownloadedPayload with ToJson::{to_json}

///|
pub extend WatchWorkspacePayload with Debug::{to_repr}

///|
pub extend WatchWorkspacePayload with FromJson::{from_json}

///|
pub extend WatchWorkspacePayload with Eq::{equal, not_equal}

///|
pub extend WatchWorkspacePayload with ToJson::{to_json}

///|
pub extend WorkspacePayload with Debug::{to_repr}

///|
pub extend WorkspacePayload with FromJson::{from_json}

///|
pub extend WorkspacePayload with Eq::{equal, not_equal}

///|
pub extend WorkspacePayload with ToJson::{to_json}

///|
pub extend WorkspaceSettingsGetPayload with Debug::{to_repr}

///|
pub extend WorkspaceSettingsGetPayload with FromJson::{from_json}

///|
pub extend WorkspaceSettingsGetPayload with Eq::{equal, not_equal}

///|
pub extend WorkspaceSettingsGetPayload with ToJson::{to_json}

///|
pub extend WorkspaceSettingsPayload with Debug::{to_repr}

///|
pub extend WorkspaceSettingsPayload with FromJson::{from_json}

///|
pub extend WorkspaceSettingsPayload with Eq::{equal, not_equal}

///|
pub extend WorkspaceSettingsPayload with ToJson::{to_json}

///|
pub extend WorkspaceSettingsSetPayload with Debug::{to_repr}

///|
pub extend WorkspaceSettingsSetPayload with FromJson::{from_json}

///|
pub extend WorkspaceSettingsSetPayload with Eq::{equal, not_equal}

///|
pub extend WorkspaceSettingsSetPayload with ToJson::{to_json}

///|
pub extend WorkspaceSymbolsPayload with Debug::{to_repr}

///|
pub extend WorkspaceSymbolsPayload with FromJson::{from_json}

///|
pub extend WorkspaceSymbolsPayload with Eq::{equal, not_equal}

///|
pub extend WorkspaceSymbolsPayload with ToJson::{to_json}

///|
pub extend WorkspacesChangedPayload with Debug::{to_repr}

///|
pub extend WorkspacesChangedPayload with FromJson::{from_json}

///|
pub extend WorkspacesChangedPayload with Eq::{equal, not_equal}

///|
pub extend WorkspacesChangedPayload with ToJson::{to_json}

///|
pub extend WorktreeChangedPayload with Debug::{to_repr}

///|
pub extend WorktreeChangedPayload with FromJson::{from_json}

///|
pub extend WorktreeChangedPayload with Eq::{equal, not_equal}

///|
pub extend WorktreeChangedPayload with ToJson::{to_json}

///|
pub extend WorktreeCreatePayload with Debug::{to_repr}

///|
pub extend WorktreeCreatePayload with FromJson::{from_json}

///|
pub extend WorktreeCreatePayload with Eq::{equal, not_equal}

///|
pub extend WorktreeCreatePayload with ToJson::{to_json}

///|
pub extend WorktreeListPayload with Debug::{to_repr}

///|
pub extend WorktreeListPayload with FromJson::{from_json}

///|
pub extend WorktreeListPayload with Eq::{equal, not_equal}

///|
pub extend WorktreeListPayload with ToJson::{to_json}

///|
pub extend WorktreeRemovePayload with Debug::{to_repr}

///|
pub extend WorktreeRemovePayload with FromJson::{from_json}

///|
pub extend WorktreeRemovePayload with Eq::{equal, not_equal}

///|
pub extend WorktreeRemovePayload with ToJson::{to_json}
