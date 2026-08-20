///|
/// How the agent has touched a file during this session, as recorded by the
/// file-writing tools (`write`, `edit`, `multi_edit`). This is the public
/// *provenance* projection; the map stores a richer per-path record internally
/// (see `Entry`).
///
/// A consumer that gates deletion on `Created` must still confirm the file is
/// unchanged: a path can be rebound after it is recorded (a `git checkout` that
/// restores a tracked file the agent recreated, a `mv` onto a non-source path),
/// so `Created` alone proves only that the agent once created *a* file at this
/// path. Use `created_and_unchanged`, which pairs the provenance with a content
/// check, rather than `get(...) is Some(Created)`.
pub enum FileState {
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
/// The internal per-path record: provenance plus the file's identity — a
/// content digest of what the agent last wrote there.
///
/// Identity is a content DIGEST, not an `mtime`: the file-writing tools already
/// hold the content in memory, so the digest is computed synchronously (no stat,
/// no cancellation window) and cannot collide the way coarse-resolution or
/// `mv`-preserved mtimes can. It is a content *version*, not a filesystem object
/// id — a different file with byte-identical content passes, which is harmless
/// (deleting identical bytes is deleting the agent's own content). The digest
/// also lets an edit detect that the file was rebound before it ran (its
/// pre-edit content no longer matches what the agent last wrote).
priv struct Entry {
  provenance : FileState
  digest : String
}

///|
/// Per-session record of how the agent has touched files, keyed by the resolved
/// path the tools write to. One map is created per session (in `build_tools`)
/// and shared with every file-writing tool, which records into it, plus
/// `remove`, which reads it. `Map` is a reference type, so the shared handle
/// observes every tool's updates without a `Ref`.
///
/// Keys are the exact resolved path each tool wrote to — deliberately NOT
/// normalized or canonicalized. Unifying equivalent spellings or symlink aliases
/// correctly needs OS-level canonicalization (realpath); lexical normalization
/// instead MISattributes provenance. So this map under-approximates on purpose:
/// an unrecognized spelling reads as unknown, which a consumer treats
/// conservatively.
///
/// In-memory only: it reflects what THIS process did this session, not history
/// restored from a durable log. A file created in an earlier process (before a
/// resume) is absent, so consumers must read "absent" as "unknown provenance",
/// never as "not created".
pub struct FileStateMap {
  priv entries : Map[String, Entry]
}

///|
/// A fresh, empty session file-state map.
pub fn FileStateMap::new() -> FileStateMap {
  { entries: Map([]) }
}

///|
/// The content digest a file-writing tool records and `remove` revalidates — the
/// hex SHA-256 of `content`. Computed from the in-memory content the tool wrote
/// (or, for `remove`, the bytes it read back), so identity capture never stats
/// the filesystem and never races cancellation.
pub fn content_digest(content : String) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(content)))
}

///|
/// Record that the agent created `path` this session with content whose digest
/// is `digest`. Creation always wins over a later modify.
pub fn FileStateMap::record_created(
  self : FileStateMap,
  path : String,
  digest : String,
) -> Unit {
  self.entries[path] = { provenance: Created, digest }
}

///|
/// Record that the agent OVERWROTE `path` wholesale this session (a `write` over
/// an existing file), with the new content's `digest`. The whole file is now the
/// agent's content, so a path already recorded `Created` keeps that stronger
/// provenance; anything else becomes `Modified`. No continuity check is needed —
/// the overwrite replaced whatever was there.
pub fn FileStateMap::record_modified(
  self : FileStateMap,
  path : String,
  digest : String,
) -> Unit {
  let provenance = if self.entries.get(path)
    is Some({ provenance: Created, .. }) {
    Created
  } else {
    Modified
  }
  self.entries[path] = { provenance, digest }
}

///|
/// Record that the agent made a TARGETED edit to `path` (an `edit`/`multi_edit`
/// that preserved most of the file), where `seen_digest` is the digest of the
/// content the tool read just before editing and `result_digest` is the digest
/// of what it wrote. A `Created` path keeps that provenance only if `seen_digest`
/// still matches what the agent last wrote — otherwise the file was rebound to
/// different content before this edit, so most of the result is not the agent's
/// and it is downgraded to `Modified`.
pub fn FileStateMap::record_edited(
  self : FileStateMap,
  path : String,
  seen_digest : String,
  result_digest : String,
) -> Unit {
  let provenance = if self.entries.get(path)
    is Some({ provenance: Created, digest: stored }) &&
    stored == seen_digest {
    Created
  } else {
    Modified
  }
  self.entries[path] = { provenance, digest: result_digest }
}

///|
/// The recorded provenance of `path` this session, or `None` when no
/// file-writing tool has touched it (which a consumer must treat as "unknown",
/// not "pre-existing"). This is provenance only — it does NOT confirm the file
/// is still the one the agent wrote; use `created_and_unchanged` to gate a
/// destructive action.
pub fn FileStateMap::get(self : FileStateMap, path : String) -> FileState? {
  self.entries.get(path).map(entry => entry.provenance)
}

