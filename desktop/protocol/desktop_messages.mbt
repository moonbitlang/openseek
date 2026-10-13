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
  // Original images as data URLs. The engine persists the bytes before upload.
  images : Array[String]
  task : String
  // Optional client-minted lifecycle identity echoed with `agent.started`.
  // Blank ids and ids longer than 128 UTF-8 bytes are ignored.
  submission_id : String?
  model : String?
  // Optional keeps older clients compatible; a present value is decoded into
  // the closed protocol type before the command reaches the host operation.
  thinking : OpenSeekThinking?
  max_steps : Int32?
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
} derive(Debug, Eq)

///|
pub(all) struct SteerPayload {
  // Same inline image representation as StartPayload.
  images : Array[String]
  text : String
  run_id : String?
  // Optional client-minted lifecycle identity echoed on the steer receipt.
  submission_id : String?
} derive(Debug, Eq)

///|
/// One valid mutation of the live follow-up queue. Operation-specific fields
/// live on their operation, so the host never receives an action/text
/// combination it still has to interpret. The queue belongs to the Desktop
/// engine process and is never written to the session record.
pub(all) enum QueueAction {
  QueueAdd(id~ : String, text~ : String, images~ : Array[String])
  QueueEdit(id~ : String, text~ : String, images~ : Array[String])
  QueueWithdraw(id~ : String)
  QueueSteer(id~ : String)
} derive(Debug, Eq)

///|
pub(all) struct QueuePayload {
  action : QueueAction
  run_id : String
} derive(Debug, Eq)

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
} derive(Debug, Eq)

///|
pub(all) struct RunsPayload {
  known : Array[KnownRunPayload]?
} derive(Debug, Eq)

///|
pub(all) struct CompactPayload {
  // Compaction addresses a durable conversation rather than a live run.
  session : String
  // A resumed conversation may need a new engine process with these settings.
  model : String?
  thinking : OpenSeekThinking?
  max_steps : Int32?
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
  max_steps : Int32?
  workspace : String?
} derive(Debug, Eq)

///|
pub(all) struct LoadSessionPayload {
  session : String
  // The workspace holding the session, when the client already knows it.
  workspace : String?
} derive(Debug, Eq)

///|
/// Export one exact conversation from one registered workspace. Download and
/// Share use the same identity; the native process chooses the save destination
/// or the login's issuing server. Neither destination crosses this boundary.
pub(all) struct SessionExportPayload {
  session : String
  workspace : String
  title : String
  archived : Bool
} derive(Debug, Eq)

///|
/// Decode the exact store identity and display metadata needed by an export.
/// Every field is required and typed; unknown metadata fields are ignored.
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
} derive(Debug, Eq)

///|
/// Permanent deletion addresses one archived record in one exact store.
/// `workspace` is the host-reported project resource path; the host validates
/// it against its registry instead of trusting the client to choose an
/// arbitrary directory.
pub(all) struct ArchivedSessionPayload {
  session : String
  workspace : String
} derive(Debug, Eq)

///|
pub(all) struct SettingsSetPayload {
  provider : String?
  custom_api_url : String?
  deepseek_api_key : String?
  glm_api_key : String?
  custom_api_key : String?
  followup_behavior : String?
} derive(Debug, Eq)

///|
pub impl FromJson for SettingsSetPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "settings patch payload")
  {
    provider: object.optional_string("provider"),
    custom_api_url: object.optional_string("custom_api_url"),
    deepseek_api_key: object.optional_string("deepseek_api_key"),
    glm_api_key: object.optional_string("glm_api_key"),
    custom_api_key: object.optional_string("custom_api_key"),
    followup_behavior: object.optional_string("followup_behavior"),
  }
}

///|
pub impl ToJson for SettingsSetPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  if self.provider is Some(value) {
    fields["provider"] = Json(value)
  }
  if self.custom_api_url is Some(value) {
    fields["custom_api_url"] = Json(value)
  }
  if self.deepseek_api_key is Some(value) {
    fields["deepseek_api_key"] = Json(value)
  }
  if self.glm_api_key is Some(value) {
    fields["glm_api_key"] = Json(value)
  }
  if self.followup_behavior is Some(value) {
    fields["followup_behavior"] = Json(value)
  }
  if self.custom_api_key is Some(value) {
    fields["custom_api_key"] = Json(value)
  }
  Json(fields)
}

///|
pub(all) struct WorkspacePayload {
  path : String
} derive(Debug, Eq)

///|
/// `worktree.list` names the workspace whose registry to read.
pub(all) struct WorktreeListPayload {
  workspace : String
} derive(Debug, Eq)

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
  { workspace, session, codex_thread, }
}

///|
pub impl ToJson for WorktreeCreatePayload with fn to_json(self) {
  let fields : Map[String, Json] = { "workspace": Json(self.workspace) }
  if self.session is Some(session) {
    fields["session"] = Json(session)
  }
  if self.codex_thread is Some(codex_thread) {
    fields["codex_thread"] = Json(codex_thread)
  }
  Json(fields)
}

///|
/// `worktree.remove` — `force` discards uncommitted changes in the checkout;
/// the branch survives either way.
pub(all) struct WorktreeRemovePayload {
  workspace : String
  name : String
  force : Bool?
} derive(Debug, Eq)

///|
pub(all) struct InstallSkillPayload {
  module_name : String
  version : String
  package_path : String?
} derive(Debug, Eq)

///|
pub(all) struct UninstallSkillPayload {
  id : String
} derive(Debug, Eq)

///|
pub(all) struct OpenPathPayload {
  session : String
  cwd : String?
  path : String
} derive(Debug, Eq)

///|
/// `base_hint` is the branch the diffstat should measure from, when the client
/// already knows it from the branch's pull request. Absent on the first probe,
/// and whenever there is no pull request to ask — the host then falls back to
/// the remote's default branch.
pub(all) struct GitBranchPayload {
  session : String
  cwd : String?
  base_hint : String?
} derive(Debug, Eq)

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
  { session, cwd, branch_hint, }
}

///|
pub impl ToJson for GitPullRequestPayload with fn to_json(self) {
  let fields : Map[String, Json] = { "session": Json(self.session) }
  if self.cwd is Some(cwd) {
    fields["cwd"] = Json(cwd)
  }
  if self.branch_hint is Some(branch_hint) {
    fields["branch_hint"] = Json(branch_hint)
  }
  Json(fields)
}

///|
/// Address the Git working tree belonging to one conversation. The optional
/// workspace hint follows the filesystem operations' trust boundary: the host
/// accepts it only when it names a registered workspace and still routes a
/// worktree-bound conversation into its own checkout.
pub(all) struct GitChangesPayload {
  session : String
  workspace : String?
} derive(Debug, Eq)

///|
/// Read one immutable page of repository history. The first request omits
/// `snapshot`; the host captures the selected refs as full commit identities
/// and echoes them back. Later pages resend that snapshot so moving refs cannot
/// duplicate or skip commits mid-scroll.
pub(all) struct GitHistoryPayload {
  session : String
  workspace : String?
  snapshot : GitHistorySnapshot?
  skip : Int32
  limit : Int32
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
} derive(Debug, Eq)

///|
pub(all) struct ReadDirPayload {
  path : String
} derive(Debug, Eq)

///|
pub(all) struct SearchFilesPayload {
  path : String
  // One Quick Open cache session. The first request populates it; subsequent
  // queries reuse it until `fs.clear_file_search_cache` retires the key.
  cache_key : String
  query : String
  // Zero warms the cache without returning rows; interactive queries use the
  // picker limit. The Host applies its own hard upper bound.
  max_results : Int32
  // Monotonic within the page. It identifies one cancellable query, not a
  // cache generation.
  generation : Int32
} derive(Debug, Eq)

///|
pub(all) struct CancelSearchFilesPayload {
  cache_key : String
  generation : Int32
} derive(Debug, Eq)

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
  generation : Int32
  max_results : Int32
} derive(Debug, Eq)

