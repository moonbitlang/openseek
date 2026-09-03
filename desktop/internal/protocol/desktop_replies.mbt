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
/// The result of one `agent.start`.
///
/// `run_id` names the turn this call opened. Every reply that returns names
/// one — the host does not deduplicate a resent `submission_id`, and a start
/// that opens no turn raises instead. A client that resends a prompt it could
/// not confirm risks a second copy of the text; read the record first.
pub(all) struct StartReply {
  run_id : String
  status : String
  exit_code : Int
} derive(Debug, Eq, FromJson, ToJson)

///|
/// The run the cancellation reached, absent when no turn was open. Absence is
/// an answer rather than a failure — a Stop racing a turn that just ended
/// wanted the run over, and it is. A cancel that could not be delivered
/// raises instead.
pub(all) struct CancelReply {
  run_id : String?
} derive(Debug, Eq)

///|
/// Omitted rather than `null` when there was nothing to cancel: the key's
/// absence is the answer, and a reader that only checks for the key sees the
/// same thing as one that inspects its value.
pub impl ToJson for CancelReply with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  if self.run_id is Some(run_id) {
    fields["run_id"] = Json(run_id)
  }
  Json(fields)
}

///|
/// Every shape that is not a run id reads as "no run was cancelled" —
/// missing, `null`, and a non-string alike. There is nothing to be strict
/// about: the field is optional by design, and a reply this host cannot spell
/// is not worth failing a Stop over.
pub impl FromJson for CancelReply with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected a cancel reply"))
  }
  {
    run_id: match fields.get("run_id") {
      Some(String(run_id)) => Some(run_id)
      _ => None
    },
  }
}

///|
pub(all) struct SteerReply {
  steered : Bool
  run_id : String?
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct QueueReply {
  accepted : Bool
} derive(Debug, Eq)

///|
pub impl FromJson for QueueReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "queue reply")
  { accepted: object.required_bool("accepted"), }
}

///|
pub impl ToJson for QueueReply with fn to_json(self) {
  { "accepted": self.accepted }
}

///|
pub(all) struct ApprovalReply {
  // Whether the decision reached a live engine that could still be waiting
  // for it. False means the question is already gone — the turn that asked it
  // ended — so the run this decision would have resumed is over. Nothing
  // behind the question times out; that is not one of the ways this is false.
  delivered : Bool
} derive(Debug, Eq)

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
/// One reconnect-safe completion returned by `agent.runs`. It answers "how
/// did this run I own end", so the three fields that establish that — the
/// run, the conversation it belonged to, and its outcome — are required; a
/// row missing any of them cannot be matched against a caller's selectors
/// and is refused instead of half-applied. `submission_id` is present only
/// for a run whose Started carried one, and `exit_code` only for a run whose
/// process exited, so both read absent, `null` and a wrong-typed value alike
/// as "not reported".
pub(all) struct RunSettlementPayload {
  run_id : String
  session : String
  submission_id : String?
  status : String
  exit_code : Int?
} derive(Debug, Eq)

///|
pub impl ToJson for RunSettlementPayload with fn to_json(self) {
  let fields = {
    "run_id": Json(self.run_id),
    "session": Json(self.session),
    "status": Json(self.status),
  }
  if self.submission_id is Some(submission_id) {
    fields["submission_id"] = Json(submission_id)
  }
  if self.exit_code is Some(exit_code) {
    fields["exit_code"] = Json(exit_code.to_double())
  }
  Json(fields)
}

