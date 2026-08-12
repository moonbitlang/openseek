// The display-ready forms of what the engine reports: transcript entries,
// sidebar session entries, and parsed runtime updates. The decoders in this
// package produce them from the host's wire data; the app's update and view
// construct and consume them freely, so the types are fully public.

///|
pub(all) enum ItemKind {
  User
  // Something the agent said. `is_danger` marks the ones that aren't a reply
  // at all — an abort/cancel/failure terminal, or a notice the frontend
  // raised itself. They wear the assistant's bubble but render as plain red
  // text, never markdown: an error's own `*` and `#` are not formatting.
  Assistant(is_danger~ : Bool)
  Reasoning
  // One tool call in its original assistant-message order. `call_id` pairs the
  // later durable result into this same item instead of adding a second row;
  // `arguments` is `Some` for a recorded call and `None` for an unmatched
  // legacy result or a synthetic runtime update. `has_result` distinguishes a
  // pending call from a completed call even when the legitimate result has
  // empty content, `is_error=false`, and no brief.
  Tool(
    call_id~ : String,
    name~ : String,
    arguments~ : String?,
    has_result~ : Bool,
    is_error~ : Bool,
    brief~ : String?
  )
  // A compaction checkpoint: the turns before it were summarized into the
  // item's content and dropped from the context. Its own kind so the view
  // renders it as a standalone card — folded into a turn's activity it
  // would read as an anonymous tool call and swallow the preceding answer
  // bubble into the fold.
  Summary
} derive(Eq)

///|
pub(all) struct TranscriptItem {
  kind : ItemKind
  content : String
  // When the durable event that produced this item was committed (unix
  // milliseconds, as the store stamps it). `None` for a client-local bubble
  // that never became a durable event, and for records written before the
  // store stamped them — the view simply shows no time for those.
  ts : Double?
  // The durable event sequence this row came from, `None` for a client-local
  // row. One event can append several rows (reasoning, answer, tool calls),
  // which then share its sequence — but at most one of them is a User row,
  // so the sequence is a stable identity for a user turn.
  sequence : Int?
} derive(Eq)

///|
/// One live sub-run shown at the tail of its owning transcript. Progress is
/// absent until the child has written a durable record; `run` prevents a lane
/// stranded by a lost finish notification from leaking into a later turn.
pub(all) struct SubrunLane {
  id : String
  kind : String
  label : String
  steps : Int
  activity : String
  run : String?
} derive(Eq)

///|
/// A `runtime_update` notice split into the watcher's status and the
/// diagnostic lines worth showing.
pub struct RuntimeUpdateView {
  status : String
  diagnostics : Array[String]
}

///|
/// One sidebar entry from the engine's durable session list: the session id
/// and its display title (first user message, already truncated engine-side;
/// blank or absent for a session with no user message yet). `workspace` is
/// the project resource whose store holds the session (`None` for a scratch
/// conversation) and `workspace_name` its display label, both from the
/// host's grouping. Its authority retains the device that owns the path.
pub(all) struct SessionListItem {
  id : String
  title : String?
  workspace : @common.Uri?
  workspace_name : String
} derive(Eq)
