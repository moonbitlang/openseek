///|
/// How the agent has touched a file during this session, as recorded by the
/// file-writing tools (`write`, `edit`, `multi_edit`).
///
/// This is an ADVISORY provenance signal, keyed by path, not a capability. A
/// consumer that gates deletion on `Created` must NOT treat it as sole
/// authority: a path can be rebound after it is recorded (the sandboxed shell
/// still permits `mv`/`rm` on non-source files, and a session spans many
/// turns), so `Created` proves only that the agent once created *a* file at
/// this path — not that the file there now is still that file. A safe consumer
/// revalidates at delete time (the path still refers to the agent's file) and
/// combines this with independent guards (e.g. only deleting git-tracked or
/// recoverable/soft-deleted files), treating `Created` as necessary, not
/// sufficient.
pub(all) enum FileState {
  /// The agent created this file this session — a `write` to a path that did
  /// not exist. Editing it afterward keeps this state; it is still the agent's
  /// own file.
  Created
  /// The agent modified a file that already existed when it first touched it
  /// this session — an `edit`/`multi_edit`, or a `write` overwriting a
  /// pre-existing non-source file.
  Modified
} derive(Eq, Debug)

///|
/// Per-session record of how the agent has touched files, keyed by the resolved
/// path the tools write to. One map is created per session (in `build_tools`)
/// and shared with every file-writing tool, which records into it, plus
/// `remove`, which reads it. `Map` is a reference type, so the shared handle
/// observes every tool's updates without a `Ref`.
///
/// Keys are lexically normalized (`./a`, `a//b`, `x/../y` collapse) so a file
/// recorded under one spelling is found under an equivalent one — the tools'
/// `workspace_path.resolve` leaves paths unnormalized under the default `.`
/// root, so `note.txt` and `./note.txt` would otherwise be distinct keys.
/// Normalization is lexical only: symlink aliases still map to distinct keys, a
/// gap a consumer closes by canonicalizing (realpath) at delete time.
///
/// In-memory only: it reflects what THIS process did this session, not history
/// restored from a durable log. A file created in an earlier process (before a
/// resume) is absent, so consumers must read "absent" as "unknown provenance",
/// never as "not created".
pub struct FileStateMap {
  priv entries : Map[String, FileState]
}

///|
/// A fresh, empty session file-state map.
pub fn FileStateMap::new() -> FileStateMap {
  { entries: Map([]) }
}

///|
/// The lexically normalized key for `path`, so equivalent spellings of one file
/// (`a`, `./a`, `dir/../a`) share an entry. Lexical only — it does not touch the
/// filesystem, so it does not resolve symlink aliases.
fn normalize_key(path : String) -> String {
  @path.Path(path).normalize().to_string()
}

///|
/// Record that the agent created `path` this session. Creation always wins: a
/// later `record_modified` will not downgrade a `Created` entry.
pub fn FileStateMap::record_created(self : FileStateMap, path : String) -> Unit {
  self.entries[normalize_key(path)] = Created
}

///|
/// Record that the agent modified `path` this session — unless it is already
/// `Created`, since editing a file the agent itself created keeps the stronger
/// creation provenance.
pub fn FileStateMap::record_modified(
  self : FileStateMap,
  path : String,
) -> Unit {
  let key = normalize_key(path)
  if self.entries.get(key) is Some(Created) {
    return
  }
  self.entries[key] = Modified
}

///|
/// The recorded state of `path` this session, or `None` when no file-writing
/// tool has touched it (which a consumer must treat as "unknown", not
/// "pre-existing").
pub fn FileStateMap::get(self : FileStateMap, path : String) -> FileState? {
  self.entries.get(normalize_key(path))
}

///|
test "record_created marks a path and survives a later modify" {
  let state = FileStateMap::new()
  state.record_created("lib/new.mbt")
  assert_true(state.get("lib/new.mbt") is Some(Created))
  // Editing a file the agent created keeps the creation provenance.
  state.record_modified("lib/new.mbt")
  assert_true(state.get("lib/new.mbt") is Some(Created))
}

///|
test "record_modified marks a pre-existing file" {
  let state = FileStateMap::new()
  state.record_modified("lib/old.mbt")
  assert_true(state.get("lib/old.mbt") is Some(Modified))
}

///|
test "an untouched path has no recorded state" {
  let state = FileStateMap::new()
  assert_true(state.get("lib/absent.mbt") is None)
}

///|
test "record_created overrides a prior modified" {
  // A path first seen as modified then created (e.g. removed and rewritten)
  // becomes Created — creation is the stronger signal.
  let state = FileStateMap::new()
  state.record_modified("lib/x.mbt")
  state.record_created("lib/x.mbt")
  assert_true(state.get("lib/x.mbt") is Some(Created))
}

///|
test "handles share one underlying map (no Ref needed)" {
  let a = FileStateMap::new()
  let b = a
  b.record_created("lib/shared.mbt")
  assert_true(a.get("lib/shared.mbt") is Some(Created))
}

///|
test "equivalent path spellings resolve to the same entry" {
  // resolve() leaves paths verbatim under the default `.` root, so without
  // normalization these would be distinct keys for the same file.
  let state = FileStateMap::new()
  state.record_created("./lib/x.mbt")
  assert_true(state.get("lib/x.mbt") is Some(Created))
  // A later modify through a third spelling must still find the Created entry.
  state.record_modified("lib/./x.mbt")
  assert_true(state.get("lib/x.mbt") is Some(Created))
}