///|
pub impl FromJson for RunSettlementPayload with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected run settlement payload"))
  }
  guard fields.get("run_id") is Some(String(run_id)) else {
    raise JsonDecodeError((path.add_key("run_id"), "expected a run id"))
  }
  guard fields.get("session") is Some(String(session)) else {
    raise JsonDecodeError((path.add_key("session"), "expected a session id"))
  }
  guard fields.get("status") is Some(String(status)) else {
    raise JsonDecodeError((path.add_key("status"), "expected a run status"))
  }
  {
    run_id,
    session,
    status,
    submission_id: match fields.get("submission_id") {
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
/// One permission question a live engine is currently blocked on, replayed to
/// a client that joins or rejoins while it stands.
///
/// An approval request is a live event, not durable state: the transcript is
/// rebuilt from the session record and approvals were never in it, so a
/// reloaded frontend recovers everything about a turn EXCEPT the question
/// holding it up. The host outlives that reload and is the only party that
/// still knows, which is why this rides the same snapshot `agent.runs` already
/// uses to tell a rejoining client what is in flight.
pub(all) struct PendingApprovalPayload {
  /// The id the decision must carry back. Reused verbatim on replay: a
  /// rejoining client answers the same question, not a new one.
  id : String
  session : String
  run_id : String?
  tool_name : String
  detail : String
  /// What would run. Absent for an asker with nothing to show.
  body : String?
} derive(Debug, Eq)

///|
pub(all) struct RunsReply {
  runs : Array[StartedPayload]
  settled : Array[RunSettlementPayload]
  /// Questions still waiting for an answer. Empty for a host with none, and
  /// for every engine that never asks.
  approvals : Array[PendingApprovalPayload]
} derive(Debug, Eq)

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
  { id, title, updated_at_ms, }
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
/// A durable user prompt as the store recorded it.
///
/// `submission_id` mirrors the durable `UserMessage` tag: the submitting
/// controller's id for this prompt, echoed from the serve `prompt` command,
/// or None for untagged input (steers, TUI and one-shot prompts, and every
/// record written before the field existed). It is what lets a delivery be
/// reconciled by exact id instead of by matching text, since two clients can
/// submit identical text into one session.
pub(all) struct SessionUserMessage {
  content : String
  submission_id : String?
} derive(Debug, Eq)

///|
/// Omit an absent tag rather than writing `null`, matching what the store
/// itself writes: an untagged prompt is byte for byte the line every record
/// held before the field existed.
pub impl ToJson for SessionUserMessage with fn to_json(self) {
  let fields = { "content": Json(self.content) }
  if self.submission_id is Some(submission_id) {
    fields["submission_id"] = Json(submission_id)
  }
  Json(fields)
}

///|
/// `content` is the message; a record without it is not one, and refusing is
/// how `SessionItem` learns to keep the raw line as `Unknown`.
///
/// The tag is a correlation hint, never the message. Missing, `null`, or a
/// value that is not a string all mean "untagged" — the same answer a record
/// written before the field existed gives. Refusing there would drop a user's
/// prompt out of the transcript over an annotation nothing renders, and the
/// enclosing `SessionItem` decoder would swallow the refusal as `Unknown`
/// rather than surface it. Unknown fields are ignored: a newer store may
/// annotate a prompt in ways this client has no reason to understand.
pub impl FromJson for SessionUserMessage with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected a user message"))
  }
  guard fields.get("content") is Some(String(content)) else {
    raise JsonDecodeError((path.add_key("content"), "expected message content"))
  }
  let submission_id = if fields.get("submission_id") is Some(String(value)) {
    Some(value)
  } else {
    None
  }
  { content, submission_id, }
}

///|
pub(all) struct SessionAssistantMessage {
  content : String
  tool_calls : Array[SessionToolCall]?
  reasoning_content : String?
  is_replay : Bool?
} derive(Debug, Eq)

///|
/// Preserve the store's compact assistant payload: optional fields are absent
/// rather than null, and replay provenance appears only on checkpoint copies.
pub impl ToJson for SessionAssistantMessage with fn to_json(self) {
  let fields = { "content": Json(self.content) }
  if self.tool_calls is Some(tool_calls) {
    fields["tool_calls"] = ToJson::to_json(tool_calls)
  }
  if self.reasoning_content is Some(reasoning_content) {
    fields["reasoning_content"] = Json(reasoning_content)
  }
  if self.is_replay is Some(is_replay) {
    fields["is_replay"] = Json(is_replay)
  }
  Json(fields)
}

///|
/// Content is required. Tool calls are functional protocol data, so a present
/// malformed list rejects the payload rather than silently dropping calls.
/// Reasoning and replay provenance are optional annotations; malformed values
/// do not hide otherwise readable assistant prose.
pub impl FromJson for SessionAssistantMessage with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected an assistant message"))
  }
  guard fields.get("content") is Some(String(content)) else {
    raise JsonDecodeError((path.add_key("content"), "expected message content"))
  }
  let tool_calls = match fields.get("tool_calls") {
    None | Some(Null) => None
    Some(value) => Some(@json.from_json(value, path=path.add_key("tool_calls")))
  }
  let reasoning_content = if fields.get("reasoning_content")
    is Some(String(value)) {
    Some(value)
  } else {
    None
  }
  let is_replay = match fields.get("is_replay") {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
  { content, tool_calls, reasoning_content, is_replay, }
}

