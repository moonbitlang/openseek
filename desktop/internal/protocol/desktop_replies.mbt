// Typed replies and nested wire documents for the desktop API. JSON exists
// only while a transport or an external process encodes/decodes these values;
// request handlers and frontend code exchange the closed types below.
//
// Every field described as an absolute filesystem path carries only the
// slash-rooted path component of an OpenSeek resource URI: `/home/u/work` on
// POSIX and `/C:/work` for a Windows drive. The frontend binds that path to
// the channel that produced the reply. UNC paths are outside this contract;
// workspace-relative fields remain slash-separated relative strings.

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
pub(all) struct GoalReply {
  // Whether the goal command reached a live engine for this conversation;
  // the durable `[goal]` marker commit is the real confirmation.
  delivered : Bool
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
/// `updated_at_ms` is the engine's last-activity stamp (session file mtime in
/// milliseconds); the engine sends an explicit `null` for a damaged directory
/// it cannot stat, so decoding accepts absent, `null`, and number alike.
pub(all) struct SessionListEntry {
  id : String
  title : String?
  updated_at_ms : Double?
} derive(Debug, Eq, ToJson)

///|
pub impl FromJson for SessionListEntry with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "session list entry must be an object"))
  }
  let title = match fields.get("title") {
    Some(String(title)) => Some(title)
    _ => None
  }
  let updated_at_ms = match fields.get("updated_at_ms") {
    Some(Number(value, ..)) => Some(value)
    _ => None
  }
  guard fields.get("id") is Some(String(id)) else {
    raise JsonDecodeError((path, "session list entry needs a string id"))
  }
  { id, title, updated_at_ms }
}

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
/// The expected, recoverable refusal from `session.archive`: the bound
/// checkout is dirty, so the caller must explicitly retry with `force` before
/// any local-only work may be discarded. `dirty_paths` is a bounded preview;
/// `dirty_path_count` is the complete number of porcelain status rows.
pub(all) struct ArchiveNeedsForceReply {
  worktree : String
  dirty_paths : Array[String]
  dirty_path_count : Int
} derive(Debug, Eq, FromJson, ToJson)

///|
/// `session.archive` keeps the legacy `SessionsReply` JSON shape on success so
/// older clients can consume replies from a newer host. A dirty checkout is a
/// normal confirmation state rather than a rejected bridge operation.
pub(all) enum ArchiveReply {
  Archived(SessionsReply)
  NeedsForce(ArchiveNeedsForceReply)
} derive(Debug, Eq)

///|
pub impl ToJson for ArchiveReply with fn to_json(self) {
  match self {
    Archived(reply) => ToJson::to_json(reply)
    NeedsForce(refusal) =>
      {
        "kind": "needs_force",
        "worktree": refusal.worktree,
        "dirty_paths": refusal.dirty_paths,
        "dirty_path_count": refusal.dirty_path_count,
      }
  }
}

///|
pub impl FromJson for ArchiveReply with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected archive reply"))
  }
  match fields.get("kind") {
    Some(String("needs_force")) => {
      let refusal : ArchiveNeedsForceReply = @json.from_json(json)
      NeedsForce(refusal)
    }
    Some(String(_)) =>
      raise JsonDecodeError(
        (path.add_key("kind"), "unknown archive reply kind"),
      )
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("kind"), "archive reply kind must be a string"),
      )
    None => {
      // Success deliberately remains `{groups:[...]}`, the pre-structured-
      // refusal response shape.
      let reply : SessionsReply = @json.from_json(json)
      Archived(reply)
    }
  }
}

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
/// engine store's `{kind,payload}` representation. `Unknown` retains the whole
/// raw item so an older Desktop can load and forward records written by a newer
/// engine without pretending to understand them. `UnknownTerminal` additionally
/// retains the known top-level terminal boundary when only its payload is new.
pub(all) enum SessionItem {
  User(SessionUserMessage)
  Assistant(SessionAssistantMessage)
  ToolResult(SessionToolResult)
  RuntimeNotice(SessionRuntimeNotice)
  Summary(SessionSummary)
  Terminal(SessionTerminal)
  UnknownTerminal(Json)
  Unknown(Json)
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
    UnknownTerminal(raw) => raw
    Unknown(raw) => raw
  }
}

///|
/// Whether this record closes a durable run. A newer terminal payload may not
/// render a bubble, but its top-level `kind` still settles ordering and notices.
pub fn SessionItem::is_terminal(self : SessionItem) -> Bool {
  self is Terminal(_) || self is UnknownTerminal(_)
}

