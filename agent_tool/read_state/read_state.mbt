///|
/// Session-scoped record of which workspace files the agent has already seen
/// this run — read, written, or edited. `write` consults it to flag when it
/// overwrites a file the agent never read, so a wholesale replacement of unseen
/// content is at least visible in the transcript.
///
/// It is ephemeral runtime state shared across the file tools, never persisted:
/// a resumed session starts empty, which fails safe (the agent is nudged to
/// read before overwriting). Keys are the already-resolved paths the tools
/// operate on — each tool resolves `arguments.path` under the workspace root
/// before recording or checking — so the same file maps to the same key across
/// tools.
///
/// This deliberately tracks only "seen vs not seen", not modification times:
/// the "file changed since you read it" check is for editors/linters touching
/// files concurrently, which does not happen in a single batch CLI session.
pub struct ReadState {
  seen : Map[String, Unit]
}

///|
/// A fresh, empty seen-set. The agent loop creates one per session and hands it
/// to the read/write/edit tools.
pub fn ReadState::ReadState() -> ReadState {
  { seen: {} }
}

///|
/// Record that the agent has seen `path` (call after a successful read, write,
/// or edit). Idempotent.
pub fn ReadState::record(self : ReadState, path : String) -> Unit {
  self.seen[path] = ()
}

///|
/// Whether `path` has been read, written, or edited this session.
pub fn ReadState::has_seen(self : ReadState, path : String) -> Bool {
  self.seen.get(path) is Some(_)
}