///|
/// Cancel one text-search generation. The Host also remembers the cancelled
/// frontier so cancel-before-search message ordering remains safe.
pub(all) struct CancelSearchTextPayload {
  session_key : String
  generation : Int32
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
  generation : Int32
  max_results : Int32
} derive(Debug, Eq)

///|
/// Cancel one semantic-search generation. The Host also remembers the
/// cancelled frontier so cancel-before-search message ordering remains safe.
pub(all) struct CancelSearchSemanticPayload {
  session_key : String
  generation : Int32
} derive(Debug, Eq)

///|
/// Request one host-backed structural Pattern Repair. `instruction` remains
/// separate from the current pattern as the repair constraint; the desktop
/// one-click UI supplies its fixed syntax-only instruction rather than a
/// second user prompt.
pub(all) struct PatternRepairPayload {
  model : String
  thinking : OpenSeekThinking?
  root : String
  pattern : String
  instruction : String
  generation : Int32
} derive(Debug, Eq)

///|
pub extend PatternRepairPayload with Debug::{to_repr}

///|
pub extend PatternRepairPayload with Eq::{equal, not_equal}

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
  generation : Int32
  matches : Array[SemanticSearchHit]
  match_count : Int32
  file_count : Int32
} derive(Debug, Eq)

///|
pub(all) struct ClearFileSearchCachePayload {
  cache_key : String
} derive(Debug, Eq)

///|
pub(all) struct ReadFilePayload {
  // Without `root`, `path` is absolute. With `root`, `root` is absolute and
  // `path` is relative to it; the host validates that pair before opening.
  path : String
  root : String?
} derive(Debug, Eq)

///|
/// One immutable structural-search match captured for an agent context file.
/// Keeping the source in the artifact makes the selected snapshot useful even
/// when the working tree changes before the agent reads it.
pub(all) struct SemanticSelectionMatch {
  rule_id : String
  description : String?
  file : String
  start_line : Int32
  start_column : Int32
  end_line : Int32
  end_column : Int32
  matched_source : String
} derive(Debug, Eq)

///|
/// Materialize one large semantic-search selection below the supplied checkout.
/// The host owns the final path; callers can never choose an arbitrary file.
pub(all) struct MaterializeSemanticSelectionPayload {
  root : String
  artifact_id : String
  patterns : Array[String]
  include_glob : String
  exclude_glob : String
  matches : Array[SemanticSelectionMatch]
} derive(Debug, Eq)

///|
pub(all) struct StatFilesPayload {
  paths : Array[String]
} derive(Debug, Eq)

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
} derive(Debug, Eq)

///|
pub(all) struct BrowseDirectoryPayload {
  path : String?
} derive(Debug, Eq)

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
  { parent, name, }
}

///|
pub impl ToJson for CreateDirectoryPayload with fn to_json(self) {
  { "parent": self.parent, "name": self.name }
}

///|
pub(all) struct TerminalOpenPayload {
  session : String
  workspace : String?
  cols : Int32
  rows : Int32
  // One shell command line to run as the session's only process, in place of
  // the interactive login shell: a `!` command from the composer. The session
  // ends when the command does, and `terminal.exit` carries its exit code.
  command : String?
} derive(Debug, Eq)

///|
pub impl FromJson for TerminalOpenPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "terminal.open payload")
  {
    session: object.required_string("session"),
    workspace: object.optional_string("workspace"),
    cols: object.required_int("cols"),
    rows: object.required_int("rows"),
    command: object.optional_string("command"),
  }
}

///|
pub impl ToJson for TerminalOpenPayload with fn to_json(self) {
  let fields : Map[String, Json] = {
    "session": Json(self.session),
    "cols": Json(self.cols),
    "rows": Json(self.rows),
  }
  if self.workspace is Some(workspace) {
    fields["workspace"] = Json(workspace)
  }
  if self.command is Some(command) {
    fields["command"] = Json(command)
  }
  Json(fields)
}

///|
/// Terminal input is a wire union: text carries `data`, byte-oriented input
/// carries `data_base64`, and the inactive field is absent rather than null.
pub(all) struct TerminalInputPayload {
  id : String
  data : String?
  data_base64 : String?
} derive(Debug, Eq)

///|
pub impl FromJson for TerminalInputPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "terminal input payload")
  let data = object.optional_string("data")
  let data_base64 = object.optional_string("data_base64")
  match (data, data_base64) {
    (Some(_), None) | (None, Some(_)) => ()
    _ =>
      raise JsonDecodeError(
        (path, "exactly one of data and data_base64 must be present"),
      )
  }
  { id: object.required_string("id"), data, data_base64, }
}

///|
pub impl ToJson for TerminalInputPayload with fn to_json(self) {
  let fields : Map[String, Json] = { "id": Json(self.id) }
  if self.data is Some(data) {
    fields["data"] = Json(data)
  }
  if self.data_base64 is Some(data_base64) {
    fields["data_base64"] = Json(data_base64)
  }
  Json::object(fields)
}

///|
pub(all) struct TerminalResizePayload {
  id : String
  cols : Int32
  rows : Int32
} derive(Debug, Eq)

///|
pub impl FromJson for TerminalResizePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "terminal resize payload")
  {
    id: object.required_string("id"),
    cols: object.required_int("cols"),
    rows: object.required_int("rows"),
  }
}

///|
pub impl ToJson for TerminalResizePayload with fn to_json(self) {
  { "id": self.id, "cols": self.cols, "rows": self.rows }
}

///|
pub(all) struct TerminalAckPayload {
  id : String
  sequence : Int32
} derive(Debug, Eq)

///|
pub impl FromJson for TerminalAckPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "terminal ack payload")
  {
    id: object.required_string("id"),
    sequence: object.required_int("sequence"),
  }
}

///|
pub impl ToJson for TerminalAckPayload with fn to_json(self) {
  { "id": self.id, "sequence": self.sequence }
}

///|
pub(all) struct TerminalClosePayload {
  id : String
} derive(Debug, Eq)

///|
pub impl FromJson for TerminalClosePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "terminal close payload")
  { id: object.required_string("id"), }
}

///|
pub impl ToJson for TerminalClosePayload with fn to_json(self) {
  { "id": self.id }
}

///|
/// Request the package dependency graph for one concrete `moon.mod` shown by
/// the file editor. `root` is the owning conversation checkout and `path` is
/// relative to it; the Host revalidates both before invoking Moon.
pub(all) struct MoonPackageGraphPayload {
  session : String
  root : String
  path : String
} derive(Debug, Eq)

///|
pub impl FromJson for MoonPackageGraphPayload with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected Moon package-graph payload"))
  }
  let object = JsonObject::of(fields, path)
  {
    session: object.required_string("session"),
    root: object.required_string("root"),
    path: object.required_string("path"),
  }
}

///|
pub impl ToJson for MoonPackageGraphPayload with fn to_json(self) {
  { "session": self.session, "root": self.root, "path": self.path }
}

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
  { session, root, path: file_path, }
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
  line : Int32
  character : Int32
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
  { session, root, path: file_path, line, character, }
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
  { session, root, query, }
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
  line : Int32
  column : Int32
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
  { session, root, path: file_path, line, column, }
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
/// Request the reference CodeLens rows for one current checkout source file.
/// Unlike navigation, no cursor position is needed: Moon IDE scans the whole
/// authorized file and returns zero-based LSP ranges for every lens.
pub(all) struct MoonIdeCodeLensPayload {
  session : String
  root : String
  path : String
} derive(Debug, Eq)

///|
pub impl FromJson for MoonIdeCodeLensPayload with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected Moon IDE CodeLens payload"))
  }
  let object = JsonObject::of(fields, path)
  {
    session: object.required_string("session"),
    root: object.required_string("root"),
    path: object.required_string("path"),
  }
}

///|
pub impl ToJson for MoonIdeCodeLensPayload with fn to_json(self) {
  { "session": self.session, "root": self.root, "path": self.path }
}

///|
pub(all) struct ExternalLinkPayload {
  url : String
} derive(Debug, Eq)

///|
pub(all) struct BrowserOpenPayload {
  id : Int32
  url : String
  dark : Bool
} derive(Debug, Eq)