///|
pub impl FromJson for SessionItem with fn from_json(json, path) {
  guard json is Object(fields) && fields.get("kind") is Some(String(kind_)) else {
    return Unknown(json)
  }
  guard fields.get("payload") is Some(payload) else {
    return if kind_ == "terminal" {
      UnknownTerminal(json)
    } else {
      Unknown(json)
    }
  }
  match kind_ {
    "user" =>
      User(@json.from_json(payload, path=path.add_key("payload"))) catch {
        _ => Unknown(json)
      }
    "assistant" =>
      Assistant(@json.from_json(payload, path=path.add_key("payload"))) catch {
        _ => Unknown(json)
      }
    "tool_result" =>
      ToolResult(@json.from_json(payload, path=path.add_key("payload"))) catch {
        _ => Unknown(json)
      }
    "runtime_notice" =>
      RuntimeNotice(@json.from_json(payload, path=path.add_key("payload"))) catch {
        _ => Unknown(json)
      }
    "summary" =>
      Summary(@json.from_json(payload, path=path.add_key("payload"))) catch {
        _ => Unknown(json)
      }
    "terminal" =>
      Terminal(@json.from_json(payload, path=path.add_key("payload"))) catch {
        _ => UnknownTerminal(json)
      }
    _ => Unknown(json)
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
/// engines stays optional; Desktop's transcript is defined by `events`, whose
/// unknown items remain available for forward-compatible round trips.
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
/// A workspace list, or a mutation's refusal reason with the registry left
/// unchanged. Success keeps the legacy `{workspaces:[...]}` shape; the
/// refusal rides in the reply body as `{error:"..."}` because the local
/// bridge summarizes raised handler errors down to "op <name> failed".
pub(all) enum WorkspacesReply {
  Workspaces(Array[String])
  WorkspaceError(String)
} derive(Debug, Eq)

///|
pub impl ToJson for WorkspacesReply with fn to_json(self) {
  match self {
    Workspaces(workspaces) => { "workspaces": workspaces }
    WorkspaceError(message) => { "error": message }
  }
}

///|
pub impl FromJson for WorkspacesReply with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected a workspaces reply"))
  }
  match fields.get("error") {
    Some(String(message)) => WorkspaceError(message)
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("error"), "workspace error must be a string"),
      )
    None => {
      guard fields.get("workspaces") is Some(listed) else {
        raise JsonDecodeError((path, "expected a workspaces list"))
      }
      Workspaces(@json.from_json(listed))
    }
  }
}

///|
/// One worktree as ops report it: the registry entry plus its derived checkout
/// path and whether that directory still exists on disk. Exactly one of
/// `session` and `codex_thread` identifies the conversation that owns it;
/// ownerless rows are tolerated only for backward-compatible hand-edited
/// registries and are never claimed by either conversation source.
pub(all) struct WorktreeInfo {
  name : String
  branch : String
  base : String
  session : String?
  codex_thread : String?
  path : String
  present : Bool
} derive(Debug, Eq)

///|
pub impl FromJson for WorktreeInfo with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected worktree info"))
  }
  let name = match fields.get("name") {
    Some(String(value)) => value
    Some(_) => raise JsonDecodeError((path.add_key("name"), "expected string"))
    None =>
      raise JsonDecodeError((path.add_key("name"), "missing required field"))
  }
  let branch = match fields.get("branch") {
    Some(String(value)) => value
    Some(_) =>
      raise JsonDecodeError((path.add_key("branch"), "expected string"))
    None =>
      raise JsonDecodeError((path.add_key("branch"), "missing required field"))
  }
  let base = match fields.get("base") {
    Some(String(value)) => value
    Some(_) => raise JsonDecodeError((path.add_key("base"), "expected string"))
    None =>
      raise JsonDecodeError((path.add_key("base"), "missing required field"))
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
  if session is Some(_) && codex_thread is Some(_) {
    raise JsonDecodeError(
      (path, "worktree cannot belong to both session and codex_thread"),
    )
  }
  let checkout_path = match fields.get("path") {
    Some(String(value)) => value
    Some(_) => raise JsonDecodeError((path.add_key("path"), "expected string"))
    None =>
      raise JsonDecodeError((path.add_key("path"), "missing required field"))
  }
  let present = match fields.get("present") {
    Some(True) => true
    Some(False) => false
    Some(_) =>
      raise JsonDecodeError((path.add_key("present"), "expected boolean"))
    None =>
      raise JsonDecodeError((path.add_key("present"), "missing required field"))
  }
  { name, branch, base, session, codex_thread, path: checkout_path, present }
}

///|
pub impl ToJson for WorktreeInfo with fn to_json(self) {
  let fields : Map[String, Json] = {
    "name": Json::string(self.name),
    "branch": Json::string(self.branch),
    "base": Json::string(self.base),
    "path": Json::string(self.path),
    "present": Json::boolean(self.present),
  }
  if self.session is Some(session) {
    fields["session"] = Json::string(session)
  }
  if self.codex_thread is Some(thread_id) {
    fields["codex_thread"] = Json::string(thread_id)
  }
  Json::object(fields)
}

///|
pub(all) struct WorktreesReply {
  worktrees : Array[WorktreeInfo]
} derive(Debug, Eq, FromJson, ToJson)

///|
/// A create's reply names the worktree it made — the client sends no name
/// and needs the generated one to start the bound conversation.
pub(all) struct WorktreeCreateReply {
  name : String
  worktrees : Array[WorktreeInfo]
} derive(Debug, Eq, FromJson, ToJson)

///|
/// A worktree creation either returns the existing success object or a safe
/// domain refusal. Refusals ride in the reply body because the local Proton
/// boundary deliberately hides arbitrary handler diagnostics.
pub(all) enum WorktreeCreateResult {
  WorktreeCreatedReply(WorktreeCreateReply)
  WorktreeCreateError(String)
} derive(Debug, Eq)

///|
pub impl ToJson for WorktreeCreateResult with fn to_json(self) {
  match self {
    WorktreeCreatedReply(reply) => ToJson::to_json(reply)
    WorktreeCreateError(message) => { "error": message }
  }
}

///|
pub impl FromJson for WorktreeCreateResult with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected a worktree creation result"))
  }
  match fields.get("error") {
    Some(String(message)) => WorktreeCreateError(message)
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("error"), "worktree creation error must be a string"),
      )
    None => WorktreeCreatedReply(@json.from_json(json))
  }
}