///|
pub(all) struct SessionToolResult {
  tool_call_id : String
  tool_name : String
  content : String
  is_error : Bool
  brief : String?
} derive(Debug, Eq)

///|
/// Optional display annotations are omitted when absent, matching the durable
/// store's compact wire shape. Unknown fields are not copied back: this encoder
/// owns only the fields this client understands.
pub impl ToJson for SessionToolResult with fn to_json(self) {
  let fields = {
    "tool_call_id": Json(self.tool_call_id),
    "tool_name": Json(self.tool_name),
    "content": Json(self.content),
    "is_error": Json(self.is_error),
  }
  if self.brief is Some(brief) {
    fields["brief"] = Json(brief)
  }
  Json(fields)
}

///|
/// The four core fields identify and carry a tool result, so missing, `null`,
/// or malformed values reject the payload and let `SessionItem` preserve the
/// raw event as `Unknown`.
///
/// `brief` is an annotation. Missing, `null`, or malformed values all mean
/// "not annotated": refusing it would hide an otherwise valid durable tool
/// result. Unknown fields are ignored for forward compatibility with newer
/// stores.
pub impl FromJson for SessionToolResult with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected a tool result"))
  }
  guard fields.get("tool_call_id") is Some(String(tool_call_id)) else {
    raise JsonDecodeError(
      (path.add_key("tool_call_id"), "expected tool call id"),
    )
  }
  guard fields.get("tool_name") is Some(String(tool_name)) else {
    raise JsonDecodeError((path.add_key("tool_name"), "expected tool name"))
  }
  guard fields.get("content") is Some(String(content)) else {
    raise JsonDecodeError(
      (path.add_key("content"), "expected tool result content"),
    )
  }
  let is_error = match fields.get("is_error") {
    Some(True) => true
    Some(False) => false
    _ =>
      raise JsonDecodeError(
        (path.add_key("is_error"), "expected tool result error flag"),
      )
  }
  let brief = if fields.get("brief") is Some(String(value)) {
    Some(value)
  } else {
    None
  }
  { tool_call_id, tool_name, content, is_error, brief, }
}

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
/// The destination selected by the native save dialog. `None` means the user
/// closed the dialog without saving. `opened` reports whether the saved file
/// was handed to the platform opener; it stays false when nothing was saved.
pub(all) struct SessionExportReply {
  path : String?
  opened : Bool
} derive(Debug, Eq)

///|
/// Missing and null paths both mean that the save dialog was cancelled.
/// `opened` is required because omitting it would make a saved-but-not-opened
/// result indistinguishable from an incomplete reply. Unknown fields are
/// ignored for forward evolution.
pub impl FromJson for SessionExportReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session export reply")
  {
    path: object.optional_string("path"),
    opened: object.required_bool("opened"),
  }
}

///|
/// An absent path is omitted rather than encoded as null, matching the other
/// optional Desktop reply fields.
pub impl ToJson for SessionExportReply with fn to_json(self) {
  let fields : Map[String, Json] = { "opened": Json(self.opened) }
  if self.path is Some(path) {
    fields["path"] = Json(path)
  }
  Json(fields)
}

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
  let object = JsonObject::of(fields, path)
  let name = object.required_string("name")
  let branch = object.required_string("branch")
  let base = object.required_string("base")
  let session = object.optional_string("session")
  let codex_thread = object.optional_string("codex_thread")
  if session is Some(_) && codex_thread is Some(_) {
    raise JsonDecodeError(
      (path, "worktree cannot belong to both session and codex_thread"),
    )
  }
  let object = JsonObject::of(fields, path)
  let checkout_path = object.required_string("path")
  let present = object.required_bool("present")
  { name, branch, base, session, codex_thread, path: checkout_path, present, }
}

