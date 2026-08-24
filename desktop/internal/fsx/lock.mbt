// Cross-process serialization for shared durable state. This process is not
// the only writer of the files under the session root and the runtime
// directory: a second desktop instance, a TUI launched in the same workspace,
// and a leftover process from a previous run all reach the same registries. An
// `@async.Mutex` orders this process's own tasks and nothing else, so a
// read-modify-write that must not lose a concurrent update pairs one with the
// advisory file lock here.

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
/// let shared = @fsx.FileLock::acquire(registry_file, Exclusive)
/// defer shared.release()
/// ```
///
/// `Exclusive` must span a complete read-modify-write: the read has to happen
/// after the lock is granted, since a value read before it may already be
/// stale. `Shared` covers a read that must not overlap a mutation — a reader
/// of a file saved by `write_text_atomic` needs no lock at all.
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
pub async fn FileLock::acquire(path : @pathx.Path, kind : @fs.Lock) -> FileLock {
  // The lock precedes the data file: a first-run registry write creates the
  // directory itself, and there is nothing to open a lock in until it exists.
  ensure_dir(path.dirname())
  let file = open_lock_file(lock_file(path).to_string())
  // A wait interrupted by cancellation leaves the descriptor ours to close;
  // leaking it would also leak the lock for as long as the process lives.
  errdefer file.close()
  file.lock(kind)
  { file, }
}

///|
/// Open the sidecar without being redirected by a link at its name. The
/// sidecar has to live beside the data file — every writer, this app or a
/// TUI, must agree on where it is — and beside the data file can mean inside
/// an attached repository, which is free to ship its own
/// `.openseek/worktrees.json.lock`.
///
/// A plain `OpenOrCreate` follows such a link twice over: it creates a file
/// wherever the link points, and it locks that inode instead, so two
/// instances following a link that moved would each hold a lock on a
/// different file and both proceed into the registry write this exists to
/// serialize.
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
    error if @async.is_being_cancelled() => raise error
    _ => None
  }
  if created is Some(file) {
    return file
  }
  let regular = (@fs.kind(sidecar, follow_symlink=false) is Regular) catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  }
  guard regular else {
    fail("\{sidecar} is not a regular file; refusing to lock through it")
  }
  @fs.open(sidecar, mode=ReadWrite, create_mode=OpenExisting)
}

///|
/// Take the lock only if nothing holds it right now.
///
/// For the caller that is asking *whether* someone holds it rather than
/// waiting for a turn — blocking there would mean waiting on the very
/// process the question is about. `None` means someone else holds it.
pub async fn FileLock::try_acquire(
  path : @pathx.Path,
  kind : @fs.Lock,
) -> FileLock? {
  ensure_dir(path.dirname())
  let file = open_lock_file(lock_file(path).to_string())
  errdefer file.close()
  // Not an error: someone holds it, which is the answer the caller wanted.
  // The descriptor still has to go, and `errdefer` does not cover a return.
  guard file.try_lock(kind) else {
    file.close()
    return None
  }
  Some({ file, })
}

///|
pub fn FileLock::release(self : FileLock) -> Unit {
  self.file.unlock()
  self.file.close()
}

///|
/// Replace `path`'s contents in one step: write a private file beside it, then
/// rename it over the target. A reader therefore sees either the old contents
/// or the new ones and never a truncated prefix, whether or not it takes the
/// lock, and a crash mid-write leaves the previous file intact.
pub async fn write_text_atomic(
  path : @pathx.Path,
  content : String,
  permission? : Int = 0o644,
) -> Unit {
  let target = path.to_string()
  // The directory is not always ours. A workspace is whatever repository the
  // user attached, and a repository can carry a symlink at a guessable
  // `<file>.tmp` — committed before the attach that adds the git exclusion.
  // Writing through it would truncate whatever it points at and then rename
  // the link itself into place as the registry. So: an unguessable name, and
  // `CreateNew` (O_CREAT|O_EXCL), which refuses any existing name including a
  // symlink. The random suffix also keeps a leftover from a crashed run from
  // blocking every later save, which a fixed name plus O_EXCL would.
  guard @entropy.random_hex(8) is Some(token) else {
    fail("could not name a private temporary file beside \{path}")
  }
  let temp = path.dirname().join(path.basename().to_owned() + ".tmp-" + token)
  // Nothing reuses this name, so every failure from here on has to take the
  // file away itself — including a write that raised partway (a cancelled
  // task, a full disk), which would otherwise leave one abandoned file per
  // attempt, holding whatever the caller was saving. Cancellation is among
  // those failures, hence the shield around the removal.
  errdefer @async.protect_from_cancel(() => discard_temp_file(temp))
  @fs.write_file(temp.to_string(), content, create_mode=CreateNew, permission~)
  commit_temp_file(temp, target)
}

///|
/// Move a finished temp file onto `target`. Windows may refuse to rename over
/// an existing file; removing the target first narrows the window where
/// neither name holds the new content to that one platform.
async fn commit_temp_file(temp : @pathx.Path, target : String) -> Unit {
  @fs.rename(temp.to_string(), target) catch {
    error if @async.is_being_cancelled() => raise error
    rename_failure => {
      // The retry exists only for that Windows refusal, which is a regular
      // file standing in the way. Anything else at the target is a different
      // failure and must surface as one: a directory there means the path is
      // wrong, and removing it would recursively destroy whatever it holds
      // rather than report that.
      let replaceable = (@fs.kind(target) is Regular) catch {
        error if @async.is_being_cancelled() => raise error
        _ => false
      }
      guard replaceable else { raise rename_failure }
      // Between the remove and the rename neither name holds the content.
      // Cancellation there would leave the target absent and let the caller's
      // cleanup take the temp file too, destroying the file this call was
      // supposed to update — so the pair commits as one.
      @async.protect_from_cancel(() => {
        @fs.remove(target)
        @fs.rename(temp.to_string(), target)
      })
    }
  }
}