///|
pub(all) struct OpenPathEditorTarget {
  // Slash-separated path relative to the conversation's resolved checkout.
  path : String
  // Absent for an ordinary file reference; present for a parsed
  // `:line[:column]` or `#Lline` suffix.
  line : Int?
  column : Int?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct OpenPathDirectoryTarget {
  // Slash-separated path relative to the conversation's resolved checkout.
  path : String
} derive(Debug, Eq, FromJson, ToJson)

///|
/// Reply to `open_path`: the route one transcript-referenced path took. The
/// variants are exhaustive — the frontend matches on them directly instead of
/// re-deriving the route from which optional field is present. The wire
/// contract stays shape-compatible: `Opened` is the pre-structured
/// `{opened: true}`, and the targets and the refusal ride the same optional
/// fields the previous struct used, so older bundled hosts and frontends keep
/// decoding every reply.
pub(all) enum OpenPathReply {
  // The host handed a non-text path (or any path outside the checkout's
  // built-in text/directory policy) to the system opener.
  Opened
  // A viewer-sized UTF-8 file inside the checkout, with optional position.
  Editor(OpenPathEditorTarget)
  // A literal directory inside the conversation checkout, for the built-in
  // Files tree.
  Directory(OpenPathDirectoryTarget)
  // The open was refused: the user-facing reason (missing path, text file
  // outside the checkout, opener failure). The frontend shows this message
  // instead of the bridge's generic `op … failed` text.
  Refused(String)
} derive(Debug, Eq)

///|
pub impl ToJson for OpenPathReply with fn to_json(self) {
  match self {
    Opened => { "opened": true }
    Editor(target) =>
      { "opened": false, "editor_target": ToJson::to_json(target) }
    Directory(target) =>
      { "opened": false, "directory_target": ToJson::to_json(target) }
    Refused(message) => { "opened": false, "error": message }
  }
}

///|
/// Decode prefers the same route the frontend acted on: an editor target wins
/// over a directory target, which wins over a refusal, which wins over the
/// legacy bare `{opened: true}`. A reply that names no route at all is
/// rejected rather than decoded to an invented outcome.
pub impl FromJson for OpenPathReply with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected an open_path reply"))
  }
  if fields.get("editor_target") is Some(target) && target is Object(_) {
    Editor(@json.from_json(target))
  } else if fields.get("directory_target") is Some(target) &&
    target is Object(_) {
    Directory(@json.from_json(target))
  } else {
    match fields.get("error") {
      Some(String(message)) => Refused(message)
      Some(_) =>
        raise JsonDecodeError(
          (path.add_key("error"), "open_path refusal must be a string"),
        )
      None =>
        match fields.get("opened") {
          Some(True) => Opened
          _ => raise JsonDecodeError((path, "open_path reply names no route"))
        }
    }
  }
}

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
/// This branch's whole line delta, measured locally: from where it left the
/// remote's default branch all the way to the working tree, so committed and
/// uncommitted work count the same and untracked files are included. `base`
/// names the ref it was measured from, and is absent when the repository
/// offered none — then the count covers uncommitted work alone. `partial`
/// marks a count that stopped short of every untracked file, so the composer
/// can say the number is a floor rather than quietly under-reporting.
pub(all) struct GitDiffStat {
  added : Int
  removed : Int
  files : Int
  base : String?
  partial : Bool
} derive(Debug, Eq, FromJson, ToJson)

///|
/// `diffstat` is absent for the same reasons `branch` is (no repository, no
/// git), and additionally when the diff itself failed — the branch chip is
/// worth showing on its own. Older peers omit the field entirely, which
/// decodes to the same absence.
pub(all) struct GitBranchReply {
  branch : String?
  diffstat : GitDiffStat?
} derive(Debug, Eq, FromJson, ToJson)

///|
/// The CI rollup for a pull request's head commit, bucketed into the three
/// states a chip can show. Skipped, neutral, and cancelled checks count as
/// passed: they are finished and not something to act on.
pub(all) struct GitChecks {
  passed : Int
  failed : Int
  pending : Int
} derive(Debug, Eq, FromJson, ToJson)

///|
/// One pull request as GitHub reports it. `state` is `open`, `merged`, or
/// `closed`; a draft is `open` with `draft` set, since drafts are open pull
/// requests that merely refuse to merge. `additions`/`deletions` are GitHub's
/// own totals against the pull request's base, which is why they can disagree
/// with anything measurable from a local checkout that has not fetched.
/// `checks` is absent when the head commit reports no checks at all.
/// `base` is the branch this pull request merges into — GitHub's own answer,
/// and the only source for it: a branch records nothing about where it came
/// from, and a base that is another feature branch (a stacked pull request)
/// is not something any local rule would guess.
pub(all) struct GitPullRequest {
  number : Int
  title : String
  state : String
  draft : Bool
  url : String
  base : String
  additions : Int
  deletions : Int
  changed_files : Int
  checks : GitChecks?
} derive(Debug, Eq, FromJson, ToJson)