///|
pub impl ToJson for WorktreeInfo with fn to_json(self) {
  let fields : Map[String, Json] = {
    "name": Json(self.name),
    "branch": Json(self.branch),
    "base": Json(self.base),
    "path": Json(self.path),
    "present": Json(self.present),
  }
  if self.session is Some(session) {
    fields["session"] = Json(session)
  }
  if self.codex_thread is Some(thread_id) {
    fields["codex_thread"] = Json(thread_id)
  }
  Json(fields)
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
/// Result of asking the host file manager to show a referenced path. A
/// refusal remains data so the frontend can display the host's exact reason
/// instead of the bridge's generic endpoint failure.
pub(all) enum RevealPathReply {
  Revealed
  RevealRefused(String)
} derive(Debug, Eq)

///|
pub impl ToJson for RevealPathReply with fn to_json(self) {
  match self {
    Revealed => { "revealed": true }
    RevealRefused(message) => { "revealed": false, "error": message }
  }
}

///|
pub impl FromJson for RevealPathReply with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "expected a reveal_path reply"))
  }
  match fields.get("revealed") {
    Some(True) => Revealed
    Some(False) =>
      match fields.get("error") {
        Some(String(message)) => RevealRefused(message)
        _ =>
          raise JsonDecodeError(
            (path.add_key("error"), "reveal_path refusal must name an error"),
          )
      }
    _ => raise JsonDecodeError((path, "reveal_path reply names no outcome"))
  }
}

///|
pub(all) struct ApplyUpdateReply {
  applied : Bool
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
/// One named ref selected for the Review graph. `kind` is `current`,
/// `upstream`, `base`, or `head`; revisions are always full commit identities.
pub(all) struct GitHistoryRef {
  name : String
  revision : String
  kind : String
} derive(Debug, Eq)

///|
/// The immutable ref selection shared by every page of one graph read.
pub(all) struct GitHistorySnapshot {
  head : String?
  branch : String?
  refs : Array[GitHistoryRef]
  tips : Array[String]
} derive(Debug, Eq)

///|
/// One commit row. Parent identities are sufficient for the frontend to draw
/// the graph lanes without asking Git for presentation-specific topology.
pub(all) struct GitHistoryCommit {
  id : String
  parent_ids : Array[String]
  subject : String
  author : String
  authored_at : String
} derive(Debug, Eq)

///|
pub(all) struct GitHistoryReply {
  repository : Bool
  snapshot : GitHistorySnapshot
  commits : Array[GitHistoryCommit]
  has_more : Bool
} derive(Debug, Eq)

///|
/// One historical path change. Status and tree-object kind stay independent:
/// a renamed symlink is still a rename, while `kind` keeps it out of text Diff.
pub(all) struct GitHistoricalChange {
  path : String
  original_path : String?
  status : String
  kind : String
} derive(Debug, Eq)

///|
pub(all) struct GitCommitChangesReply {
  commit : String
  parent : String?
  changes : Array[GitHistoricalChange]
} derive(Debug, Eq)

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
/// One match range within the source line. Columns are one-based UTF-16
/// code-unit offsets and the end is exclusive, matching the editor Viewer
/// contract.
pub(all) struct TextSearchRange {
  start_column : Int
  end_column : Int
} derive(Debug, Eq)

///|
/// A matching source line. `path` is relative to the searched root;
/// `preview_start_column` maps a clipped preview back onto the source line.
pub(all) struct TextSearchMatch {
  path : String
  line_number : Int
  preview : String
  preview_start_column : Int
  ranges : Array[TextSearchRange]
} derive(Debug, Eq)

///|
/// A text-search failure carried inside the successful bridge response. Keeping
/// code and message together makes a half-populated wire error impossible to
/// construct inside the Host or frontend.
pub(all) struct TextSearchError {
  code : String
  message : String
} derive(Debug, Eq)

///|
/// A complete bounded text-search response. Operational failures stay in the
/// typed reply so the Search panel can distinguish invalid regexes, missing
/// bundled assets, permissions, and ordinary errors without failing unrelated
/// bridge methods. Success omits both optional error fields on the wire.
pub(all) struct SearchTextReply {
  root : String
  generation : Int
  matches : Array[TextSearchMatch]
  match_count : Int
  file_count : Int
  limit_hit : Bool
  cancelled : Bool
  error : TextSearchError?
} derive(Debug, Eq)

///|
/// One source line from a semantic-search hit's surrounding context.
/// `line`/`is_match` mirror moongrep's `source_context` entries; `text` has a
/// single trailing `\r` stripped so Windows CRLF files render cleanly.
pub(all) struct SemanticContextLine {
  line : Int
  text : String
  is_match : Bool
} derive(Debug, Eq)

///|
/// One structural match reported by moongrep. `path` is workspace-relative and
/// slash-separated like a text-search row. `rule_id` is the anonymous CLI
/// pattern or the loaded YAML rule id; `description` is absent for the
/// anonymous pattern, which has no rule description. The range is the matched
/// node's one-based line/column extent; `matched_source` is the matched source
/// with `\n` line endings; `source_context` is moongrep's +/-2-line window.
pub(all) struct SemanticSearchHit {
  path : String
  rule_id : String
  description : String?
  start_line : Int
  start_column : Int
  end_line : Int
  end_column : Int
  matched_source : String
  source_context : Array[SemanticContextLine]
} derive(Debug, Eq)

///|
/// A semantic-search failure carried inside the successful bridge response,
/// mirroring `TextSearchError`.
pub(all) struct SemanticSearchError {
  code : String
  message : String
} derive(Debug, Eq)

///|
/// A complete bounded semantic-search response, shaped like `SearchTextReply`
/// so the Search panel treats both modes uniformly. Success omits both
/// optional error fields on the wire.
pub(all) struct SearchSemanticReply {
  root : String
  generation : Int
  matches : Array[SemanticSearchHit]
  match_count : Int
  file_count : Int
  limit_hit : Bool
  cancelled : Bool
  partial : Bool
  error : SemanticSearchError?
} derive(Debug, Eq)

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
/// One `fs.stat_files` outcome. `Present` carries the opaque mtime signature
/// `"{seconds}:{nanos}"`; `Missing` is a path that does not resolve to a file;
/// `Failed` is every other stat error with the host's message. The three stay
/// distinct on the wire so a file the host cannot inspect never reads as one
/// that is gone.
pub(all) enum FileSignature {
  Missing
  Present(String)
  Failed(String)
} derive(Debug, Eq)

///|
pub impl ToJson for FileSignature with fn to_json(self) {
  match self {
    Missing => { "kind": "missing" }
    Present(sig) => { "kind": "present", "sig": sig }
    Failed(message) => { "kind": "failed", "message": message }
  }
}

///|
pub impl FromJson for FileSignature with fn from_json(json, path) {
  guard json is Object(fields) && fields.get("kind") is Some(String(kind_)) else {
    raise JsonDecodeError((path, "expected file signature"))
  }
  match kind_ {
    "missing" => Missing
    "present" => {
      guard fields.get("sig") is Some(String(sig)) else {
        raise JsonDecodeError((path.add_key("sig"), "expected string"))
      }
      Present(sig)
    }
    "failed" => {
      guard fields.get("message") is Some(String(message)) else {
        raise JsonDecodeError((path.add_key("message"), "expected string"))
      }
      Failed(message)
    }
    _ =>
      raise JsonDecodeError(
        (path.add_key("kind"), "unknown file signature kind"),
      )
  }
}

///|
pub(all) struct FileStat {
  path : String
  signature : FileSignature
} derive(Debug, Eq)

///|
pub impl ToJson for FileStat with fn to_json(self) {
  { "path": self.path, "signature": self.signature.to_json() }
}

///|
pub impl FromJson for FileStat with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "file stat")
  {
    path: object.required_string("path"),
    signature: @json.from_json(
      object.required_json("signature"),
      path=path.add_key("signature"),
    ),
  }
}