///|
/// Best-effort removal of an abandoned temp file: the caller is already
/// raising the failure that matters, and a cleanup error must not replace it.
async fn discard_temp_file(temp : @pathx.Path) -> Unit {
  @fs.remove(temp.to_string()) catch {
    _ => ()
  }
}

// Tests. The lock is flock-based — it belongs to the open file description,
// not the process — so two acquires of one path contend inside a single
// process through exactly the mechanism a second instance would hit. That is
// what makes these tests meaningful without spawning a helper process.

///|
/// Every leftover matters now that the temp name is random: a save that
/// forgot to clean up would litter the directory instead of overwriting one
/// reused name.
async fn temp_leftovers(root : @pathx.Path, base : String) -> Array[String] {
  @fs.readdir(root.to_string()).filter(name => {
    name != base && name.has_prefix(base)
  })
}

///|
async test "an atomic save replaces the target and leaves no temp behind" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-fsx-atomic-")
  let file = root.join("registry.json")
  write_text_atomic(file, "first")
  assert_eq(read_text(file), "first")
  write_text_atomic(file, "second")
  assert_eq(read_text(file), "second")
  assert_eq(temp_leftovers(root, "registry.json"), [])
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
/// The lock must not be redirectable either: an attached repository can ship
/// `.openseek/worktrees.json.lock` as a link, and following it would both
/// create a file wherever it points and lock the wrong inode.
async test "a lock refuses a sidecar that is not a regular file" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-fsx-locklink-")
  let victim = root.join("victim.txt")
  let file = root.join("registry.json")
  @fs.symlink(
    root.join("registry.json.lock").to_string(),
    target=victim.to_string(),
  )
  let mut refused = false
  let taken = Some(FileLock::acquire(file, Exclusive)) catch {
    _ => {
      refused = true
      None
    }
  }
  if taken is Some(lock) {
    lock.release()
  }
  assert_true(refused)
  // Following the link would have created the file it points at.
  assert_false(exists(victim))
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
/// The save must not be redirectable out of its directory. A repository can
/// carry a symlink at the guessable `<file>.tmp` before it is ever attached
/// as a workspace; writing through it would truncate the link's target and
/// then rename the link itself into place as the registry.
async test "an atomic save never writes through a guessable temp name" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-fsx-symlink-")
  let victim = root.join("victim.txt")
  write_text_atomic(victim, "precious")
  let planted = root.join("registry.json.tmp")
  @fs.symlink(planted.to_string(), target=victim.to_string())
  let file = root.join("registry.json")
  write_text_atomic(file, "saved")
  assert_eq(read_text(file), "saved")
  // The planted link is untouched, and so is what it points at.
  assert_eq(read_text(victim), "precious")
  assert_true(@fs.kind(planted.to_string(), follow_symlink=false) is SymLink)
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
async test "an exclusive lock makes the next holder wait for the release" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-fsx-exclusive-")
  let file = root.join("registry.json")
  let log : Array[String] = []
  @async.with_task_group(group => {
    let first = FileLock::acquire(file, Exclusive)
    group.spawn(() => {
      let second = FileLock::acquire(file, Exclusive)
      defer second.release()
      log.push("second acquired")
    })
    |> ignore
    // Long enough for the waiter to reach the lock and block on it.
    @async.sleep(100)
    log.push("first releasing")
    first.release()
  })
  assert_eq(log, ["first releasing", "second acquired"])
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
/// Readers must not queue behind each other, or every unlocked read this
/// design relies on would have been the wrong call.
async test "shared locks admit each other" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-fsx-shared-")
  let file = root.join("registry.json")
  let log : Array[String] = []
  @async.with_task_group(group => {
    let first = FileLock::acquire(file, Shared)
    group.spawn(() => {
      let second = FileLock::acquire(file, Shared)
      defer second.release()
      log.push("second acquired")
    })
    |> ignore
    @async.sleep(100)
    log.push("first releasing")
    first.release()
  })
  assert_eq(log, ["second acquired", "first releasing"])
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
/// The Windows retry must not turn "something else already occupies this
/// path" into a recursive delete of whatever that something holds.
async test "an atomic save refuses a target that is not a regular file" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-fsx-kind-")
  let occupied = root.join("registry.json")
  ensure_dir(occupied)
  let kept = occupied.join("keep.txt")
  write_text_atomic(kept, "precious")
  let mut refused = false
  write_text_atomic(occupied, "clobber") catch {
    _ => refused = true
  }
  assert_true(refused)
  assert_eq(read_text(kept), "precious")
  // The refusal must also not leave its half-finished temp file behind.
  assert_eq(temp_leftovers(root, "registry.json"), [])
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
/// A released lock must leave nothing behind that keeps the next acquire out
/// — the failure this catches is `release` closing the descriptor without
/// unlocking, which only shows up on the second acquire.
async test "a lock can be retaken after release" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-fsx-retake-")
  let file = root.join("registry.json")
  for _ in 0..<3 {
    let lock = FileLock::acquire(file, Exclusive)
    write_text_atomic(file, "held")
    lock.release()
  }
  assert_eq(read_text(file), "held")
  @fs.rmdir(root.to_string(), recursive=true)
}
