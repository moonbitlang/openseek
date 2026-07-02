// The display-ready forms of what the engine reports: transcript entries,
// sidebar session entries, and parsed runtime updates. The decoders in this
// package produce them from the host's wire data; the app's update and view
// construct and consume them freely, so the types are fully public.

///|
pub(all) enum ItemKind {
  User
  Assistant(Bool)
  Reasoning
  Tool(String, Bool)
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
/// empty for a session with no user message yet). `workspace` is the project
/// directory whose store holds the session ("" for a scratch conversation)
/// and `workspace_name` its display label, both from the host's grouping.
pub(all) struct SessionListItem {
  id : String
  title : String
  workspace : String
  workspace_name : String
}

///|
/// `value`, unless it is blank — then `fallback`. The engine's wire fields
/// are free text; this is the one normalization rule for display labels.
pub fn non_empty_or(value : String, fallback : String) -> String {
  if value.trim().is_empty() {
    fallback
  } else {
    value
  }
}