///|
/// Whether the agent created `path` this session AND the file there now still has
/// the content the agent last wrote — `current_digest` matches the recorded
/// digest. This is the gate `remove` uses (it hashes the bytes it reads back and
/// passes them here): it refuses when the path was never created by the agent or
/// when its content differs from what the agent wrote (rebound since).
pub fn FileStateMap::created_and_unchanged(
  self : FileStateMap,
  path : String,
  current_digest : String,
) -> Bool {
  self.entries.get(path) is Some({ provenance: Created, digest: stored }) &&
  stored == current_digest
}

///|
/// Drop any recorded state for `path`. `remove` calls this after deleting a file
/// so the provenance does not outlive the file: if the same path is later
/// recreated by something other than the agent's tools, it reads as unknown
/// again rather than as still-agent-created.
pub fn FileStateMap::forget(self : FileStateMap, path : String) -> Unit {
  self.entries.remove(path)
}

///|
test "record_created marks a path and survives a later overwrite" {
  let a = content_digest("fn a\n")
  let b = content_digest("fn b\n")
  let state = FileStateMap::new()
  state.record_created("lib/new.mbt", a)
  assert_true(state.get("lib/new.mbt") is Some(Created))
  // Overwriting a file the agent created keeps the creation provenance.
  state.record_modified("lib/new.mbt", b)
  assert_true(state.get("lib/new.mbt") is Some(Created))
  assert_true(state.created_and_unchanged("lib/new.mbt", b))
}

///|
test "record_modified marks a pre-existing file" {
  let state = FileStateMap::new()
  state.record_modified("lib/old.mbt", content_digest("x\n"))
  assert_true(state.get("lib/old.mbt") is Some(Modified))
}

///|
test "an untouched path has no recorded state" {
  let state = FileStateMap::new()
  assert_true(state.get("lib/absent.mbt") is None)
}

///|
test "created_and_unchanged holds only for a Created path with a matching digest" {
  let created = content_digest("v1\n")
  let other = content_digest("v2\n")
  let state = FileStateMap::new()
  state.record_created("lib/x.mbt", created)
  assert_true(state.created_and_unchanged("lib/x.mbt", created))
  // Different content means the file was rebound since the agent wrote it.
  assert_false(state.created_and_unchanged("lib/x.mbt", other))
}

///|
test "an edit keeps Created only when it saw the agent's own content" {
  let created = content_digest("original\n")
  let edited = content_digest("edited\n")
  let foreign = content_digest("someone else\n")
  let after_foreign = content_digest("someone else + edit\n")
  // Normal edit: the tool read back the agent's own content, so Created holds.
  let ok = FileStateMap::new()
  ok.record_created("a.mbt", created)
  ok.record_edited("a.mbt", created, edited)
  assert_true(ok.get("a.mbt") is Some(Created))
  assert_true(ok.created_and_unchanged("a.mbt", edited))
  // Rebound-then-edited: the tool read foreign content (not what the agent
  // wrote), so Created is downgraded and the file is no longer deletable.
  let rebound = FileStateMap::new()
  rebound.record_created("a.mbt", created)
  rebound.record_edited("a.mbt", foreign, after_foreign)
  assert_true(rebound.get("a.mbt") is Some(Modified))
  assert_false(rebound.created_and_unchanged("a.mbt", after_foreign))
}

///|
test "created_and_unchanged is false for a modified or untouched path" {
  let d = content_digest("x\n")
  let state = FileStateMap::new()
  state.record_modified("lib/pre.mbt", d)
  assert_false(state.created_and_unchanged("lib/pre.mbt", d))
  assert_false(state.created_and_unchanged("lib/absent.mbt", d))
}

///|
test "forget drops a path's provenance" {
  let state = FileStateMap::new()
  state.record_created("lib/gone.mbt", content_digest("x\n"))
  state.forget("lib/gone.mbt")
  assert_true(state.get("lib/gone.mbt") is None)
}

///|
test "handles share one underlying map (no Ref needed)" {
  let a = FileStateMap::new()
  let b = a
  b.record_created("lib/shared.mbt", content_digest("x\n"))
  assert_true(a.get("lib/shared.mbt") is Some(Created))
}

///|
test "distinct path spellings are distinct keys (a safe under-approximation)" {
  // The map keys verbatim — it never canonicalizes — so an equivalent spelling
  // reads as unknown rather than risk reporting a different file as
  // agent-created. Canonicalization (realpath) is the deletion consumer's job.
  let state = FileStateMap::new()
  state.record_created("./note.txt", content_digest("x\n"))
  assert_true(state.get("./note.txt") is Some(Created))
  assert_true(state.get("note.txt") is None)
}

///|
#deprecated
pub extend FileState with Debug::{to_repr}

///|
pub extend FileState with Eq::{equal, not_equal}