///|
pub(all) struct StatFilesReply {
  stats : Array[FileStat]
} derive(Debug, Eq)

///|
pub impl ToJson for StatFilesReply with fn to_json(self) {
  { "stats": self.stats }
}

///|
pub impl FromJson for StatFilesReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "stat files reply")
  let stats : Array[FileStat] = []
  for index, raw in object.required_array("stats") {
    stats.push(
      @json.from_json(raw, path=path.add_key("stats").add_index(index)),
    )
  }
  { stats, }
}

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
      Json(fields)
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
  id : String
} derive(Debug, Eq)

///|
pub impl FromJson for TerminalOpenReply with fn from_json(json, path) {
  guard json is Object(fields) && fields.get("id") is Some(String(id)) else {
    raise JsonDecodeError((path, "expected terminal open reply"))
  }
  { id, }
}

///|
pub impl ToJson for TerminalOpenReply with fn to_json(self) {
  { "id": self.id }
}

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
/// The two reference actions emitted by the supported Moon IDE CodeLens
/// command. `position` remains zero-based LSP coordinates. Local locations
/// have already been canonicalized by the host and carry the navigation
/// protocol's one-based numeric ranges.
pub(all) enum MoonIdeCodeLensAction {
  Local(position~ : LspPosition, locations~ : Array[MoonIdeLocation])
  Outside(position~ : LspPosition)
} derive(Debug, Eq)