///|
pub impl ToJson for BrowserOpenPayload with fn to_json(self) {
  { "id": self.id, "url": self.url, "dark": self.dark }
}

///|
pub impl FromJson for BrowserOpenPayload with fn from_json(json, path) {
  guard json is { "id": id, "url": url, "dark": dark, .. } else {
    raise JsonDecodeError((path, "expected browser id, URL and theme"))
  }
  {
    id: @json.from_json(id, path=path.add_key("id")),
    url: @json.from_json(url, path=path.add_key("url")),
    dark: @json.from_json(dark, path=path.add_key("dark")),
  }
}

///|
pub(all) struct BrowserIdPayload {
  id : Int32
} derive(Debug, Eq)

///|
pub(all) struct BrowserThemePayload {
  id : Int32
  dark : Bool
} derive(Debug, Eq)

///|
pub(all) struct AppTitlebarThemePayload {
  dark : Bool
} derive(Debug, Eq)

///|
pub(all) struct BrowserBoundsPayload {
  id : Int32
  x : Int32
  y : Int32
  width : Int32
  height : Int32
} derive(Debug, Eq)

///|
pub(all) struct BrowserVisiblePayload {
  id : Int32
  visible : Bool
} derive(Debug, Eq)
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
  { stage: @json.from_json(stage, path=path.add_key("stage")), }
}

///|
pub(all) struct StartedPayload {
  run_id : String
  submission_id : String?
  engine : String?
  model : String?
  max_steps : Int32?
  session : String
  session_root : String?
} derive(Debug, Eq)

///|
pub(all) struct AgentEventPayload {
  run_id : String?
  // Engine events always belong to the durable session that owns the process;
  // only `run_id` may be absent for between-turn lifecycle events.
  session : String
  event : @wire.Event
} derive(Debug, Eq)

///|
/// Session and event are required. A missing or null run id means a
/// between-turn event; malformed fields are refused and unknown keys ignored.
pub impl FromJson for AgentEventPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "agent event payload")
  let session = object.required_string("session")
  let run_id = object.optional_string("run_id")
  guard @wire.parse(object.required_json("event")) is Some(event) else {
    raise JsonDecodeError((path.add_key("event"), "unknown engine event"))
  }
  { run_id, session, event, }
}

///|
pub impl ToJson for AgentEventPayload with fn to_json(self) {
  let fields : Map[String, Json] = {
    "session": Json(self.session),
    "event": self.event.to_json(),
  }
  if self.run_id is Some(run_id) {
    fields["run_id"] = Json(run_id)
  }
  Json(fields)
}

///|
/// A host failure report stays decodable even when one of its display fields
/// is absent or has the wrong JSON type. Errors are the one notification class
/// that must not disappear because the report describing them is malformed;
/// the frontend assigns the generic label for a missing or blank `message`.
pub(all) struct AgentErrorPayload {
  run_id : String?
  message : String?
  exit_code : Int32?
  diagnostics : String?
} derive(Debug, Eq)

///|
pub impl FromJson for AgentErrorPayload with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected agent error payload"))
  }
  {
    run_id: lenient_string(fields, "run_id"),
    message: lenient_string(fields, "message"),
    exit_code: lenient_int(fields, "exit_code"),
    diagnostics: lenient_string(fields, "diagnostics"),
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
  exit_code : Int32?
} derive(Debug, Eq)

///|
pub impl ToJson for FinishedPayload with fn to_json(self) {
  let fields = { "run_id": Json(self.run_id), "status": Json(self.status) }
  if self.answer is Some(answer) {
    fields["answer"] = Json(answer)
  }
  if self.exit_code is Some(exit_code) {
    fields["exit_code"] = Json(exit_code.to_double())
  }
  Json(fields)
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
    answer: lenient_string(fields, "answer"),
    exit_code: lenient_int(fields, "exit_code"),
  }
}

///|
pub(all) struct SessionCommitPayload {
  session : String
  sequence : Int32
  event : SessionEvent
  // The durable store root this commit was read from, as a frontend resource
  // path. Session ids are not globally unique across stores, so the
  // broadcast names the store half of the identity beside the id.
  session_root : String
} derive(Debug, Eq)

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
  steps : Int32
  activity : String
} derive(Debug, Eq)

///|
/// One resolved call of a workflow a snippet is running, read by the host from
/// the run's journal and broadcast as `workflow.entry`. Nothing downstream
/// persists it: the journal itself is the record, and a client that arrives
/// late rebuilds its view from the next entries it sees. `child` is the
/// subagent's own session id (`<parent>-sr-N`), the same string its transcript
/// is named by — a reader can open it directly. `phase`, `cost_usd` and the
/// timestamps are absent when the journal did not carry them.
pub(all) struct WorkflowEntryPayload {
  /// The run, as `workflow_started` named it (`wf-N`).
  workflow : String
  /// The parent session the run belongs to.
  session : String
  child : String
  kind : String
  label : String
  phase : String?
  /// The contract's snake_case terminal: `captured`, `no_report`,
  /// `max_steps`, `context_yield`, `timed_out`, `skipped`, `failed`.
  status : String
  steps : Int32
  prompt_tokens : Int32
  completion_tokens : Int32
  cost_usd : Double?
  /// Why `steps` and the token counts may fall short of what the child spent
  /// (it left no result, or its launch was cancelled); absent when they are
  /// the engine's own account. Unknown spend is not zero spend.
  unaccounted : String?
  /// Milliseconds since the epoch, as plain JSON numbers.
  started_at : Double?
  finished_at : Double?
} derive(Debug, Eq)

///|
/// One exact store-qualified session changed placement or display metadata.
/// Current change values are `archived`, `unarchived`, `deleted`, and
/// `renamed`; clients still treat unknown values as list invalidations.
pub(all) struct SessionChangedPayload {
  change : String
  session : String
  // The project store owning this record. Session ids are not globally
  // unique across stores, so every invalidation carries both halves of the
  // durable identity.
  workspace : String
} derive(Debug, Eq)

///|
pub(all) struct WorkspacesChangedPayload {
  workspaces : Array[String]
  chat_root : ChatWorkspaceRoot?
} derive(Debug, Eq)

///|
pub impl ToJson for WorkspacesChangedPayload with fn to_json(self) {
  let fields : Map[String, Json] = { "workspaces": Json(self.workspaces) }
  if self.chat_root is Some(root) {
    fields["chat_root"] = root.to_json()
  }
  Json(fields)
}

///|
pub impl FromJson for WorkspacesChangedPayload with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected a workspace snapshot"))
  }
  let object = JsonObject::of(fields, path)
  guard fields.get("workspaces") is Some(listed) else {
    raise JsonDecodeError(
      (path.add_key("workspaces"), "expected a workspace list"),
    )
  }
  {
    workspaces: @json.from_json(listed),
    chat_root: decode_chat_workspace_root(object),
  }
}

///|
/// One workspace's worktree list changed; sidebars re-join their name chips
/// and pickers refresh — the `workspace.changed` pattern, keyed by the
/// workspace the list belongs to.
pub(all) struct WorktreeChangedPayload {
  workspace : String
  worktrees : Array[WorktreeInfo]
} derive(Debug, Eq)

///|
/// `workspace.settings_get` names the workspace whose desktop-owned
/// settings file to read.
pub(all) struct WorkspaceSettingsGetPayload {
  workspace : String
} derive(Debug, Eq)

///|
/// `workspace.settings_set` patches one workspace's settings; absent fields
/// stay unchanged. The committed state comes back in the reply and in the
/// `workspace.settings_changed` broadcast.
pub(all) struct WorkspaceSettingsSetPayload {
  workspace : String
  worktree_mode : Bool?
  checkout_submodules : Bool?
  submodule_checkout_timeout_seconds : Int32?
} derive(Debug, Eq)

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
  submodule_checkout_timeout_seconds : Int32
} derive(Debug, Eq)

///|
pub(all) struct SettingsStatusPayload {
  revision : Int32
  provider : String
  custom_api_url : String?
  has_deepseek_key : Bool
  has_glm_key : Bool
  has_custom_key : Bool
  followup_behavior : String
} derive(Debug, Eq)

