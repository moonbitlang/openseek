///|
/// Stable identifier for one OpenSeek conversation.
///
/// `SessionId` is stored in every `Session` and is also used by
/// `agent_session/store` as the directory name under `root/sessions/<id>/`.
/// This type deliberately stores the raw string without normalizing or
/// validating it; store APIs validate filesystem safety before constructing
/// paths. Use `generated` for ids created by OpenSeek itself.
pub struct SessionId {
  priv value : String
} derive(Debug)

///|
/// Wrap a raw id string exactly as supplied.
///
/// This constructor does not reject empty strings, path separators, `"."`, or
/// `".."`. That is intentional: `agent_session` is a pure typed model and does
/// not know which storage backend will consume the id. Filesystem-backed
/// callers should expect `SessionStore` methods to raise for ids that are not
/// safe directory names.
pub fn SessionId::SessionId(value : String) -> SessionId {
  { value, }
}

///|
/// Return the raw id string.
///
/// The returned value is suitable for display, CLI flags, JSON, or passing back
/// to another `SessionId` constructor. It is not escaped for paths or shells.
pub fn SessionId::value(self : SessionId) -> String {
  self.value
}

///|
/// Generate an id for a new run that did not receive an explicit id.
///
/// The normal format is:
///
/// ```text
/// <prefix>-YYYYMMDD-HHMMSS-mmm[-<salt>]
/// ```
///
/// `now_ms` is interpreted as unix milliseconds and rendered in UTC. The
/// timestamp keeps generated ids sortable in ordinary string order and readable
/// in `--session-list`. `prefix` lets launchers identify the source, such as
/// `"cli"` or `"tui"`. `salt` is appended only when non-empty; use it when a
/// caller can start multiple sessions in the same millisecond under one store
/// root.
///
/// If `now_ms` cannot be represented as a date, the fallback is
/// `<prefix>-<now_ms>[-<salt>]`. This preserves uniqueness and directory-name
/// friendliness even with an absurd system clock.
pub fn SessionId::generated(
  prefix~ : String,
  now_ms~ : Int64,
  salt? : String = "",
) -> SessionId {
  fn pad2(value : Int) -> String {
    if value < 10 {
      "0\{value}"
    } else {
      "\{value}"
    }
  }

  fn pad3(value : Int) -> String {
    if value < 10 {
      "00\{value}"
    } else if value < 100 {
      "0\{value}"
    } else {
      "\{value}"
    }
  }

  let tail = if salt == "" { "" } else { "-\{salt}" }
  let time = @time.unix(now_ms / 1000) catch {
    // A wall clock unrepresentable as a date (absurd system time): the raw
    // millisecond count still yields a unique, valid directory name.
    _ => return SessionId("\{prefix}-\{now_ms}\{tail}")
  }
  SessionId(
    "\{prefix}-\{time.year()}\{pad2(time.month())}\{pad2(time.day())}-\{pad2(time.hour())}\{pad2(time.minute())}\{pad2(time.second())}-\{pad3((now_ms % 1000).to_int())}\{tail}",
  )
}

///|
/// User-authored model input for one conversational event.
///
/// A `UserMessage` is durable data, not a UI transcript item. It records the
/// exact text that should be replayed as a user-role message in
/// `Session::chat_messages`.
pub struct UserMessage {
  priv content : String
} derive(Debug, ToJson, FromJson)

///|
priv struct SessionToolCall {
  id : String
  name : String
  arguments : String
} derive(Debug, ToJson, FromJson)

///|
fn SessionToolCall::from_deepseek(call : @deepseek.ToolCall) -> SessionToolCall {
  { id: call.id, name: call.name, arguments: call.arguments }
}

///|
fn SessionToolCall::to_deepseek(self : SessionToolCall) -> @deepseek.ToolCall {
  ToolCall(id=self.id, name=self.name, arguments=self.arguments)
}

///|
/// Wrap one user prompt exactly as supplied.
///
/// The constructor does not trim, normalize, or reject empty content. Empty
/// messages are preserved because they may be meaningful to a caller or test.
pub fn UserMessage::UserMessage(content : String) -> UserMessage {
  { content, }
}

///|
/// Return the prompt text exactly as stored.
pub fn UserMessage::content(self : UserMessage) -> String {
  self.content
}