///|
pub impl ToJson for MoonIdeCodeLensAction with fn to_json(self) {
  match self {
    Local(position~, locations~) =>
      { "kind": "local", "position": position, "locations": locations }
    Outside(position~) => { "kind": "outside", "position": position }
  }
}

///|
pub impl FromJson for MoonIdeCodeLensAction with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "Moon IDE CodeLens action")
  let position : LspPosition = @json.from_json(
    object.required_json("position"),
    path=path.add_key("position"),
  )
  match object.required_string("kind") {
    "local" => {
      let locations : Array[MoonIdeLocation] = @json.from_json(
        object.required_json("locations"),
        path=path.add_key("locations"),
      )
      Local(position~, locations~)
    }
    "outside" => Outside(position~)
    _ =>
      raise JsonDecodeError(
        (path.add_key("kind"), "unknown Moon IDE CodeLens action kind"),
      )
  }
}

///|
/// One source CodeLens. Its anchor range and action position retain Moon
/// IDE's zero-based LSP coordinates until the Viewer provider projects them.
pub(all) struct MoonIdeCodeLens {
  range : LspRange
  title : String
  action : MoonIdeCodeLensAction
} derive(Debug, Eq, FromJson, ToJson)

///|
pub(all) struct MoonIdeCodeLensReply {
  lenses : Array[MoonIdeCodeLens]
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
        ("kind", Json("available")),
        ("version", Json(version)),
        ("installable", Json(installable)),
      ])
      if unavailable_reason is Some(reason) {
        fields["unavailable_reason"] = Json(reason)
      } else {
        fields["unavailable_reason"] = Json::null()
      }
      Json(fields)
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
    fields["submission_id"] = Json(submission_id)
    return Json(fields)
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
  { event, submission_id, }
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
      Some({ ..self, event: ReasoningMessage(content=""), })
    AssistantMessage(..) =>
      Some({ ..self, event: AssistantMessage(content=""), })
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
pub extend ApplyUpdateReply with Debug::{to_repr}

///|
pub extend ApplyUpdateReply with FromJson::{from_json}

///|
pub extend ApplyUpdateReply with Eq::{equal, not_equal}

///|
pub extend ApplyUpdateReply with ToJson::{to_json}

///|
pub extend ApprovalReply with Debug::{to_repr}

///|
pub extend ApprovalReply with FromJson::{from_json}

///|
pub extend ApprovalReply with Eq::{equal, not_equal}

///|
pub extend ApprovalReply with ToJson::{to_json}

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
pub extend FileSignature with Debug::{to_repr}

///|
pub extend FileSignature with FromJson::{from_json}

///|
pub extend FileSignature with Eq::{equal, not_equal}

///|
pub extend FileSignature with ToJson::{to_json}

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
pub extend GitCommitChangesReply with Debug::{to_repr}

///|
pub extend GitCommitChangesReply with FromJson::{from_json}

///|
pub extend GitCommitChangesReply with Eq::{equal, not_equal}

///|
pub extend GitCommitChangesReply with ToJson::{to_json}

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
pub extend GitHistoricalChange with Debug::{to_repr}

///|
pub extend GitHistoricalChange with FromJson::{from_json}

///|
pub extend GitHistoricalChange with Eq::{equal, not_equal}

///|
pub extend GitHistoricalChange with ToJson::{to_json}

///|
pub extend GitHistoryCommit with Debug::{to_repr}

///|
pub extend GitHistoryCommit with FromJson::{from_json}

///|
pub extend GitHistoryCommit with Eq::{equal, not_equal}

///|
pub extend GitHistoryCommit with ToJson::{to_json}

///|
pub extend GitHistoryRef with Debug::{to_repr}

///|
pub extend GitHistoryRef with FromJson::{from_json}

///|
pub extend GitHistoryRef with Eq::{equal, not_equal}

///|
pub extend GitHistoryRef with ToJson::{to_json}

///|
pub extend GitHistoryReply with Debug::{to_repr}

///|
pub extend GitHistoryReply with FromJson::{from_json}

///|
pub extend GitHistoryReply with Eq::{equal, not_equal}

///|
pub extend GitHistoryReply with ToJson::{to_json}

///|
pub extend GitHistorySnapshot with Debug::{to_repr}

///|
pub extend GitHistorySnapshot with FromJson::{from_json}

///|
pub extend GitHistorySnapshot with Eq::{equal, not_equal}

///|
pub extend GitHistorySnapshot with ToJson::{to_json}

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
pub extend LoadSessionReply with Debug::{to_repr}