///|
pub impl FromJson for SettingsStatusPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "settings status payload")
  {
    revision: object.required_int("revision"),
    provider: object.required_string("provider"),
    custom_api_url: object.optional_string("custom_api_url"),
    has_deepseek_key: object.required_bool("has_deepseek_key"),
    has_glm_key: object.required_bool("has_glm_key"),
    has_custom_key: object.required_bool("has_custom_key"),
    followup_behavior: object.required_string("followup_behavior"),
  }
}

///|
pub impl ToJson for SettingsStatusPayload with fn to_json(self) {
  let fields : Map[String, Json] = {
    "revision": Json(self.revision),
    "provider": Json(self.provider),
    "has_deepseek_key": Json(self.has_deepseek_key),
    "has_glm_key": Json(self.has_glm_key),
    "has_custom_key": Json(self.has_custom_key),
    "followup_behavior": Json(self.followup_behavior),
  }
  if self.custom_api_url is Some(value) {
    fields["custom_api_url"] = Json(value)
  }
  Json(fields)
}

///|
/// Immutable identity of the installed desktop package. The native host reads
/// this from `proton-package.json`; it is not an editable engine setting.
pub(all) struct AppInfoReply {
  version : String
  // A development build's console entry URL, the loopback origin the host
  // serves its own frontend on for the system browser. Absent in a release.
  console_url : String?
} derive(Debug, Eq)

///|
/// `version` is required; `console_url` reads as absent when missing or
/// null. Unknown fields are ignored.
pub impl FromJson for AppInfoReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "app info reply")
  {
    version: object.required_string("version"),
    console_url: object.optional_string("console_url"),
  }
}

///|
/// A release build omits `console_url` rather than sending null.
pub impl ToJson for AppInfoReply with fn to_json(self) {
  let object : Map[String, Json] = { "version": Json(self.version) }
  if self.console_url is Some(url) {
    object["console_url"] = Json(url)
  }
  Json::object(object)
}

///|
pub(all) struct UpdateDownloadProgressPayload {
  downloaded_bytes : Int32
  total_bytes : Int32?
} derive(Debug, Eq)

///|
pub(all) struct UpdateDownloadedPayload {
  version : String
} derive(Debug, Eq)

///|
pub(all) struct UpdateDownloadFailedPayload {
  message : String
} derive(Debug, Eq)

///|
pub(all) struct AuthUserPayload {
  login : String
  avatar_url : String
} derive(Debug, Eq)

///|
pub(all) struct AuthDevicePayload {
  id : String
  name : String
  url : String
} derive(Debug, Eq)

///|
pub(all) struct AuthStatusPayload {
  connected : Bool
  server_url : String?
  managed_by_env : Bool?
  user : AuthUserPayload?
  device : AuthDevicePayload?
} derive(Debug, Eq)

///|
pub(all) struct DiagnosticsPayload {
  root : String
  path : String
  diagnostics : Array[LspDiagnostic]
} derive(Debug, Eq)

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
} derive(Debug, Eq)

///|
pub(all) struct FsWatchFailedPayload {
  root : String
  message : String
  // Identifies the concrete watcher that produced this failure.
  generation : String
} derive(Debug, Eq)

///|
pub(all) struct TerminalOutputPayload {
  id : String
  sequence : Int32
  data : String
} derive(Debug, Eq)

///|
pub impl FromJson for TerminalOutputPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "terminal output payload")
  {
    id: object.required_string("id"),
    sequence: object.required_int("sequence"),
    data: object.required_string("data"),
  }
}

///|
pub impl ToJson for TerminalOutputPayload with fn to_json(self) {
  { "id": self.id, "sequence": self.sequence, "data": self.data }
}

///|
pub(all) struct TerminalExitPayload {
  id : String
  code : Int32
} derive(Debug, Eq)

///|
pub impl FromJson for TerminalExitPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "terminal exit payload")
  { id: object.required_string("id"), code: object.required_int("code"), }
}

///|
pub impl ToJson for TerminalExitPayload with fn to_json(self) {
  { "id": self.id, "code": self.code }
}

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
pub extend MoonPackageGraphPayload with Debug::{to_repr}

///|
pub extend MoonPackageGraphPayload with FromJson::{from_json}

///|
pub extend MoonPackageGraphPayload with Eq::{equal, not_equal}

///|
pub extend MoonPackageGraphPayload with ToJson::{to_json}

///|
pub extend MoonIdeCodeLensPayload with Debug::{to_repr}

///|
pub extend MoonIdeCodeLensPayload with FromJson::{from_json}

///|
pub extend MoonIdeCodeLensPayload with Eq::{equal, not_equal}

///|
pub extend MoonIdeCodeLensPayload with ToJson::{to_json}

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
pub extend SemanticSelectionMatch with Debug::{to_repr}

///|
pub extend SemanticSelectionMatch with Eq::{equal, not_equal}

///|
pub extend SemanticSelectionMatch with FromJson::{from_json}

///|
pub extend SemanticSelectionMatch with ToJson::{to_json}

///|
pub extend MaterializeSemanticSelectionPayload with Debug::{to_repr}

///|
pub extend MaterializeSemanticSelectionPayload with Eq::{equal, not_equal}

///|
pub extend MaterializeSemanticSelectionPayload with FromJson::{from_json}

///|
pub extend MaterializeSemanticSelectionPayload with ToJson::{to_json}

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
pub extend QueuePayload with Debug::{to_repr}

///|
pub extend QueuePayload with FromJson::{from_json}

///|
pub extend QueuePayload with Eq::{equal, not_equal}

///|
pub extend QueuePayload with ToJson::{to_json}

///|
pub extend QueueAction with Debug::{to_repr}

///|
pub extend QueueAction with Eq::{equal, not_equal}

///|
pub extend SubrunProgressPayload with Debug::{to_repr}

///|
pub extend SubrunProgressPayload with FromJson::{from_json}

///|
pub extend SubrunProgressPayload with Eq::{equal, not_equal}

///|
pub extend SubrunProgressPayload with ToJson::{to_json}

///|
pub extend WorkflowEntryPayload with Debug::{to_repr}

///|
pub extend WorkflowEntryPayload with FromJson::{from_json}

///|
pub extend WorkflowEntryPayload with Eq::{equal, not_equal}

///|
pub extend WorkflowEntryPayload with ToJson::{to_json}

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

///|
#deprecated("Use `Debug::to_repr` via the trait or `Repr(value)` instead", skip_current_package=true)
#doc(hidden)
pub extend AppTitlebarThemePayload with Debug::{to_repr}

///|
#deprecated("Use `FromJson::from_json` via the trait instead", skip_current_package=true)
#doc(hidden)
pub extend AppTitlebarThemePayload with FromJson::{from_json}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend AppTitlebarThemePayload with Eq::{equal, not_equal}

///|
#deprecated("Use `ToJson::to_json` via the trait instead", skip_current_package=true)
#doc(hidden)
pub extend AppTitlebarThemePayload with ToJson::{to_json}

///|
pub extend BrowserThemePayload with Debug::{to_repr}

///|
pub extend BrowserThemePayload with FromJson::{from_json}

///|
pub extend BrowserThemePayload with Eq::{equal, not_equal}

///|
pub extend BrowserThemePayload with ToJson::{to_json}

///|
pub extend CancelSearchSemanticPayload with Debug::{to_repr}

///|
pub extend CancelSearchSemanticPayload with FromJson::{from_json}

///|
pub extend CancelSearchSemanticPayload with Eq::{equal, not_equal}

///|
pub extend CancelSearchSemanticPayload with ToJson::{to_json}

///|
pub extend CreateDirectoryPayload with Debug::{to_repr}

///|
pub extend CreateDirectoryPayload with FromJson::{from_json}

///|
pub extend CreateDirectoryPayload with Eq::{equal, not_equal}

///|
pub extend CreateDirectoryPayload with ToJson::{to_json}

///|
pub extend SearchSemanticPayload with Debug::{to_repr}

///|
pub extend SearchSemanticPayload with FromJson::{from_json}

///|
pub extend SearchSemanticPayload with Eq::{equal, not_equal}