///|
/// Assistant output returned by the model for one event.
///
/// This stores visible assistant text, requested tool calls, and optional
/// reasoning content. Tool calls are durable because later `ToolResult` events
/// must match their call ids during `Session::chat_messages` projection.
pub struct AssistantMessage {
  priv content : String
  priv tool_calls : Array[SessionToolCall]
  priv reasoning_content : String?
} derive(Debug, ToJson, FromJson)

///|
/// Build an assistant event payload from model response parts.
///
/// `content` is the visible assistant text and may be empty when the model only
/// requested tools. `tool_calls` are copied from DeepSeek protocol values into
/// the session storage form so ids, names, and raw argument strings survive
/// JSON round-tripping. `reasoning_content` is stored only when the provider
/// returned it.
pub fn AssistantMessage::AssistantMessage(
  content : String,
  tool_calls? : Array[@deepseek.ToolCall] = [],
  reasoning_content? : String,
) -> AssistantMessage {
  {
    content,
    tool_calls: [
      for call in tool_calls => SessionToolCall::from_deepseek(call)
    ],
    reasoning_content,
  }
}

///|
/// Return the assistant's visible text.
///
/// This may be empty for tool-only responses. Callers should use `tool_calls`
/// to distinguish a useful tool request from an empty text-only response.
pub fn AssistantMessage::content(self : AssistantMessage) -> String {
  self.content
}

///|
/// Return the native tool calls requested by this assistant event.
///
/// Each call contains the durable call id, tool name, and raw argument string.
/// The returned array is rebuilt from the stored representation, so mutating it
/// does not mutate the `AssistantMessage`.
pub fn AssistantMessage::tool_calls(
  self : AssistantMessage,
) -> Array[@deepseek.ToolCall] {
  [
    for call in self.tool_calls => call.to_deepseek()
  ]
}

///|
/// Return provider reasoning content, if any.
///
/// `None` means the provider did not return reasoning content. `Some("")`
/// means it returned an explicitly empty reasoning field.
pub fn AssistantMessage::reasoning_content(self : AssistantMessage) -> String? {
  self.reasoning_content
}

///|
/// Result returned by a local tool for one assistant tool call.
///
/// During model projection, a `ToolResult` is emitted only when its
/// `tool_call_id` matches a pending assistant tool call. Unmatched results are
/// ignored to keep replay protocol-valid.
pub struct ToolResult {
  priv tool_call_id : String
  priv tool_name : String
  priv content : String
  priv is_error : Bool
} derive(Debug, ToJson, FromJson)

///|
/// Record the outcome of one tool execution.
///
/// `tool_call_id` must be the id from the assistant tool call this result
/// answers. `tool_name` is retained for diagnostics and listing/debug output.
/// `content` is exactly what will be replayed to the model. `is_error`
/// classifies the content for callers, but the DeepSeek projection currently
/// sends the same text shape either way.
pub fn ToolResult::ToolResult(
  tool_call_id~ : String,
  tool_name~ : String,
  content~ : String,
  is_error? : Bool = false,
) -> ToolResult {
  { tool_call_id, tool_name, content, is_error }
}

///|
fn ToolResult::tool_call_id(self : ToolResult) -> String {
  self.tool_call_id
}

///|
/// Return the tool name that produced this result.
///
/// This is metadata; protocol matching uses `tool_call_id`, not `tool_name`.
pub fn ToolResult::tool_name(self : ToolResult) -> String {
  self.tool_name
}

///|
/// Return the tool output that will be replayed to the model.
///
/// When `is_error` is true, this string is the error report rather than a
/// successful result.
pub fn ToolResult::content(self : ToolResult) -> String {
  self.content
}

///|
/// Return whether `content` reports a tool failure.
pub fn ToolResult::is_error(self : ToolResult) -> Bool {
  self.is_error
}

///|
/// Out-of-band runtime update surfaced to the model.
///
/// Runtime notices are projected as user-role messages. They are intended for
/// process state such as watcher diagnostics, steering messages, or other
/// context that did not originate from the user's prompt text.
pub struct RuntimeNotice {
  priv content : String
} derive(Debug, ToJson, FromJson)

///|
/// Wrap one runtime update exactly as it should be replayed.
pub fn RuntimeNotice::RuntimeNotice(content : String) -> RuntimeNotice {
  { content, }
}

///|
/// Return the runtime update text.
pub fn RuntimeNotice::content(self : RuntimeNotice) -> String {
  self.content
}

