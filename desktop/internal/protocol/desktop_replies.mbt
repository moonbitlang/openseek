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
    Archived(reply) => reply.to_json()
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
pub(all) struct WorkspacesReply {
  workspaces : Array[String]
} derive(Debug, Eq, FromJson, ToJson)

///|
/// One worktree as ops report it: the registry entry plus its derived
/// checkout path and whether that directory still exists on disk. `session`
/// is the one conversation this worktree is the execution environment of;
/// `None` only between creation and the binding first start.
pub(all) struct WorktreeInfo {
  name : String
  branch : String
  base : String
  session : String?
  path : String
  present : Bool
} derive(Debug, Eq, FromJson, ToJson)

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
/// task-base inventories put their single comparison status in the worktree
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
/// The active checkout's change inventory plus the immutable task baseline
/// available to worktree-aware review clients. When `baseline` exists the
/// inventory compares it to the working tree, including committed work; the
/// HEAD fallback remains ordinary staged + unstaged status. A
/// missing Git executable and a non-repository workspace both report
/// `repository=false`; once a repository is recognized, operational failures
/// are request errors rather than an ambiguous empty list.
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
/// One path's `HEAD` blob for quick diff. `Missing` is the legitimate baseline
/// for an added/untracked file or an unborn `HEAD`; withheld blobs mirror the
/// ordinary file reader's binary and one-megabyte policies.
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