///|
pub extend SearchSemanticPayload with ToJson::{to_json}

///|
#deprecated("Use `Debug::to_repr` via the trait or `Repr(value)` instead", skip_current_package=true)
#doc(hidden)
pub extend SemanticSearchProgressPayload with Debug::{to_repr}

///|
#deprecated("Use `FromJson::from_json` via the trait instead", skip_current_package=true)
#doc(hidden)
pub extend SemanticSearchProgressPayload with FromJson::{from_json}

///|
#deprecated("Use `==` or the `Eq` trait directly", skip_current_package=true)
#doc(hidden)
pub extend SemanticSearchProgressPayload with Eq::{equal, not_equal}

///|
#deprecated("Use `ToJson::to_json` via the trait instead", skip_current_package=true)
#doc(hidden)
pub extend SemanticSearchProgressPayload with ToJson::{to_json}

///|
pub impl FromJson for CancelPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "CancelPayload")
  {
    run_id: match object.optional_json("run_id") {
      None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("run_id")))
    },
  }
}

///|
pub impl ToJson for CancelPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  if self.run_id is Some(value) {
    fields["run_id"] = Json(value)
  }
  Json(fields)
}

///|
pub impl FromJson for KnownRunPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "KnownRunPayload")
  {
    session: @json.from_json(
      object.required_json("session"),
      path=path.add_key("session"),
    ),
    run_id: match object.optional_json("run_id") {
      None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("run_id")))
    },
    submission_id: match object.optional_json("submission_id") {
      None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("submission_id")))
    },
  }
}

///|
pub impl ToJson for KnownRunPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["session"] = Json(self.session)
  if self.run_id is Some(value) {
    fields["run_id"] = Json(value)
  }
  if self.submission_id is Some(value) {
    fields["submission_id"] = Json(value)
  }
  Json(fields)
}

///|
pub impl FromJson for RunsPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "RunsPayload")
  {
    known: match object.optional_json("known") {
      None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("known")))
    },
  }
}

///|
pub impl ToJson for RunsPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  if self.known is Some(value) {
    fields["known"] = Json(value)
  }
  Json(fields)
}

///|
pub impl FromJson for LoadSessionPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "LoadSessionPayload")
  {
    session: @json.from_json(
      object.required_json("session"),
      path=path.add_key("session"),
    ),
    workspace: match object.optional_json("workspace") {
      None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("workspace")))
    },
  }
}

///|
pub impl ToJson for LoadSessionPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["session"] = Json(self.session)
  if self.workspace is Some(value) {
    fields["workspace"] = Json(value)
  }
  Json(fields)
}

///|
pub impl FromJson for SessionPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SessionPayload")
  {
    session: @json.from_json(
      object.required_json("session"),
      path=path.add_key("session"),
    ),
    force: match object.optional_json("force") {
      None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("force")))
    },
  }
}

///|
pub impl ToJson for SessionPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["session"] = Json(self.session)
  if self.force is Some(value) {
    fields["force"] = Json(value)
  }
  Json(fields)
}

///|
pub impl FromJson for ArchivedSessionPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "ArchivedSessionPayload")
  {
    session: @json.from_json(
      object.required_json("session"),
      path=path.add_key("session"),
    ),
    workspace: @json.from_json(
      object.required_json("workspace"),
      path=path.add_key("workspace"),
    ),
  }
}

///|
pub impl ToJson for ArchivedSessionPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["session"] = Json(self.session)
  fields["workspace"] = Json(self.workspace)
  Json(fields)
}

///|
pub impl FromJson for WorkspacePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "WorkspacePayload")
  {
    path: @json.from_json(
      object.required_json("path"),
      path=path.add_key("path"),
    ),
  }
}

///|
pub impl ToJson for WorkspacePayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["path"] = Json(self.path)
  Json(fields)
}

///|
pub impl FromJson for WorktreeListPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "WorktreeListPayload")
  {
    workspace: @json.from_json(
      object.required_json("workspace"),
      path=path.add_key("workspace"),
    ),
  }
}

///|
pub impl ToJson for WorktreeListPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["workspace"] = Json(self.workspace)
  Json(fields)
}

///|
pub impl FromJson for WorktreeRemovePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "WorktreeRemovePayload")
  {
    workspace: @json.from_json(
      object.required_json("workspace"),
      path=path.add_key("workspace"),
    ),
    name: @json.from_json(
      object.required_json("name"),
      path=path.add_key("name"),
    ),
    force: match object.optional_json("force") {
      None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("force")))
    },
  }
}

///|
pub impl ToJson for WorktreeRemovePayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["workspace"] = Json(self.workspace)
  fields["name"] = Json(self.name)
  if self.force is Some(value) {
    fields["force"] = Json(value)
  }
  Json(fields)
}

///|
pub impl FromJson for InstallSkillPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "InstallSkillPayload")
  {
    module_name: @json.from_json(
      object.required_json("module_name"),
      path=path.add_key("module_name"),
    ),
    version: @json.from_json(
      object.required_json("version"),
      path=path.add_key("version"),
    ),
    package_path: match object.optional_json("package_path") {
      None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("package_path")))
    },
  }
}

///|
pub impl ToJson for InstallSkillPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["module_name"] = Json(self.module_name)
  fields["version"] = Json(self.version)
  if self.package_path is Some(value) {
    fields["package_path"] = Json(value)
  }
  Json(fields)
}

///|
pub impl FromJson for UninstallSkillPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "UninstallSkillPayload")
  { id: @json.from_json(object.required_json("id"), path=path.add_key("id")), }
}

///|
pub impl ToJson for UninstallSkillPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["id"] = Json(self.id)
  Json(fields)
}

///|
pub impl FromJson for OpenPathPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "OpenPathPayload")
  {
    session: @json.from_json(
      object.required_json("session"),
      path=path.add_key("session"),
    ),
    cwd: match object.optional_json("cwd") {
      None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("cwd")))
    },
    path: @json.from_json(
      object.required_json("path"),
      path=path.add_key("path"),
    ),
  }
}

///|
pub impl ToJson for OpenPathPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["session"] = Json(self.session)
  if self.cwd is Some(value) {
    fields["cwd"] = Json(value)
  }
  fields["path"] = Json(self.path)
  Json(fields)
}

///|
pub impl FromJson for GitBranchPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitBranchPayload")
  {
    session: @json.from_json(
      object.required_json("session"),
      path=path.add_key("session"),
    ),
    cwd: match object.optional_json("cwd") {
      None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("cwd")))
    },
    base_hint: match object.optional_json("base_hint") {
      None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("base_hint")))
    },
  }
}

///|
pub impl ToJson for GitBranchPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["session"] = Json(self.session)
  if self.cwd is Some(value) {
    fields["cwd"] = Json(value)
  }
  if self.base_hint is Some(value) {
    fields["base_hint"] = Json(value)
  }
  Json(fields)
}

///|
pub impl FromJson for GitChangesPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitChangesPayload")
  {
    session: @json.from_json(
      object.required_json("session"),
      path=path.add_key("session"),
    ),
    workspace: match object.optional_json("workspace") {
      None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("workspace")))
    },
  }
}

///|
pub impl ToJson for GitChangesPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["session"] = Json(self.session)
  if self.workspace is Some(value) {
    fields["workspace"] = Json(value)
  }
  Json(fields)
}

///|
pub impl FromJson for GitOriginalFilePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitOriginalFilePayload")
  {
    session: @json.from_json(
      object.required_json("session"),
      path=path.add_key("session"),
    ),
    workspace: match object.optional_json("workspace") {
      None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("workspace")))
    },
    path: @json.from_json(
      object.required_json("path"),
      path=path.add_key("path"),
    ),
    revision: match object.optional_json("revision") {
      None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("revision")))
    },
  }
}

///|
pub impl ToJson for GitOriginalFilePayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["session"] = Json(self.session)
  if self.workspace is Some(value) {
    fields["workspace"] = Json(value)
  }
  fields["path"] = Json(self.path)
  if self.revision is Some(value) {
    fields["revision"] = Json(value)
  }
  Json(fields)
}

