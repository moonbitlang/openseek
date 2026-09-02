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
  // A durable checkpoint copy of an answer already owned by an earlier model
  // step. It renders as normal assistant prose but never starts another step.
  AssistantReplay
  // The final visible answer confirmed by a durable Finished terminal. The
  // terminal may carry new text or confirm that the preceding Assistant text
  // is final; either shape becomes this kind so the view can distinguish a
  // turn-ending answer from tool-prefacing assistant narration.
  TerminalAnswer
  Reasoning
  // One tool call in its original assistant-message order. `call_id` pairs the
  // later durable result into this same item instead of adding a second row;
  // `arguments` is `Some` for a recorded call and `None` for an unmatched
  // legacy result. `has_result` distinguishes a
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
  // renders it as a standalone card — batched into a turn's activity it
  // would read as an anonymous tool call row and swallow the preceding
  // answer bubble into the step's group.
  Summary
  // A runtime notice the engine injected between turns — a background-job
  // completion, or a legacy `moon_check` block from an older record. Stands
  // alone in the transcript, never batched into a step's activity.
  Notice
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
pub extend SessionListItem with Eq::{equal, not_equal}

///|
pub extend TranscriptItem with Eq::{equal, not_equal}
