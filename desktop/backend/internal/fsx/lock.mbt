// Cross-process serialization for shared durable state. A host process is
// not the only writer of the registries under the session root and inside a
// workspace's store: a second window host, a headless server, and a build
// left over from a previous run all reach the same files. An `@async.Mutex`
// orders one process's own tasks and nothing else, so a read-modify-write
// that must not lose a concurrent update pairs one with the advisory file
// lock here.

///|
/// The advisory lock beside `path`. It is a sidecar rather than the data file
/// itself because an atomic save replaces the target by rename: a lock taken
/// on the data file would be attached to the inode that rename orphans, and
/// two writers would each hold "the lock" on a different file.
fn lock_file(path : @pathx.Path) -> @pathx.Path {
  path.dirname().join(path.basename().to_owned() + ".lock")
}

///|
/// An advisory lock on one shared file, held across processes until `release`.
/// It is acquired beside the `@async.Mutex` that orders this process's own
/// tasks, and in the same shape:
///
/// ```moonbit skip
/// registry_lock.acquire()
/// defer registry_lock.release()
/// let shared = @fsx.FileLock::acquire(registry_file)
/// defer shared.release()
/// ```
///
/// It must span a complete read-modify-write: the read has to happen after
/// the lock is granted, since a value read before it may already be stale. A
/// reader of a file saved by `write_text_atomic` needs no lock at all, which
/// is why there is no shared form.
///
/// The lock only orders writers that take it. Keeping unlocked readers safe
/// is `write_text_atomic`'s job: another tool, an older build, or a plain
/// `cat` never takes this lock and must still see a complete file.
struct FileLock {
  file : @fs.File
}

///|
/// Take the advisory lock guarding `path`, waiting for whichever process
/// holds it. Blocking is the point: a mutation that gave up here would be the
/// lost update the lock exists to prevent.
pub async fn FileLock::acquire(path : @pathx.Path) -> FileLock {
  // The lock precedes the data file: a first-run registry write creates the
  // directory itself, and there is nothing to open a lock in until it exists.
  ensure_dir(path.dirname())
  let file = open_lock_file(lock_file(path).to_string())
  // A wait interrupted by cancellation leaves the descriptor ours to close;
  // leaking it would also leak the lock for as long as the process lives.
  errdefer file.close()
  file.lock(Exclusive)
  { file, }
}

///|
/// Open the sidecar without being redirected by a link at its name. The
/// sidecar has to live beside the data file — every writer must agree on
/// where it is — and beside the data file can mean inside an attached
/// repository, which is free to ship its own `.openseek/worktrees.json.lock`.
///
/// A plain `OpenOrCreate` follows such a link twice over: it creates a file
/// wherever the link points, and it locks that inode instead, so two hosts
/// following a link that moved would each hold a lock on a different file and
/// both proceed into the registry write this exists to serialize.
///
/// `CreateNew` (O_CREAT|O_EXCL) never follows a link, so the create path is
/// closed outright. The already-exists path — the ordinary one — rejects
/// anything that is not a regular file by its own `lstat`. That leaves a
/// window for a link swapped in between the check and the open: closing it
/// needs `O_NOFOLLOW`, which this filesystem API does not expose. What it
/// does close is the case that gets here without an attacker present at the
/// keyboard, which is a link committed to a repository.
async fn open_lock_file(sidecar : String) -> @fs.File {
  let created = Some(
    @fs.open(sidecar, mode=ReadWrite, create_mode=CreateNew, permission=0o600),
  ) catch {
    _ => None
  }
  if created is Some(file) {
    return file
  }
  let regular = (@fs.kind(sidecar, follow_symlink=false) is Regular) catch {
    _ => false
  }
  guard regular else {
    fail("\{sidecar} is not a regular file; refusing to lock through it")
  }
  @fs.open(sidecar, mode=ReadWrite, create_mode=OpenExisting)
}

///|
pub fn FileLock::release(self : FileLock) -> Unit {
  self.file.unlock()
  self.file.close()
}