///|
pub impl FromJson for ReadDirPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "ReadDirPayload")
  {
    path: @json.from_json(
      object.required_json("path"),
      path=path.add_key("path"),
    ),
  }
}

///|
pub impl ToJson for ReadDirPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["path"] = Json(self.path)
  Json(fields)
}

///|
pub impl FromJson for SearchFilesPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SearchFilesPayload")
  {
    path: @json.from_json(
      object.required_json("path"),
      path=path.add_key("path"),
    ),
    cache_key: @json.from_json(
      object.required_json("cache_key"),
      path=path.add_key("cache_key"),
    ),
    query: @json.from_json(
      object.required_json("query"),
      path=path.add_key("query"),
    ),
    max_results: @json.from_json(
      object.required_json("max_results"),
      path=path.add_key("max_results"),
    ),
    generation: @json.from_json(
      object.required_json("generation"),
      path=path.add_key("generation"),
    ),
  }
}

///|
pub impl ToJson for SearchFilesPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["path"] = Json(self.path)
  fields["cache_key"] = Json(self.cache_key)
  fields["query"] = Json(self.query)
  fields["max_results"] = Json(self.max_results)
  fields["generation"] = Json(self.generation)
  Json(fields)
}

///|
pub impl FromJson for CancelSearchFilesPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "CancelSearchFilesPayload")
  {
    cache_key: @json.from_json(
      object.required_json("cache_key"),
      path=path.add_key("cache_key"),
    ),
    generation: @json.from_json(
      object.required_json("generation"),
      path=path.add_key("generation"),
    ),
  }
}

///|
pub impl ToJson for CancelSearchFilesPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["cache_key"] = Json(self.cache_key)
  fields["generation"] = Json(self.generation)
  Json(fields)
}

///|
pub impl FromJson for ClearFileSearchCachePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "ClearFileSearchCachePayload")
  {
    cache_key: @json.from_json(
      object.required_json("cache_key"),
      path=path.add_key("cache_key"),
    ),
  }
}

///|
pub impl ToJson for ClearFileSearchCachePayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["cache_key"] = Json(self.cache_key)
  Json(fields)
}

///|
pub impl FromJson for ReadFilePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "ReadFilePayload")
  {
    path: @json.from_json(
      object.required_json("path"),
      path=path.add_key("path"),
    ),
    root: match object.optional_json("root") {
      None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("root")))
    },
  }
}

///|
pub impl ToJson for ReadFilePayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["path"] = Json(self.path)
  if self.root is Some(value) {
    fields["root"] = Json(value)
  }
  Json(fields)
}

///|
pub impl FromJson for SemanticSelectionMatch with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SemanticSelectionMatch")
  {
    rule_id: @json.from_json(
      object.required_json("rule_id"),
      path=path.add_key("rule_id"),
    ),
    description: match object.optional_json("description") {
      None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("description")))
    },
    file: @json.from_json(
      object.required_json("file"),
      path=path.add_key("file"),
    ),
    start_line: @json.from_json(
      object.required_json("start_line"),
      path=path.add_key("start_line"),
    ),
    start_column: @json.from_json(
      object.required_json("start_column"),
      path=path.add_key("start_column"),
    ),
    end_line: @json.from_json(
      object.required_json("end_line"),
      path=path.add_key("end_line"),
    ),
    end_column: @json.from_json(
      object.required_json("end_column"),
      path=path.add_key("end_column"),
    ),
    matched_source: @json.from_json(
      object.required_json("matched_source"),
      path=path.add_key("matched_source"),
    ),
  }
}

///|
pub impl ToJson for SemanticSelectionMatch with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["rule_id"] = Json(self.rule_id)
  if self.description is Some(value) {
    fields["description"] = Json(value)
  }
  fields["file"] = Json(self.file)
  fields["start_line"] = Json(self.start_line)
  fields["start_column"] = Json(self.start_column)
  fields["end_line"] = Json(self.end_line)
  fields["end_column"] = Json(self.end_column)
  fields["matched_source"] = Json(self.matched_source)
  Json(fields)
}

///|
pub impl FromJson for MaterializeSemanticSelectionPayload with fn from_json(
  json,
  path,
) {
  let object = JsonObject::decode(
    json, path, "MaterializeSemanticSelectionPayload",
  )
  {
    root: @json.from_json(
      object.required_json("root"),
      path=path.add_key("root"),
    ),
    artifact_id: @json.from_json(
      object.required_json("artifact_id"),
      path=path.add_key("artifact_id"),
    ),
    patterns: @json.from_json(
      object.required_json("patterns"),
      path=path.add_key("patterns"),
    ),
    include_glob: @json.from_json(
      object.required_json("include_glob"),
      path=path.add_key("include_glob"),
    ),
    exclude_glob: @json.from_json(
      object.required_json("exclude_glob"),
      path=path.add_key("exclude_glob"),
    ),
    matches: @json.from_json(
      object.required_json("matches"),
      path=path.add_key("matches"),
    ),
  }
}

///|
pub impl ToJson for MaterializeSemanticSelectionPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["root"] = Json(self.root)
  fields["artifact_id"] = Json(self.artifact_id)
  fields["patterns"] = Json(self.patterns)
  fields["include_glob"] = Json(self.include_glob)
  fields["exclude_glob"] = Json(self.exclude_glob)
  fields["matches"] = Json(self.matches)
  Json(fields)
}

///|
pub impl FromJson for StatFilesPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "StatFilesPayload")
  {
    paths: @json.from_json(
      object.required_json("paths"),
      path=path.add_key("paths"),
    ),
  }
}

///|
pub impl ToJson for StatFilesPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["paths"] = Json(self.paths)
  Json(fields)
}

///|
pub impl FromJson for WatchWorkspacePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "WatchWorkspacePayload")
  {
    path: @json.from_json(
      object.required_json("path"),
      path=path.add_key("path"),
    ),
    files: @json.from_json(
      object.required_json("files"),
      path=path.add_key("files"),
    ),
    directories: @json.from_json(
      object.required_json("directories"),
      path=path.add_key("directories"),
    ),
    recursive: match object.optional_json("recursive") {
      None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("recursive")))
    },
    generation: @json.from_json(
      object.required_json("generation"),
      path=path.add_key("generation"),
    ),
  }
}

///|
pub impl ToJson for WatchWorkspacePayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["path"] = Json(self.path)
  fields["files"] = Json(self.files)
  fields["directories"] = Json(self.directories)
  if self.recursive is Some(value) {
    fields["recursive"] = Json(value)
  }
  fields["generation"] = Json(self.generation)
  Json(fields)
}

///|
pub impl FromJson for BrowseDirectoryPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "BrowseDirectoryPayload")
  {
    path: match object.optional_json("path") {
      None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("path")))
    },
  }
}

///|
pub impl ToJson for BrowseDirectoryPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  if self.path is Some(value) {
    fields["path"] = Json(value)
  }
  Json(fields)
}

///|
pub impl FromJson for ExternalLinkPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "ExternalLinkPayload")
  {
    url: @json.from_json(object.required_json("url"), path=path.add_key("url")),
  }
}

///|
pub impl ToJson for ExternalLinkPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["url"] = Json(self.url)
  Json(fields)
}

///|
pub impl FromJson for BrowserIdPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "BrowserIdPayload")
  { id: @json.from_json(object.required_json("id"), path=path.add_key("id")), }
}

///|
pub impl ToJson for BrowserIdPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["id"] = Json(self.id)
  Json(fields)
}

///|
pub impl FromJson for BrowserThemePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "BrowserThemePayload")
  {
    id: @json.from_json(object.required_json("id"), path=path.add_key("id")),
    dark: @json.from_json(
      object.required_json("dark"),
      path=path.add_key("dark"),
    ),
  }
}

///|
pub impl ToJson for BrowserThemePayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["id"] = Json(self.id)
  fields["dark"] = Json(self.dark)
  Json(fields)
}

///|
pub impl FromJson for AppTitlebarThemePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "AppTitlebarThemePayload")
  {
    dark: @json.from_json(
      object.required_json("dark"),
      path=path.add_key("dark"),
    ),
  }
}

