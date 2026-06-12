///|
/// Stable identifier for a persisted OpenSeek conversation.
pub struct SessionId {
  priv value : String
} derive(Debug)

///|
/// Wrap a raw id string. The id doubles as the session's directory name in a
/// `SessionStore`, so it should be filesystem-safe on every platform.
pub fn SessionId::SessionId(value : String) -> SessionId {
  { value, }
}

///|
/// The raw id string, e.g. for display or for building a store path.
pub fn SessionId::value(self : SessionId) -> String {
  self.value
}

///|
/// Session id for a run that did not pick one: a UTC wall-clock stamp,
/// `<prefix>-YYYYMMDD-HHMMSS-mmm` (e.g. `cli-20260612-081500-042`), plus an
/// optional `-<salt>` tail.
///
/// The timestamp form keeps generated ids unique per launch, sorted
/// chronologically in `--session-list`, and valid as a directory name on
/// every platform. Launchers pass their own `prefix` ("tui", "cli") so a
/// listing shows where each conversation came from. A launcher that can
/// start several times in the same millisecond under one session root (the
/// headless CLI under a parallel driver) supplies `salt` — entropy that
/// keeps simultaneous runs from appending to each other's session.
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
/// User-authored model input for one conversational turn.
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
/// Wrap one user prompt as it was submitted, verbatim.
pub fn UserMessage::UserMessage(content : String) -> UserMessage {
  { content, }
}

///|
/// The prompt text exactly as the user submitted it.
pub fn UserMessage::content(self : UserMessage) -> String {
  self.content
}

///|
/// Assistant output returned by the model. Native DeepSeek tool calls are kept
/// in their typed protocol form so replay can preserve call ids and raw
/// argument strings exactly.
pub struct AssistantMessage {
  priv content : String
  priv tool_calls : Array[SessionToolCall]
  priv reasoning_content : String?
} derive(Debug, ToJson, FromJson)

///|
/// Build an assistant message from the model's response parts: the visible
/// `content`, any native `tool_calls` it requested, and the thinking-mode
/// `reasoning_content` when the API returned one. Tool calls are converted to
/// the session's own storage form so the event log has no wire-type
/// dependency.
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
/// The assistant's visible text — empty for turns that only requested tool
/// calls.
pub fn AssistantMessage::content(self : AssistantMessage) -> String {
  self.content
}

///|
/// The native tool calls the model requested this turn, in protocol form
/// (call id, name, raw argument string). Empty for a text-only response.
pub fn AssistantMessage::tool_calls(
  self : AssistantMessage,
) -> Array[@deepseek.ToolCall] {
  [
    for call in self.tool_calls => call.to_deepseek()
  ]
}

///|
/// The thinking-mode reasoning the model returned alongside its answer, or
/// `None` when the response carried no reasoning content.
pub fn AssistantMessage::reasoning_content(self : AssistantMessage) -> String? {
  self.reasoning_content
}

///|
/// Result returned by a local tool for one assistant tool call.
pub struct ToolResult {
  priv tool_call_id : String
  priv tool_name : String
  priv content : String
  priv is_error : Bool
} derive(Debug, ToJson, FromJson)

///|
/// Record the outcome of one tool execution: which assistant call it answers
/// (`tool_call_id`), which tool ran (`tool_name`), what it returned
/// (`content`), and whether that content is an error report rather than a
/// normal result.
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
/// Name of the tool that produced this result (e.g. `shell`, `edit`).
pub fn ToolResult::tool_name(self : ToolResult) -> String {
  self.tool_name
}

///|
/// The tool's output as it was fed back to the model — an error description
/// when `is_error` is true.
pub fn ToolResult::content(self : ToolResult) -> String {
  self.content
}

///|
/// Whether `content` reports a failure (bad arguments, command error) rather
/// than a normal result.
pub fn ToolResult::is_error(self : ToolResult) -> Bool {
  self.is_error
}

///|
/// Out-of-band runtime update that was surfaced to the model, such as a
/// `moon_check --watch` diagnostic batch.
pub struct RuntimeNotice {
  priv content : String
} derive(Debug, ToJson, FromJson)

///|
/// Wrap one runtime update exactly as it was injected into the conversation.
pub fn RuntimeNotice::RuntimeNotice(content : String) -> RuntimeNotice {
  { content, }
}

///|
/// The update text the model saw, including any watcher metadata preamble.
pub fn RuntimeNotice::content(self : RuntimeNotice) -> String {
  self.content
}