///|
/// Durable compaction record for older session events.
///
/// A summary does not delete the covered raw events. It records that
/// `from_sequence..to_sequence` can be replaced by `content` when projecting
/// model context. The durable event log remains append-only.
pub struct SessionSummary {
  priv content : String
  priv from_sequence : Int
  priv to_sequence : Int
} derive(Debug, ToJson, FromJson)

///|
/// Build a summary for an inclusive event sequence range.
///
/// This constructor stores the values exactly as supplied and does not validate
/// that the range is non-empty, positive, or present in a session. Prefer
/// `Session::compact` when creating a summary event for a real session because
/// it validates content and range before appending.
pub fn SessionSummary::SessionSummary(
  content~ : String,
  from_sequence~ : Int,
  to_sequence~ : Int,
) -> SessionSummary {
  { content, from_sequence, to_sequence }
}

///|
/// Return the summary text used in model-facing projection.
pub fn SessionSummary::content(self : SessionSummary) -> String {
  self.content
}

///|
/// Return the first covered event sequence, inclusive.
pub fn SessionSummary::from_sequence(self : SessionSummary) -> Int {
  self.from_sequence
}

///|
/// Return the last covered event sequence, inclusive.
pub fn SessionSummary::to_sequence(self : SessionSummary) -> Int {
  self.to_sequence
}

///|
/// How an agent turn ended.
///
/// `Finished` carries the final assistant answer. `Aborted` carries the
/// agent's own abort reason. `Interrupted` carries an external cancellation
/// reason. `Failed` carries the failure message. In a complete turn, the last
/// event is exactly one `Terminal`; if a session ends without one, replay is
/// seeing a turn that was cut off mid-flight.
pub(all) enum TurnTerminal {
  Finished(String)
  Aborted(String)
  Interrupted(String)
  Failed(String)
} derive(Debug)

///|
/// Payload vocabulary for one `SessionEvent`.
///
/// `User` and `Runtime` project as user-role model messages. `Assistant`
/// projects as an assistant message and may open pending tool calls. `Tool`
/// answers a pending assistant tool call. `Summary` is append-only compaction
/// metadata that can replace older events during projection. `Terminal`
/// records turn completion status and may project as a final assistant/status
/// message.
pub(all) enum SessionItem {
  User(UserMessage)
  Assistant(AssistantMessage)
  Tool(ToolResult)
  Runtime(RuntimeNotice)
  Summary(SessionSummary)
  Terminal(TurnTerminal)
} derive(Debug)

///|
/// One append-only event in a session log.
///
/// Sequence numbers are one-based within a session and are assigned by
/// `Session::append_event`. The durable store rejects non-contiguous sequences
/// when loading from disk. The timestamp is unix milliseconds; in-memory
/// appends default to `0`, while `SessionStore::append` stamps with the current
/// wall clock.
pub struct SessionEvent {
  priv sequence : Int
  // Wall-clock stamp (unix milliseconds) of when the event was appended; 0
  // for purely in-memory sessions appended without a clock (the durable
  // store always stamps). The field is named for its wire key, and typed
  // Double so it serializes as a JSON number (core encodes Int64 as a
  // string); milliseconds are exactly representable until year ~2255.
  priv ts : Double
  priv item : SessionItem
} derive(Debug, ToJson, FromJson)

///|
fn SessionEvent::SessionEvent(
  sequence~ : Int,
  item~ : SessionItem,
  unix_ms? : Int64 = 0,
) -> SessionEvent {
  { sequence, ts: unix_ms.to_double(), item }
}

///|
/// Return this event's one-based position in the session log.
pub fn SessionEvent::sequence(self : SessionEvent) -> Int {
  self.sequence
}

///|
/// Return this event's payload.
pub fn SessionEvent::item(self : SessionEvent) -> SessionItem {
  self.item
}

///|
/// Return when the event was appended, as unix milliseconds.
///
/// A value of `0` means the event was created without a clock, which is the
/// default for pure in-memory `Session::append` and `append_event` calls. The
/// filesystem store always passes a real wall-clock timestamp.
pub fn SessionEvent::unix_ms(self : SessionEvent) -> Int64 {
  self.ts.to_int64()
}

