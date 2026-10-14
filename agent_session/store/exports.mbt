// Deliberate exports with no in-repo production consumer (see
// shrink_package.md): test seams, round-trip/protocol surface, and
// future-proof API kept on purpose. Each entry documents its reason.

///|
/// Persist a complete session snapshot, replacing prior contents for its id.
///
/// `create` ensures the session directory exists, takes an exclusive lock, and
/// atomically rewrites `openseek_session-<id>.jsonl` (write to a temp file,
/// then rename). Use it for new sessions, fixtures, import tools, or deliberate
/// full rewrites. Do not use it for ordinary agent progress; `append`
/// preserves stale-snapshot detection and writes only one new event.
///
/// The call raises on invalid ids, filesystem errors, JSON encoding/write
/// failures, or lock failures.
pub async fn SessionStore::create(
  self : SessionStore,
  session : @agent_session.Session,
) -> Unit {
  ensure_session_dir(self, session.id())
  with_session_lock(self, session.id(), Exclusive, () => {
    write_text_atomic(
      self.session_file_path(session.id()),
      session_file_text(session),
      dirs=self.session_dir_chain(session.id()),
    )
    record_mark(self, session)
  })
}

///|
/// List known session ids under `root/sessions`, sorted by directory name.
///
/// This is a directory listing only. It does not open session files, parse
/// logs, or check loadability. A missing `root/sessions` directory returns an
/// empty array. Other filesystem errors raise. Returned ids are raw directory
/// names wrapped as `SessionId`.
pub async fn SessionStore::list(
  self : SessionStore,
) -> Array[@agent_session.SessionId] {
  let names = @fs.readdir(self.sessions_dir(), sort=true) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => []
    error => raise error
  }
  [
    for name in names if name != "." && name != ".." => SessionId(name)
  ]
}

///|
/// Return the root path passed to `SessionStore(root)`.
///
/// The returned string is not canonicalized. It may be relative or absolute,
/// and no filesystem check is performed by this accessor.
pub fn SessionStore::root(self : SessionStore) -> String {
  self.root
}