///|
/// Durable compaction of older session events. The `event_range` names the
/// inclusive source range summarized so future refactors can verify what was
/// compacted without depending on string parsing.
pub struct SessionSummary {
  priv content : String
  priv from_sequence : Int
  priv to_sequence : Int
} derive(Debug, ToJson, FromJson)

///|
/// Build a summary of the events `from_sequence..to_sequence` (inclusive).
/// Prefer `Session::compact`, which validates the range against the session
/// before appending.
pub fn SessionSummary::SessionSummary(
  content~ : String,
  from_sequence~ : Int,
  to_sequence~ : Int,
) -> SessionSummary {
  { content, from_sequence, to_sequence }
}

///|
/// The summary text that stands in for the compacted events in the
/// model-facing projection.
pub fn SessionSummary::content(self : SessionSummary) -> String {
  self.content
}

///|
/// First event sequence (inclusive) this summary covers.
pub fn SessionSummary::from_sequence(self : SessionSummary) -> Int {
  self.from_sequence
}

///|
/// Last event sequence (inclusive) this summary covers.
pub fn SessionSummary::to_sequence(self : SessionSummary) -> Int {
  self.to_sequence
}

///|
/// How a turn ended, with the payload a consumer shows for it: the final
/// answer for `Finished`, the reason for `Aborted` (the agent's own abort
/// tool) and `Interrupted` (cancelled from outside), or the failure message
/// for `Failed`. Every turn closes with exactly one of these, so a session
/// whose last event is not a `Terminal` was cut off mid-turn.
pub(all) enum TurnTerminal {
  Finished(String)
  Aborted(String)
  Interrupted(String)
  Failed(String)
} derive(Debug)

///|
/// One kind of session event payload — the conversation's vocabulary: the
/// user spoke (`User`), the model answered (`Assistant`), a tool returned
/// (`Tool`), the runtime injected diagnostics (`Runtime`), older events were
/// compacted (`Summary`), or the turn ended (`Terminal`).
pub(all) enum SessionItem {
  User(UserMessage)
  Assistant(AssistantMessage)
  Tool(ToolResult)
  Runtime(RuntimeNotice)
  Summary(SessionSummary)
  Terminal(TurnTerminal)
} derive(Debug)

///|
/// One append-only session event. Sequence numbers are one-based and monotonic
/// within a session.
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
/// This event's position in the session's append-only log (one-based).
pub fn SessionEvent::sequence(self : SessionEvent) -> Int {
  self.sequence
}

///|
/// The event's payload.
pub fn SessionEvent::item(self : SessionEvent) -> SessionItem {
  self.item
}

///|
/// When the event was appended (unix milliseconds), or 0 when it was created
/// without a clock (purely in-memory sessions; the durable store always
/// stamps).
pub fn SessionEvent::unix_ms(self : SessionEvent) -> Int64 {
  self.ts.to_int64()
}

///|
/// Immutable model of an OpenSeek conversation. Mutating operations return a new
/// `Session` backed by persistent event storage, so appending does not copy the
/// whole event log.
pub struct Session {
  priv id : SessionId
  priv system_prompt : String
  priv events : @vector.Vector[SessionEvent]
  priv last_sequence : Int
} derive(Debug)

///|
/// Build a session from its identity, system prompt, and (when loading from
/// storage) its existing event log. `last_sequence` is recovered from the
/// highest sequence present, so appending continues where the log left off.
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
/// The session's stable identifier.
pub fn Session::id(self : Session) -> SessionId {
  self.id
}

///|
/// The system prompt this conversation runs under, fixed at creation.
pub fn Session::system_prompt(self : Session) -> String {
  self.system_prompt
}

///|
/// The full append-only event log, oldest first.
pub fn Session::events(self : Session) -> @vector.Vector[SessionEvent] {
  self.events
}

///|
/// Sequence of the newest event, or `0` for a session with no events yet.
pub fn Session::last_sequence(self : Session) -> Int {
  self.last_sequence
}

///|
fn Session::next_sequence(self : Session) -> Int {
  self.last_sequence() + 1
}

///|
/// Append one item as the next event and return the new session value; the
/// receiver is unchanged. Callers that also need the assigned event (e.g. to
/// persist it) should use `append_event`.
pub fn Session::append(
  self : Session,
  item : SessionItem,
  unix_ms? : Int64 = 0,
) -> Session {
  let (next, _) = self.append_event(item, unix_ms~)
  next
}

///|
/// Append one item and return both the new session value and the event that was
/// appended. This lets durable stores write the new event without converting the
/// whole immutable vector back to an array.
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
/// Append a validated summary event that compacts a contiguous range of existing
/// events in model-facing projection while preserving those events in the
/// durable append-only log.
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
