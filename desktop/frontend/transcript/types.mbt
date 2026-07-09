// The display-ready forms of what the engine reports: transcript entries,
// sidebar session entries, and parsed runtime updates. The decoders in this
// package produce them from the host's wire data; the app's update and view
// construct and consume them freely, so the types are fully public.

///|
pub(all) enum ItemKind {
  User
  Assistant(Bool)
  Reasoning
  // A tool call's result: the tool name, whether it failed, and the tool's
  // optional one-line human-readable summary of what the call did (`None`
  // when the tool supplied none — display falls back to the name).
  Tool(name~ : String, is_error~ : Bool, brief~ : String?)
  // A compaction checkpoint: the turns before it were summarized into the
  // item's content and dropped from the context. Its own kind so the view
  // renders it as a standalone card — folded into a turn's activity it
  // would read as an anonymous tool call and swallow the preceding answer
  // bubble into the fold.
  Summary
}

///|
pub(all) struct TranscriptItem {
  kind : ItemKind
  content : String
}

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
/// the project directory whose store holds the session ("" for a scratch
/// conversation) and `workspace_name` its display label, both from the
/// host's grouping.
pub(all) struct SessionListItem {
  id : String
  title : String?
  workspace : String
  workspace_name : String
}
