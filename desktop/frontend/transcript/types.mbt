// The display-ready forms of what the engine reports: transcript entries,
// sidebar session entries, and runtime notices. The decoders in this
// package produce them from the host's wire data; the app's update and view
// construct and consume them freely, so the types are fully public.

///|
/// What one transcript item is, text included. An item is one durable session
/// event (or one client-local bubble) kept in the shape the event had: a
/// provider response stays one `Assistant` item carrying its reasoning and
/// tool calls, so the view never has to reassemble a model step from adjacent
/// rows. Each kind carries only the text it can have, so a part that may be
/// absent (a response's prose, a notice's body) is an option, never an empty
/// string.
pub(all) enum ItemKind {
  User(String)
  // One provider response. `reasoning` is the thinking that preceded the
  // prose, `prose` what the model said (absent for a tool-only response), and
  // `calls` the tool calls that followed it, in the model's own order.
  // `replay` marks a checkpoint copy of an answer an earlier response already
  // owns: it renders as prose but never counts as a model step. `finished`
  // marks the answer a durable Finished terminal confirmed as the turn's
  // final one, which is what earns it the copy action and completion stamp.
  Assistant(
    reasoning~ : String?,
    prose~ : String?,
    calls~ : Array[ToolCall],
    replay~ : Bool,
    finished~ : Bool
  )
  // A turn's final answer carried by a Finished terminal whose text is not
  // the preceding response's prose: a completion-tool answer, or the
  // context-ceiling guidance.
  Answer(String)
  // A turn that ended without an answer — an abort/cancel/failure terminal —
  // or a notice the frontend raised itself. It wears the assistant's bubble
  // but renders as plain red text, never markdown: an error's own `*` and
  // `#` are not formatting.
  Failure(String)
  // A durable runtime notice with a display presence: a goal marker, or an
  // engine notice injected between turns. `label` names the family (`goal`,
  // `runtime notice`), `brief` is the one-line caption a notice folds to,
  // `is_error` marks a blocked goal, and `body` is what a multi-line notice
  // expands to.
  Notice(label~ : String, brief~ : String?, is_error~ : Bool, body~ : String?)
  // A compaction checkpoint: the turns before it were summarized into this
  // text and dropped from the context. Its own kind so the view renders it
  // as a standalone card between turns.
  Summary(String)
} derive(Eq)

///|
/// One tool call of a provider response, in its original order. `call_id`
/// pairs the later durable result into this same call; `arguments` is what
/// the model sent (a Codex file change can carry none).
pub(all) struct ToolCall {
  call_id : String
  name : String
  arguments : String?
  outcome : ToolOutcome
} derive(Eq)

///|
/// Where a tool call stands. A call is `Pending` until its durable result
/// lands; a Codex command can stream `output` while still pending. `Done`
/// carries the result — its content may legitimately be empty — with the
/// error flag and the display brief the result came with.
pub(all) enum ToolOutcome {
  Pending(output~ : String?)
  Done(content~ : String, is_error~ : Bool, brief~ : String?)
} derive(Eq)

///|
pub(all) struct TranscriptItem {
  kind : ItemKind
  // When the durable event that produced this item was committed (unix
  // milliseconds, as the store stamps it). `None` for a client-local bubble
  // that never became a durable event, and for records written before the
  // store stamped them — the view simply shows no time for those.
  ts : Double?
  // The durable event sequence this item came from, `None` for a client-local
  // item. One event projects to at most one item, so the sequence is the
  // item's stable identity.
  sequence : Int?
} derive(Eq)

///|
/// The item's own text, when it has one: a user prompt, a response's prose,
/// an answer, a failure, a notice body, or a summary. A response that only
/// thought or only called tools has none.
pub fn TranscriptItem::text(self : TranscriptItem) -> String? {
  match self.kind {
    User(text) | Answer(text) | Failure(text) | Summary(text) => Some(text)
    Assistant(prose~, ..) => prose
    Notice(body~, ..) => body
  }
}

///|
/// One sidebar entry from the engine's durable session list: the session id
/// and its display title (first user message, already truncated engine-side;
/// blank or absent for a session with no user message yet). `workspace` is
/// the project resource whose store holds the session and `workspace_name`
/// its display label, both from the host's grouping. Every durable record
/// lives in a workspace store, so the resource is not optional; its
/// authority retains the device that owns the path.
pub(all) struct SessionListItem {
  id : String
  title : String?
  workspace : @common.Uri
  workspace_name : String
  // Engine last-activity stamp (session file mtime, milliseconds). `None`
  // for a damaged directory the engine could not stat; such rows keep their
  // listing but sort after stamped ones, same as the engine's own ordering.
  updated_at_ms : Double?
} derive(Eq)

///|
pub extend ItemKind with Eq::{equal, not_equal}

///|
pub extend ToolCall with Eq::{equal, not_equal}

///|
pub extend ToolOutcome with Eq::{equal, not_equal}

///|
pub extend SessionListItem with Eq::{equal, not_equal}

///|
pub extend TranscriptItem with Eq::{equal, not_equal}