///|
/// Immutable model of one OpenSeek conversation.
///
/// A `Session` owns the stable id, fixed system prompt, append-only event log,
/// and cached `last_sequence`. Operations that add events return a new
/// `Session`; the receiver is unchanged. Internally the event log is an
/// immutable vector, so appending shares existing structure instead of copying
/// the whole history.
pub struct Session {
  priv id : SessionId
  priv system_prompt : String
  priv events : @vector.Vector[SessionEvent]
  priv last_sequence : Int
} derive(Debug)

///|
/// Build a session from identity, system prompt, and an optional event log.
///
/// `id` is stored exactly as supplied. `system_prompt` becomes the first system
/// message in `chat_messages` and is not changed by append operations. `events`
/// is used as-is; this constructor does not check contiguity or sort events.
/// `last_sequence` is recovered as the highest sequence number present, so the
/// next append uses `last_sequence + 1`.
pub fn Session::Session(
  id : SessionId,
  system_prompt~ : String,
  events? : @vector.Vector[SessionEvent] = @vector.new(),
) -> Session {
  let mut last_sequence = 0
  for event in events {
    if event.sequence > last_sequence {
      last_sequence = event.sequence
    }
  }
  { id, system_prompt, events, last_sequence }
}

///|
/// Return this session's stable identifier.
pub fn Session::id(self : Session) -> SessionId {
  self.id
}

///|
/// Return the fixed system prompt for this conversation.
pub fn Session::system_prompt(self : Session) -> String {
  self.system_prompt
}

///|
/// Return the full append-only event log, oldest first.
///
/// The returned immutable vector is the durable source of truth. Model-facing
/// compaction is applied by `chat_messages`, not by removing events here.
pub fn Session::events(self : Session) -> @vector.Vector[SessionEvent] {
  self.events
}

///|
/// Return the sequence number that will precede the next append.
///
/// This is the highest event sequence present, or `0` when the session has no
/// events. It is the value used by `SessionStore` to detect stale in-memory
/// snapshots before appending.
pub fn Session::last_sequence(self : Session) -> Int {
  self.last_sequence
}

///|
fn Session::next_sequence(self : Session) -> Int {
  self.last_sequence() + 1
}

///|
/// Append one item as the next event and return the new session value.
///
/// The receiver is unchanged. The new event gets sequence
/// `self.last_sequence() + 1`. `unix_ms` defaults to `0`; pass a wall-clock
/// value when constructing durable events yourself. Callers that also need the
/// assigned `SessionEvent` should use `append_event`.
pub fn Session::append(
  self : Session,
  item : SessionItem,
  unix_ms? : Int64 = 0,
) -> Session {
  let (next, _) = self.append_event(item, unix_ms~)
  next
}

///|
/// Append one item and return both the new session and the assigned event.
///
/// The returned event is exactly the event pushed into the returned session.
/// Durable stores use this to append one JSONL line without reserializing the
/// whole immutable vector. The receiver is unchanged.
pub fn Session::append_event(
  self : Session,
  item : SessionItem,
  unix_ms? : Int64 = 0,
) -> (Session, SessionEvent) {
  let event = SessionEvent(sequence=self.next_sequence(), item~, unix_ms~)
  (
    {
      id: self.id,
      system_prompt: self.system_prompt,
      events: self.events.push(event),
      last_sequence: event.sequence,
    },
    event,
  )
}

///|
/// Append a validated summary event for an existing event range.
///
/// `content` must not be blank after trimming. `from_sequence` must be
/// positive. `to_sequence` must be at least `from_sequence` and must not exceed
/// the current `last_sequence`. On success, this appends a `Summary` item as the
/// next event and returns the new session. It does not remove or rewrite any
/// covered raw events; `chat_messages` applies the compaction during projection.
pub fn Session::compact(
  self : Session,
  content~ : String,
  from_sequence~ : Int,
  to_sequence~ : Int,
  unix_ms? : Int64 = 0,
) -> Session raise {
  if content.trim().is_empty() {
    fail("summary content must not be empty")
  }
  if from_sequence <= 0 {
    fail("summary from_sequence must be positive")
  }
  if to_sequence < from_sequence {
    fail("summary to_sequence must be >= from_sequence")
  }
  let last = self.last_sequence()
  if to_sequence > last {
    fail(
      "summary range \{from_sequence}..\{to_sequence} exceeds last sequence \{last}",
    )
  }
  self.append(
    Summary(SessionSummary(content~, from_sequence~, to_sequence~)),
    unix_ms~,
  )
}