///|
/// Reply to `git.pull_request`. `pull_request` and `compare_url` both absent
/// means the host could not answer at all — no repository, no GitHub remote,
/// or no usable `gh` — which the composer shows as no chip rather than an
/// error. `compare_url` alone is the ordinary "this branch has no pull request
/// yet" answer, and the composer offers it as a link to open one.
///
/// `branch` is the branch the host actually looked up, which is not
/// necessarily the one the client had in mind when it asked: the host reads
/// `HEAD` itself, and an agent can move the checkout in between. The client
/// labels the answer with this rather than with its own request, so a pull
/// request can never be shown against a branch it does not belong to.
pub(all) struct GitPullRequestReply {
  pull_request : GitPullRequest?
  compare_url : String?
  branch : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
/// One current-path row from the active review comparison. HEAD-based
/// inventories retain `git status --porcelain=v1 -z`'s index/worktree columns;
/// baseline inventories put their single comparison status in the worktree
/// column and never imply that committed work is staged. Codes keep Git's
/// spellings (`" "`, `M`, `A`, `D`, `R`, …), while `kind` is one of
/// `modified`, `added`, `deleted`, `renamed`, `copied`, `unmerged`,
/// `type-changed`, `untracked`, `submodule`, or `symlink` (with unknown future
/// statuses falling back to `modified`).
/// Renames and copies carry their source path separately.
pub(all) struct GitChange {
  path : String
  original_path : String?
  index_status : String
  worktree_status : String
  kind : String
} derive(Debug, Eq, FromJson, ToJson)

///|
/// The active checkout's change inventory plus its immutable comparison
/// baseline: a worktree's task base or an ordinary branch's default-branch
/// fork point. When `baseline` exists the inventory compares it to the working
/// tree, including committed work; the HEAD fallback remains ordinary staged +
/// unstaged status. A missing Git executable and a non-repository workspace
/// both report `repository=false`; once a repository is recognized,
/// operational failures are request errors rather than an ambiguous empty
/// list.
pub(all) struct GitChangesReply {
  repository : Bool
  // The commit object currently named by HEAD. `None` covers an unborn HEAD,
  // a non-repository workspace, and older hosts that predate this field.
  head : String?
  // The immutable commit used as the review's left side. New hosts return it
  // whenever one exists; clients fall back to `head` when talking to an older
  // host that omitted the field.
  baseline : String?
  changes : Array[GitChange]
} derive(Debug, Eq, FromJson, ToJson)

///|
/// One path's comparison blob for quick diff. `Missing` is the legitimate
/// baseline for an added/untracked file or an unborn `HEAD`; withheld blobs
/// mirror the ordinary file reader's binary and one-megabyte policies.
pub(all) enum GitOriginalFileReply {
  Missing
  BinaryOriginal
  OversizedOriginal
  OriginalContent(String)
} derive(Debug, Eq)

///|
pub impl ToJson for GitOriginalFileReply with fn to_json(self) {
  match self {
    Missing => { "kind": "missing" }
    BinaryOriginal => { "kind": "binary" }
    OversizedOriginal => { "kind": "oversized" }
    OriginalContent(content) => { "kind": "content", "content": content }
  }
}

///|
pub impl FromJson for GitOriginalFileReply with fn from_json(json, path) {
  guard json is Object(fields) && fields.get("kind") is Some(String(kind_)) else {
    raise JsonDecodeError((path, "expected Git original-file reply"))
  }
  match kind_ {
    "missing" => Missing
    "binary" => BinaryOriginal
    "oversized" => OversizedOriginal
    "content" => {
      guard fields.get("content") is Some(String(content)) else {
        raise JsonDecodeError((path, "malformed Git original-file reply"))
      }
      OriginalContent(content)
    }
    _ =>
      raise JsonDecodeError(
        (path.add_key("kind"), "unknown Git original-file reply kind"),
      )
  }
}

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
pub(all) struct SearchFilesReply {
  files : Array[String]
  from_cache : Bool
  limit_hit : Bool
  cancelled : Bool
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) enum ReadFileReply {
  Binary
  Oversized
  BinaryContent(data_base64~ : String, media_type~ : String)
  Content(content~ : String, absolute~ : String, sig~ : String)
} derive(Debug, Eq)

///|
pub impl ToJson for ReadFileReply with fn to_json(self) {
  match self {
    Binary => { "kind": "binary" }
    Oversized => { "kind": "oversized" }
    BinaryContent(data_base64~, media_type~) =>
      {
        "kind": "binary_content",
        "data_base64": data_base64,
        "media_type": media_type,
      }
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
    "binary_content" => {
      guard fields.get("data_base64") is Some(String(data_base64)) &&
        fields.get("media_type") is Some(String(media_type)) else {
        raise JsonDecodeError((path, "malformed binary file content reply"))
      }
      BinaryContent(data_base64~, media_type~)
    }
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
/// One directory listing (`parent` is `None` at a filesystem root), the
/// Windows drive list, or the reason there is none. Success keeps the
/// legacy `{path,parent?,entries}` shape; the refusal rides in the reply
/// body as `{error:"..."}` because the local bridge summarizes raised
/// handler errors down to "op <name> failed".
pub(all) enum BrowseDirectoryReply {
  Listing(path~ : String, parent~ : String?, entries~ : Array[String])
  // Windows only: the virtual level above the drive roots, reached by
  // browsing the resource-path root "/". Entries are drive spellings such
  // as "C:"; the drive root itself is the resource path "/C:/".
  Drives(entries~ : Array[String])
  BrowseError(String)
} derive(Debug, Eq)

///|
pub impl ToJson for BrowseDirectoryReply with fn to_json(self) {
  match self {
    Listing(path~, parent~, entries~) => {
      let fields : Map[String, Json] = {
        "path": path.to_json(),
        "entries": entries.to_json(),
      }
      if parent is Some(parent) {
        fields["parent"] = parent.to_json()
      }
      Json::object(fields)
    }
    Drives(entries~) => { "drives": entries.to_json() }
    BrowseError(message) => { "error": message }
  }
}

///|
pub impl FromJson for BrowseDirectoryReply with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected a directory listing"))
  }
  match fields.get("error") {
    Some(String(message)) => BrowseError(message)
    Some(_) =>
      raise JsonDecodeError(
        (path.add_key("error"), "browse error must be a string"),
      )
    None => {
      if fields.get("drives") is Some(drives) {
        return Drives(entries=@json.from_json(drives))
      }
      guard fields.get("path") is Some(String(listed)) else {
        raise JsonDecodeError((path, "expected a directory path"))
      }
      let parent : String? = match fields.get("parent") {
        Some(String(parent)) => Some(parent)
        Some(_) =>
          raise JsonDecodeError(
            (path.add_key("parent"), "directory parent must be a string"),
          )
        None => None
      }
      guard fields.get("entries") is Some(entries) else {
        raise JsonDecodeError((path, "expected directory entries"))
      }
      Listing(path=listed, parent~, entries=@json.from_json(entries))
    }
  }
}

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
/// The field is absent when the check itself could not run — "no data", which
/// the client answers by keeping the markers it has, distinct from the empty
/// array's "no problems", which clears them.
pub(all) struct LspDiagnosticsReply {
  diagnostics : Array[LspDiagnostic]?
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

///|
pub extend AgentStreamEvent with Debug::{to_repr}

///|
pub extend AgentStreamEvent with FromJson::{from_json}

///|
pub extend AgentStreamEvent with Eq::{equal, not_equal}

///|
pub extend AgentStreamEvent with ToJson::{to_json}

///|
pub extend AppEntry with Debug::{to_repr}

///|
pub extend AppEntry with FromJson::{from_json}

///|
pub extend AppEntry with Eq::{equal, not_equal}

///|
pub extend AppEntry with ToJson::{to_json}

///|
pub extend ApplyUpdateReply with Debug::{to_repr}

///|
pub extend ApplyUpdateReply with FromJson::{from_json}

///|
pub extend ApplyUpdateReply with Eq::{equal, not_equal}

///|
pub extend ApplyUpdateReply with ToJson::{to_json}

///|
pub extend ArchiveNeedsForceReply with Debug::{to_repr}

///|
pub extend ArchiveNeedsForceReply with FromJson::{from_json}

///|
pub extend ArchiveNeedsForceReply with Eq::{equal, not_equal}

///|
pub extend ArchiveNeedsForceReply with ToJson::{to_json}

///|
pub extend ArchiveReply with Debug::{to_repr}

///|
pub extend ArchiveReply with FromJson::{from_json}

///|
pub extend ArchiveReply with Eq::{equal, not_equal}

///|
pub extend ArchiveReply with ToJson::{to_json}

///|
pub extend BrowseDirectoryReply with Debug::{to_repr}

///|
pub extend BrowseDirectoryReply with FromJson::{from_json}

///|
pub extend BrowseDirectoryReply with Eq::{equal, not_equal}

///|
pub extend BrowseDirectoryReply with ToJson::{to_json}

///|
pub extend CancelReply with Debug::{to_repr}

///|
pub extend CancelReply with FromJson::{from_json}

///|
pub extend CancelReply with Eq::{equal, not_equal}

///|
pub extend CancelReply with ToJson::{to_json}

///|
pub extend CheckUpdateReply with Debug::{to_repr}

///|
pub extend CheckUpdateReply with FromJson::{from_json}

///|
pub extend CheckUpdateReply with Eq::{equal, not_equal}

///|
pub extend CheckUpdateReply with ToJson::{to_json}

///|
pub extend CompactReply with Debug::{to_repr}

///|
pub extend CompactReply with FromJson::{from_json}

///|
pub extend CompactReply with Eq::{equal, not_equal}

///|
pub extend CompactReply with ToJson::{to_json}

///|
pub extend DirEntry with Debug::{to_repr}

///|
pub extend DirEntry with FromJson::{from_json}

///|
pub extend DirEntry with Eq::{equal, not_equal}

///|
pub extend DirEntry with ToJson::{to_json}

///|
pub extend DownloadUpdateAcceptedReply with Debug::{to_repr}

///|
pub extend DownloadUpdateAcceptedReply with FromJson::{from_json}

///|
pub extend DownloadUpdateAcceptedReply with Eq::{equal, not_equal}

///|
pub extend DownloadUpdateAcceptedReply with ToJson::{to_json}

///|
pub extend EmptyPayload with Debug::{to_repr}

///|
pub extend EmptyPayload with FromJson::{from_json}

///|
pub extend EmptyPayload with Eq::{equal, not_equal}

///|
pub extend EmptyPayload with ToJson::{to_json}

///|
pub extend EmptyReply with Debug::{to_repr}

///|
pub extend EmptyReply with FromJson::{from_json}

///|
pub extend EmptyReply with Eq::{equal, not_equal}

///|
pub extend EmptyReply with ToJson::{to_json}

///|
pub extend FileStat with Debug::{to_repr}

///|
pub extend FileStat with FromJson::{from_json}

///|
pub extend FileStat with Eq::{equal, not_equal}

///|
pub extend FileStat with ToJson::{to_json}

///|
pub extend GitBranchReply with Debug::{to_repr}

///|
pub extend GitBranchReply with FromJson::{from_json}

///|
pub extend GitBranchReply with Eq::{equal, not_equal}

///|
pub extend GitBranchReply with ToJson::{to_json}

///|
pub extend GitChange with Debug::{to_repr}

///|
pub extend GitChange with FromJson::{from_json}

///|
pub extend GitChange with Eq::{equal, not_equal}

///|
pub extend GitChange with ToJson::{to_json}

///|
pub extend GitChangesReply with Debug::{to_repr}

///|
pub extend GitChangesReply with FromJson::{from_json}

///|
pub extend GitChangesReply with Eq::{equal, not_equal}

///|
pub extend GitChangesReply with ToJson::{to_json}

///|
pub extend GitChecks with Debug::{to_repr}

///|
pub extend GitChecks with FromJson::{from_json}

///|
pub extend GitChecks with Eq::{equal, not_equal}

///|
pub extend GitChecks with ToJson::{to_json}

///|
pub extend GitDiffStat with Debug::{to_repr}

///|
pub extend GitDiffStat with FromJson::{from_json}

///|
pub extend GitDiffStat with Eq::{equal, not_equal}

///|
pub extend GitDiffStat with ToJson::{to_json}

///|
pub extend GitOriginalFileReply with Debug::{to_repr}

///|
pub extend GitOriginalFileReply with FromJson::{from_json}

///|
pub extend GitOriginalFileReply with Eq::{equal, not_equal}

///|
pub extend GitOriginalFileReply with ToJson::{to_json}

///|
pub extend GitPullRequest with Debug::{to_repr}

///|
pub extend GitPullRequest with FromJson::{from_json}

///|
pub extend GitPullRequest with Eq::{equal, not_equal}

///|
pub extend GitPullRequest with ToJson::{to_json}

///|
pub extend GitPullRequestReply with Debug::{to_repr}

///|
pub extend GitPullRequestReply with FromJson::{from_json}

///|
pub extend GitPullRequestReply with Eq::{equal, not_equal}

///|
pub extend GitPullRequestReply with ToJson::{to_json}

///|
pub extend GoalReply with Debug::{to_repr}

///|
pub extend GoalReply with FromJson::{from_json}

///|
pub extend GoalReply with Eq::{equal, not_equal}

///|
pub extend GoalReply with ToJson::{to_json}

///|
pub extend InstallSkillReply with Debug::{to_repr}

///|
pub extend InstallSkillReply with FromJson::{from_json}

///|
pub extend InstallSkillReply with Eq::{equal, not_equal}

///|
pub extend InstallSkillReply with ToJson::{to_json}

///|
pub extend InstalledSkill with Debug::{to_repr}

///|
pub extend InstalledSkill with FromJson::{from_json}

///|
pub extend InstalledSkill with Eq::{equal, not_equal}

///|
pub extend InstalledSkill with ToJson::{to_json}

///|
pub extend InstalledSkillsReply with Debug::{to_repr}

///|
pub extend InstalledSkillsReply with FromJson::{from_json}

///|
pub extend InstalledSkillsReply with Eq::{equal, not_equal}

///|
pub extend InstalledSkillsReply with ToJson::{to_json}

///|
pub extend LaunchAppReply with Debug::{to_repr}

///|
pub extend LaunchAppReply with FromJson::{from_json}

///|
pub extend LaunchAppReply with Eq::{equal, not_equal}

///|
pub extend LaunchAppReply with ToJson::{to_json}

///|
pub extend ListAppsReply with Debug::{to_repr}

///|
pub extend ListAppsReply with FromJson::{from_json}

///|
pub extend ListAppsReply with Eq::{equal, not_equal}

///|
pub extend ListAppsReply with ToJson::{to_json}

///|
pub extend LoadSessionReply with Debug::{to_repr}

///|
pub extend LoadSessionReply with FromJson::{from_json}

///|
pub extend LoadSessionReply with Eq::{equal, not_equal}

///|
pub extend LoadSessionReply with ToJson::{to_json}

///|
pub extend LspDiagnostic with Debug::{to_repr}

///|
pub extend LspDiagnostic with FromJson::{from_json}

///|
pub extend LspDiagnostic with Eq::{equal, not_equal}

///|
pub extend LspDiagnostic with ToJson::{to_json}

///|
pub extend LspDiagnosticsReply with Debug::{to_repr}

///|
pub extend LspDiagnosticsReply with FromJson::{from_json}

///|
pub extend LspDiagnosticsReply with Eq::{equal, not_equal}

///|
pub extend LspDiagnosticsReply with ToJson::{to_json}

///|
pub extend LspHoverReply with Debug::{to_repr}

///|
pub extend LspHoverReply with FromJson::{from_json}

///|
pub extend LspHoverReply with Eq::{equal, not_equal}

///|
pub extend LspHoverReply with ToJson::{to_json}

///|
pub extend LspPosition with Debug::{to_repr}

///|
pub extend LspPosition with FromJson::{from_json}

///|
pub extend LspPosition with Eq::{equal, not_equal}

///|
pub extend LspPosition with ToJson::{to_json}

///|
pub extend LspRange with Debug::{to_repr}

///|
pub extend LspRange with FromJson::{from_json}

///|
pub extend LspRange with Eq::{equal, not_equal}

///|
pub extend LspRange with ToJson::{to_json}

///|
pub extend MarketSkill with Debug::{to_repr}

///|
pub extend MarketSkill with FromJson::{from_json}

///|
pub extend MarketSkill with Eq::{equal, not_equal}

///|
pub extend MarketSkill with ToJson::{to_json}

///|
pub extend MoonIdeLocation with Debug::{to_repr}

///|
pub extend MoonIdeLocation with FromJson::{from_json}

///|
pub extend MoonIdeLocation with Eq::{equal, not_equal}

///|
pub extend MoonIdeLocation with ToJson::{to_json}

///|
pub extend MoonIdeLocationsReply with Debug::{to_repr}

///|
pub extend MoonIdeLocationsReply with FromJson::{from_json}

///|
pub extend MoonIdeLocationsReply with Eq::{equal, not_equal}

///|
pub extend MoonIdeLocationsReply with ToJson::{to_json}

///|
pub extend OpenExternalReply with Debug::{to_repr}

///|
pub extend OpenExternalReply with FromJson::{from_json}

///|
pub extend OpenExternalReply with Eq::{equal, not_equal}

///|
pub extend OpenExternalReply with ToJson::{to_json}

///|
pub extend OpenPathDirectoryTarget with Debug::{to_repr}

///|
pub extend OpenPathDirectoryTarget with FromJson::{from_json}

///|
pub extend OpenPathDirectoryTarget with Eq::{equal, not_equal}

///|
pub extend OpenPathDirectoryTarget with ToJson::{to_json}

///|
pub extend OpenPathEditorTarget with Debug::{to_repr}

///|
pub extend OpenPathEditorTarget with FromJson::{from_json}

///|
pub extend OpenPathEditorTarget with Eq::{equal, not_equal}

///|
pub extend OpenPathEditorTarget with ToJson::{to_json}

///|
pub extend OpenPathReply with Debug::{to_repr}

///|
pub extend OpenPathReply with FromJson::{from_json}

///|
pub extend OpenPathReply with Eq::{equal, not_equal}

///|
pub extend OpenPathReply with ToJson::{to_json}

///|
pub extend ReadDirReply with Debug::{to_repr}

///|
pub extend ReadDirReply with FromJson::{from_json}

///|
pub extend ReadDirReply with Eq::{equal, not_equal}

///|
pub extend ReadDirReply with ToJson::{to_json}

///|
pub extend ReadFileReply with Debug::{to_repr}

///|
pub extend ReadFileReply with FromJson::{from_json}

///|
pub extend ReadFileReply with Eq::{equal, not_equal}

///|
pub extend ReadFileReply with ToJson::{to_json}

///|
pub extend RunSettlementPayload with Debug::{to_repr}

///|
pub extend RunSettlementPayload with FromJson::{from_json}

///|
pub extend RunSettlementPayload with Eq::{equal, not_equal}

///|
pub extend RunSettlementPayload with ToJson::{to_json}

///|
pub extend RunsReply with Debug::{to_repr}

///|
pub extend RunsReply with FromJson::{from_json}

///|
pub extend RunsReply with Eq::{equal, not_equal}

///|
pub extend RunsReply with ToJson::{to_json}

///|
pub extend SearchFilesReply with Debug::{to_repr}

///|
pub extend SearchFilesReply with FromJson::{from_json}

///|
pub extend SearchFilesReply with Eq::{equal, not_equal}

///|
pub extend SearchFilesReply with ToJson::{to_json}

///|
pub extend SessionAssistantMessage with Debug::{to_repr}

///|
pub extend SessionAssistantMessage with FromJson::{from_json}

///|
pub extend SessionAssistantMessage with Eq::{equal, not_equal}

///|
pub extend SessionAssistantMessage with ToJson::{to_json}

///|
pub extend SessionDocument with Debug::{to_repr}

///|
pub extend SessionDocument with FromJson::{from_json}

///|
pub extend SessionDocument with Eq::{equal, not_equal}

///|
pub extend SessionDocument with ToJson::{to_json}

///|
pub extend SessionEvent with Debug::{to_repr}

///|
pub extend SessionEvent with FromJson::{from_json}

///|
pub extend SessionEvent with Eq::{equal, not_equal}

///|
pub extend SessionEvent with ToJson::{to_json}

///|
pub extend SessionGroup with Debug::{to_repr}

///|
pub extend SessionGroup with FromJson::{from_json}

///|
pub extend SessionGroup with Eq::{equal, not_equal}

///|
pub extend SessionGroup with ToJson::{to_json}

///|
pub extend SessionItem with Debug::{to_repr}

///|
pub extend SessionItem with FromJson::{from_json}

///|
pub extend SessionItem with Eq::{equal, not_equal}

///|
pub extend SessionItem with ToJson::{to_json}

///|
pub extend SessionListEntry with Debug::{to_repr}

///|
pub extend SessionListEntry with FromJson::{from_json}

///|
pub extend SessionListEntry with Eq::{equal, not_equal}

///|
pub extend SessionListEntry with ToJson::{to_json}

///|
pub extend SessionRuntimeNotice with Debug::{to_repr}

///|
pub extend SessionRuntimeNotice with FromJson::{from_json}

///|
pub extend SessionRuntimeNotice with Eq::{equal, not_equal}

///|
pub extend SessionRuntimeNotice with ToJson::{to_json}

///|
pub extend SessionSummary with Debug::{to_repr}

///|
pub extend SessionSummary with FromJson::{from_json}

///|
pub extend SessionSummary with Eq::{equal, not_equal}

///|
pub extend SessionSummary with ToJson::{to_json}

///|
pub extend SessionTerminal with Debug::{to_repr}

///|
pub extend SessionTerminal with FromJson::{from_json}

///|
pub extend SessionTerminal with Eq::{equal, not_equal}

///|
pub extend SessionTerminal with ToJson::{to_json}

///|
pub extend SessionToolCall with Debug::{to_repr}

///|
pub extend SessionToolCall with FromJson::{from_json}

///|
pub extend SessionToolCall with Eq::{equal, not_equal}

///|
pub extend SessionToolCall with ToJson::{to_json}

///|
pub extend SessionToolResult with Debug::{to_repr}

///|
pub extend SessionToolResult with FromJson::{from_json}

///|
pub extend SessionToolResult with Eq::{equal, not_equal}

///|
pub extend SessionToolResult with ToJson::{to_json}

///|
pub extend SessionUserMessage with Debug::{to_repr}

///|
pub extend SessionUserMessage with FromJson::{from_json}

///|
pub extend SessionUserMessage with Eq::{equal, not_equal}

///|
pub extend SessionUserMessage with ToJson::{to_json}

///|
pub extend SessionsReply with Debug::{to_repr}

///|
pub extend SessionsReply with FromJson::{from_json}

///|
pub extend SessionsReply with Eq::{equal, not_equal}

///|
pub extend SessionsReply with ToJson::{to_json}

///|
pub extend SkillsCatalogReply with Debug::{to_repr}

///|
pub extend SkillsCatalogReply with FromJson::{from_json}

///|
pub extend SkillsCatalogReply with Eq::{equal, not_equal}

///|
pub extend SkillsCatalogReply with ToJson::{to_json}

///|
pub extend StartReply with Debug::{to_repr}

///|
pub extend StartReply with FromJson::{from_json}

///|
pub extend StartReply with Eq::{equal, not_equal}

///|
pub extend StartReply with ToJson::{to_json}

///|
pub extend StatFilesReply with Debug::{to_repr}

///|
pub extend StatFilesReply with FromJson::{from_json}

///|
pub extend StatFilesReply with Eq::{equal, not_equal}

///|
pub extend StatFilesReply with ToJson::{to_json}

///|
pub extend SteerReply with Debug::{to_repr}

///|
pub extend SteerReply with FromJson::{from_json}

///|
pub extend SteerReply with Eq::{equal, not_equal}

///|
pub extend SteerReply with ToJson::{to_json}

///|
pub extend SymbolItem with Debug::{to_repr}

///|
pub extend SymbolItem with FromJson::{from_json}

///|
pub extend SymbolItem with Eq::{equal, not_equal}

///|
pub extend SymbolItem with ToJson::{to_json}

///|
pub extend SymbolPosition with Debug::{to_repr}

///|
pub extend SymbolPosition with FromJson::{from_json}

///|
pub extend SymbolPosition with Eq::{equal, not_equal}

///|
pub extend SymbolPosition with ToJson::{to_json}

///|
pub extend SymbolRange with Debug::{to_repr}

///|
pub extend SymbolRange with FromJson::{from_json}

///|
pub extend SymbolRange with Eq::{equal, not_equal}

///|
pub extend SymbolRange with ToJson::{to_json}

///|
pub extend TerminalOpenReply with Debug::{to_repr}

///|
pub extend TerminalOpenReply with FromJson::{from_json}

///|
pub extend TerminalOpenReply with Eq::{equal, not_equal}

///|
pub extend TerminalOpenReply with ToJson::{to_json}

///|
pub extend UninstallSkillReply with Debug::{to_repr}

///|
pub extend UninstallSkillReply with FromJson::{from_json}

///|
pub extend UninstallSkillReply with Eq::{equal, not_equal}

///|
pub extend UninstallSkillReply with ToJson::{to_json}

///|
pub extend WorkspaceSymbolsReply with Debug::{to_repr}

///|
pub extend WorkspaceSymbolsReply with FromJson::{from_json}

///|
pub extend WorkspaceSymbolsReply with Eq::{equal, not_equal}

///|
pub extend WorkspaceSymbolsReply with ToJson::{to_json}

///|
pub extend WorkspacesReply with Debug::{to_repr}

///|
pub extend WorkspacesReply with FromJson::{from_json}

///|
pub extend WorkspacesReply with Eq::{equal, not_equal}

///|
pub extend WorkspacesReply with ToJson::{to_json}

///|
pub extend WorktreeCreateReply with Debug::{to_repr}

///|
pub extend WorktreeCreateReply with FromJson::{from_json}

///|
pub extend WorktreeCreateReply with Eq::{equal, not_equal}

///|
pub extend WorktreeCreateReply with ToJson::{to_json}

///|
pub extend WorktreeCreateResult with Debug::{to_repr}

///|
pub extend WorktreeCreateResult with FromJson::{from_json}

///|
pub extend WorktreeCreateResult with Eq::{equal, not_equal}

///|
pub extend WorktreeCreateResult with ToJson::{to_json}

///|
pub extend WorktreeInfo with Debug::{to_repr}

///|
pub extend WorktreeInfo with FromJson::{from_json}

///|
pub extend WorktreeInfo with Eq::{equal, not_equal}

///|
pub extend WorktreeInfo with ToJson::{to_json}

///|
pub extend WorktreesReply with Debug::{to_repr}

///|
pub extend WorktreesReply with FromJson::{from_json}

///|
pub extend WorktreesReply with Eq::{equal, not_equal}

///|
pub extend WorktreesReply with ToJson::{to_json}