///|
pub extend LoadSessionReply with FromJson::{from_json}

///|
pub extend LoadSessionReply with Eq::{equal, not_equal}

///|
pub extend LoadSessionReply with ToJson::{to_json}

///|
pub extend SessionExportReply with Debug::{to_repr}

///|
pub extend SessionExportReply with FromJson::{from_json}

///|
pub extend SessionExportReply with Eq::{equal, not_equal}

///|
pub extend SessionExportReply with ToJson::{to_json}

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
pub extend MoonIdeCodeLensAction with Debug::{to_repr}

///|
pub extend MoonIdeCodeLensAction with FromJson::{from_json}

///|
pub extend MoonIdeCodeLensAction with Eq::{equal, not_equal}

///|
pub extend MoonIdeCodeLensAction with ToJson::{to_json}

///|
pub extend MoonIdeCodeLens with Debug::{to_repr}

///|
pub extend MoonIdeCodeLens with FromJson::{from_json}

///|
pub extend MoonIdeCodeLens with Eq::{equal, not_equal}

///|
pub extend MoonIdeCodeLens with ToJson::{to_json}

///|
pub extend MoonIdeCodeLensReply with Debug::{to_repr}

///|
pub extend MoonIdeCodeLensReply with FromJson::{from_json}

///|
pub extend MoonIdeCodeLensReply with Eq::{equal, not_equal}

///|
pub extend MoonIdeCodeLensReply with ToJson::{to_json}

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
pub extend PendingApprovalPayload with Debug::{to_repr}

///|
pub extend PendingApprovalPayload with FromJson::{from_json}

///|
pub extend PendingApprovalPayload with Eq::{equal, not_equal}

///|
pub extend PendingApprovalPayload with ToJson::{to_json}

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
pub extend SearchTextReply with Debug::{to_repr}

///|
pub extend SearchTextReply with FromJson::{from_json}

///|
pub extend SearchTextReply with Eq::{equal, not_equal}

///|
pub extend SearchTextReply with ToJson::{to_json}

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
pub extend QueueReply with Debug::{to_repr}

///|
pub extend QueueReply with FromJson::{from_json}

///|
pub extend QueueReply with Eq::{equal, not_equal}

///|
pub extend QueueReply with ToJson::{to_json}

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
pub extend TextSearchError with Debug::{to_repr}

///|
pub extend TextSearchError with Eq::{equal, not_equal}

///|
pub extend TextSearchMatch with Debug::{to_repr}

///|
pub extend TextSearchMatch with FromJson::{from_json}

///|
pub extend TextSearchMatch with Eq::{equal, not_equal}

///|
pub extend TextSearchMatch with ToJson::{to_json}

///|
pub extend TextSearchRange with Debug::{to_repr}

///|
pub extend TextSearchRange with FromJson::{from_json}

///|
pub extend TextSearchRange with Eq::{equal, not_equal}

///|
pub extend TextSearchRange with ToJson::{to_json}

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

///|
pub extend SearchSemanticReply with Debug::{to_repr}

///|
pub extend SearchSemanticReply with FromJson::{from_json}

///|
pub extend SearchSemanticReply with Eq::{equal, not_equal}

///|
pub extend SearchSemanticReply with ToJson::{to_json}

///|
pub extend SemanticContextLine with Debug::{to_repr}

///|
pub extend SemanticContextLine with FromJson::{from_json}

///|
pub extend SemanticContextLine with Eq::{equal, not_equal}

///|
pub extend SemanticContextLine with ToJson::{to_json}

///|
pub extend SemanticSearchError with Debug::{to_repr}

///|
pub extend SemanticSearchError with FromJson::{from_json}

///|
pub extend SemanticSearchError with Eq::{equal, not_equal}

///|
pub extend SemanticSearchError with ToJson::{to_json}

///|
pub extend SemanticSearchHit with Debug::{to_repr}

///|
pub extend SemanticSearchHit with FromJson::{from_json}

///|
pub extend SemanticSearchHit with Eq::{equal, not_equal}

///|
pub extend SemanticSearchHit with ToJson::{to_json}

///|
pub extend RevealPathReply with Debug::{to_repr}

///|
pub extend RevealPathReply with FromJson::{from_json}

///|
pub extend RevealPathReply with Eq::{equal, not_equal}

///|
pub extend RevealPathReply with ToJson::{to_json}