///|
pub impl ToJson for AppTitlebarThemePayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["dark"] = Json(self.dark)
  Json(fields)
}

///|
pub impl FromJson for BrowserBoundsPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "BrowserBoundsPayload")
  {
    id: @json.from_json(object.required_json("id"), path=path.add_key("id")),
    x: @json.from_json(object.required_json("x"), path=path.add_key("x")),
    y: @json.from_json(object.required_json("y"), path=path.add_key("y")),
    width: @json.from_json(
      object.required_json("width"),
      path=path.add_key("width"),
    ),
    height: @json.from_json(
      object.required_json("height"),
      path=path.add_key("height"),
    ),
  }
}

///|
pub impl ToJson for BrowserBoundsPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["id"] = Json(self.id)
  fields["x"] = Json(self.x)
  fields["y"] = Json(self.y)
  fields["width"] = Json(self.width)
  fields["height"] = Json(self.height)
  Json(fields)
}

///|
pub impl FromJson for BrowserVisiblePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "BrowserVisiblePayload")
  {
    id: @json.from_json(object.required_json("id"), path=path.add_key("id")),
    visible: @json.from_json(
      object.required_json("visible"),
      path=path.add_key("visible"),
    ),
  }
}

///|
pub impl ToJson for BrowserVisiblePayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["id"] = Json(self.id)
  fields["visible"] = Json(self.visible)
  Json(fields)
}

///|
pub impl FromJson for StartedPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "StartedPayload")
  {
    run_id: @json.from_json(
      object.required_json("run_id"),
      path=path.add_key("run_id"),
    ),
    submission_id: match object.optional_json("submission_id") {
      None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("submission_id")))
    },
    engine: match object.optional_json("engine") {
      None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("engine")))
    },
    model: match object.optional_json("model") {
      None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("model")))
    },
    max_steps: match object.optional_json("max_steps") {
      None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("max_steps")))
    },
    session: @json.from_json(
      object.required_json("session"),
      path=path.add_key("session"),
    ),
    session_root: match object.optional_json("session_root") {
      None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("session_root")))
    },
  }
}

///|
pub impl ToJson for StartedPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["run_id"] = Json(self.run_id)
  if self.submission_id is Some(value) {
    fields["submission_id"] = Json(value)
  }
  if self.engine is Some(value) {
    fields["engine"] = Json(value)
  }
  if self.model is Some(value) {
    fields["model"] = Json(value)
  }
  if self.max_steps is Some(value) {
    fields["max_steps"] = Json(value)
  }
  fields["session"] = Json(self.session)
  if self.session_root is Some(value) {
    fields["session_root"] = Json(value)
  }
  Json(fields)
}

///|
pub impl ToJson for AgentErrorPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  if self.run_id is Some(value) {
    fields["run_id"] = Json(value)
  }
  if self.message is Some(value) {
    fields["message"] = Json(value)
  }
  if self.exit_code is Some(value) {
    fields["exit_code"] = Json(value)
  }
  if self.diagnostics is Some(value) {
    fields["diagnostics"] = Json(value)
  }
  Json(fields)
}

///|
pub impl FromJson for SessionCommitPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SessionCommitPayload")
  {
    session: @json.from_json(
      object.required_json("session"),
      path=path.add_key("session"),
    ),
    sequence: @json.from_json(
      object.required_json("sequence"),
      path=path.add_key("sequence"),
    ),
    event: @json.from_json(
      object.required_json("event"),
      path=path.add_key("event"),
    ),
    session_root: @json.from_json(
      object.required_json("session_root"),
      path=path.add_key("session_root"),
    ),
  }
}

///|
pub impl ToJson for SessionCommitPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["session"] = Json(self.session)
  fields["sequence"] = Json(self.sequence)
  fields["event"] = self.event.to_json()
  fields["session_root"] = Json(self.session_root)
  Json(fields)
}

///|
pub impl FromJson for SubrunProgressPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SubrunProgressPayload")
  {
    id: @json.from_json(object.required_json("id"), path=path.add_key("id")),
    session: @json.from_json(
      object.required_json("session"),
      path=path.add_key("session"),
    ),
    steps: @json.from_json(
      object.required_json("steps"),
      path=path.add_key("steps"),
    ),
    activity: @json.from_json(
      object.required_json("activity"),
      path=path.add_key("activity"),
    ),
  }
}

///|
pub impl ToJson for SubrunProgressPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["id"] = Json(self.id)
  fields["session"] = Json(self.session)
  fields["steps"] = Json(self.steps)
  fields["activity"] = Json(self.activity)
  Json(fields)
}

///|
pub impl FromJson for WorkflowEntryPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "WorkflowEntryPayload")
  {
    workflow: @json.from_json(
      object.required_json("workflow"),
      path=path.add_key("workflow"),
    ),
    session: @json.from_json(
      object.required_json("session"),
      path=path.add_key("session"),
    ),
    child: @json.from_json(
      object.required_json("child"),
      path=path.add_key("child"),
    ),
    kind: @json.from_json(
      object.required_json("kind"),
      path=path.add_key("kind"),
    ),
    label: @json.from_json(
      object.required_json("label"),
      path=path.add_key("label"),
    ),
    phase: match object.optional_json("phase") {
      None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("phase")))
    },
    status: @json.from_json(
      object.required_json("status"),
      path=path.add_key("status"),
    ),
    steps: @json.from_json(
      object.required_json("steps"),
      path=path.add_key("steps"),
    ),
    prompt_tokens: @json.from_json(
      object.required_json("prompt_tokens"),
      path=path.add_key("prompt_tokens"),
    ),
    completion_tokens: @json.from_json(
      object.required_json("completion_tokens"),
      path=path.add_key("completion_tokens"),
    ),
    cost_usd: match object.optional_json("cost_usd") {
      None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("cost_usd")))
    },
    unaccounted: match object.optional_json("unaccounted") {
      None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("unaccounted")))
    },
    started_at: match object.optional_json("started_at") {
      None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("started_at")))
    },
    finished_at: match object.optional_json("finished_at") {
      None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("finished_at")))
    },
  }
}

///|
pub impl ToJson for WorkflowEntryPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["workflow"] = Json(self.workflow)
  fields["session"] = Json(self.session)
  fields["child"] = Json(self.child)
  fields["kind"] = Json(self.kind)
  fields["label"] = Json(self.label)
  if self.phase is Some(value) {
    fields["phase"] = Json(value)
  }
  fields["status"] = Json(self.status)
  fields["steps"] = Json(self.steps)
  fields["prompt_tokens"] = Json(self.prompt_tokens)
  fields["completion_tokens"] = Json(self.completion_tokens)
  if self.cost_usd is Some(value) {
    fields["cost_usd"] = Json(value)
  }
  if self.unaccounted is Some(value) {
    fields["unaccounted"] = Json(value)
  }
  if self.started_at is Some(value) {
    fields["started_at"] = Json(value)
  }
  if self.finished_at is Some(value) {
    fields["finished_at"] = Json(value)
  }
  Json(fields)
}

///|
pub impl FromJson for SessionChangedPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "SessionChangedPayload")
  {
    change: @json.from_json(
      object.required_json("change"),
      path=path.add_key("change"),
    ),
    session: @json.from_json(
      object.required_json("session"),
      path=path.add_key("session"),
    ),
    workspace: @json.from_json(
      object.required_json("workspace"),
      path=path.add_key("workspace"),
    ),
  }
}

///|
pub impl ToJson for SessionChangedPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["change"] = Json(self.change)
  fields["session"] = Json(self.session)
  fields["workspace"] = Json(self.workspace)
  Json(fields)
}

///|
pub impl FromJson for WorktreeChangedPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "WorktreeChangedPayload")
  {
    workspace: @json.from_json(
      object.required_json("workspace"),
      path=path.add_key("workspace"),
    ),
    worktrees: @json.from_json(
      object.required_json("worktrees"),
      path=path.add_key("worktrees"),
    ),
  }
}

///|
pub impl ToJson for WorktreeChangedPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["workspace"] = Json(self.workspace)
  fields["worktrees"] = Json(self.worktrees)
  Json(fields)
}

///|
pub impl FromJson for WorkspaceSettingsGetPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "WorkspaceSettingsGetPayload")
  {
    workspace: @json.from_json(
      object.required_json("workspace"),
      path=path.add_key("workspace"),
    ),
  }
}

///|
pub impl ToJson for WorkspaceSettingsGetPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["workspace"] = Json(self.workspace)
  Json(fields)
}

///|
pub impl FromJson for WorkspaceSettingsSetPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "WorkspaceSettingsSetPayload")
  {
    workspace: @json.from_json(
      object.required_json("workspace"),
      path=path.add_key("workspace"),
    ),
    worktree_mode: match object.optional_json("worktree_mode") {
      None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("worktree_mode")))
    },
    checkout_submodules: match object.optional_json("checkout_submodules") {
      None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("checkout_submodules")))
    },
    submodule_checkout_timeout_seconds: match
      object.optional_json("submodule_checkout_timeout_seconds") {
      None => None
      Some(value) =>
        Some(
          @json.from_json(
            value,
            path=path.add_key("submodule_checkout_timeout_seconds"),
          ),
        )
    },
  }
}

///|
pub impl ToJson for WorkspaceSettingsSetPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["workspace"] = Json(self.workspace)
  if self.worktree_mode is Some(value) {
    fields["worktree_mode"] = Json(value)
  }
  if self.checkout_submodules is Some(value) {
    fields["checkout_submodules"] = Json(value)
  }
  if self.submodule_checkout_timeout_seconds is Some(value) {
    fields["submodule_checkout_timeout_seconds"] = Json(value)
  }
  Json(fields)
}

///|
pub impl FromJson for WorkspaceSettingsPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "WorkspaceSettingsPayload")
  {
    workspace: @json.from_json(
      object.required_json("workspace"),
      path=path.add_key("workspace"),
    ),
    worktree_mode: @json.from_json(
      object.required_json("worktree_mode"),
      path=path.add_key("worktree_mode"),
    ),
    checkout_submodules: @json.from_json(
      object.required_json("checkout_submodules"),
      path=path.add_key("checkout_submodules"),
    ),
    submodule_checkout_timeout_seconds: @json.from_json(
      object.required_json("submodule_checkout_timeout_seconds"),
      path=path.add_key("submodule_checkout_timeout_seconds"),
    ),
  }
}

///|
pub impl ToJson for WorkspaceSettingsPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["workspace"] = Json(self.workspace)
  fields["worktree_mode"] = Json(self.worktree_mode)
  fields["checkout_submodules"] = Json(self.checkout_submodules)
  fields["submodule_checkout_timeout_seconds"] = Json(
    self.submodule_checkout_timeout_seconds,
  )
  Json(fields)
}

///|
pub impl FromJson for UpdateDownloadProgressPayload with fn from_json(
  json,
  path,
) {
  let object = JsonObject::decode(json, path, "UpdateDownloadProgressPayload")
  {
    downloaded_bytes: @json.from_json(
      object.required_json("downloaded_bytes"),
      path=path.add_key("downloaded_bytes"),
    ),
    total_bytes: match object.optional_json("total_bytes") {
      None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("total_bytes")))
    },
  }
}

///|
pub impl ToJson for UpdateDownloadProgressPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["downloaded_bytes"] = Json(self.downloaded_bytes)
  if self.total_bytes is Some(value) {
    fields["total_bytes"] = Json(value)
  }
  Json(fields)
}

///|
pub impl FromJson for UpdateDownloadedPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "UpdateDownloadedPayload")
  {
    version: @json.from_json(
      object.required_json("version"),
      path=path.add_key("version"),
    ),
  }
}

///|
pub impl ToJson for UpdateDownloadedPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["version"] = Json(self.version)
  Json(fields)
}

///|
pub impl FromJson for UpdateDownloadFailedPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "UpdateDownloadFailedPayload")
  {
    message: @json.from_json(
      object.required_json("message"),
      path=path.add_key("message"),
    ),
  }
}

///|
pub impl ToJson for UpdateDownloadFailedPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["message"] = Json(self.message)
  Json(fields)
}

///|
pub impl FromJson for AuthUserPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "AuthUserPayload")
  {
    login: @json.from_json(
      object.required_json("login"),
      path=path.add_key("login"),
    ),
    avatar_url: @json.from_json(
      object.required_json("avatar_url"),
      path=path.add_key("avatar_url"),
    ),
  }
}

///|
pub impl ToJson for AuthUserPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["login"] = Json(self.login)
  fields["avatar_url"] = Json(self.avatar_url)
  Json(fields)
}

///|
pub impl FromJson for AuthDevicePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "AuthDevicePayload")
  {
    id: @json.from_json(object.required_json("id"), path=path.add_key("id")),
    name: @json.from_json(
      object.required_json("name"),
      path=path.add_key("name"),
    ),
    url: @json.from_json(object.required_json("url"), path=path.add_key("url")),
  }
}

///|
pub impl ToJson for AuthDevicePayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["id"] = Json(self.id)
  fields["name"] = Json(self.name)
  fields["url"] = Json(self.url)
  Json(fields)
}

///|
pub impl FromJson for AuthStatusPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "AuthStatusPayload")
  {
    connected: @json.from_json(
      object.required_json("connected"),
      path=path.add_key("connected"),
    ),
    server_url: match object.optional_json("server_url") {
      None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("server_url")))
    },
    managed_by_env: match object.optional_json("managed_by_env") {
      None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("managed_by_env")))
    },
    user: match object.optional_json("user") {
      None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("user")))
    },
    device: match object.optional_json("device") {
      None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("device")))
    },
  }
}

///|
pub impl ToJson for AuthStatusPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["connected"] = Json(self.connected)
  if self.server_url is Some(value) {
    fields["server_url"] = Json(value)
  }
  if self.managed_by_env is Some(value) {
    fields["managed_by_env"] = Json(value)
  }
  if self.user is Some(value) {
    fields["user"] = value.to_json()
  }
  if self.device is Some(value) {
    fields["device"] = value.to_json()
  }
  Json(fields)
}

///|
pub impl FromJson for DiagnosticsPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "DiagnosticsPayload")
  {
    root: @json.from_json(
      object.required_json("root"),
      path=path.add_key("root"),
    ),
    path: @json.from_json(
      object.required_json("path"),
      path=path.add_key("path"),
    ),
    diagnostics: @json.from_json(
      object.required_json("diagnostics"),
      path=path.add_key("diagnostics"),
    ),
  }
}

///|
pub impl ToJson for DiagnosticsPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["root"] = Json(self.root)
  fields["path"] = Json(self.path)
  fields["diagnostics"] = Json(self.diagnostics)
  Json(fields)
}

///|
pub impl FromJson for FsChangedPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "FsChangedPayload")
  {
    root: @json.from_json(
      object.required_json("root"),
      path=path.add_key("root"),
    ),
    baseline: @json.from_json(
      object.required_json("baseline"),
      path=path.add_key("baseline"),
    ),
    events: @json.from_json(
      object.required_json("events"),
      path=path.add_key("events"),
    ),
    generation: @json.from_json(
      object.required_json("generation"),
      path=path.add_key("generation"),
    ),
  }
}

///|
pub impl ToJson for FsChangedPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["root"] = Json(self.root)
  fields["baseline"] = Json(self.baseline)
  fields["events"] = Json(self.events)
  fields["generation"] = Json(self.generation)
  Json(fields)
}

///|
pub impl FromJson for FsWatchFailedPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "FsWatchFailedPayload")
  {
    root: @json.from_json(
      object.required_json("root"),
      path=path.add_key("root"),
    ),
    message: @json.from_json(
      object.required_json("message"),
      path=path.add_key("message"),
    ),
    generation: @json.from_json(
      object.required_json("generation"),
      path=path.add_key("generation"),
    ),
  }
}

///|
pub impl ToJson for FsWatchFailedPayload with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  fields["root"] = Json(self.root)
  fields["message"] = Json(self.message)
  fields["generation"] = Json(self.generation)
  Json(fields)
}
