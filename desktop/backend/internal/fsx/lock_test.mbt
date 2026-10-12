// The lock belongs to the open file description, not the process, so two
// acquires of one path contend inside a single process through exactly the
// mechanism a second host would hit. That is what makes these tests
// meaningful without spawning a helper process.

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
  let root : @pathx.Path = Path(@fs.tmpdir(prefix="openseek-fsx-atomic-"))
  defer @fs.rmdir(root.to_string(), recursive=true)
  let file = root.join("registry.json")
  @fsx.write_text_atomic(file, "first")
  assert_eq(@fsx.read_text(file), "first")
  @fsx.write_text_atomic(file, "second")
  assert_eq(@fsx.read_text(file), "second")
  assert_eq(temp_leftovers(root, "registry.json"), [])
}

///|
/// The lock must not be redirectable: an attached repository can ship
/// `.openseek/worktrees.json.lock` as a link, and following it would both
/// create a file wherever it points and lock the wrong inode.
#cfg(not(platform="windows"))
async test "a lock refuses a sidecar that is not a regular file" {
  let root : @pathx.Path = Path(@fs.tmpdir(prefix="openseek-fsx-locklink-"))
  defer @fs.rmdir(root.to_string(), recursive=true)
  let victim = root.join("victim.txt")
  let file = root.join("registry.json")
  @fs.symlink(
    root.join("registry.json.lock").to_string(),
    target=victim.to_string(),
  )
  let taken = Some(@fsx.FileLock::acquire(file)) catch { _ => None }
  if taken is Some(lock) {
    lock.release()
    fail("the lock was taken through a link")
  }
  // Following the link would have created the file it points at.
  assert_false(@fsx.exists(victim))
}

///|
/// The save must not be redirectable out of its directory. A repository can
/// carry a symlink at the guessable `<file>.tmp` before it is ever attached
/// as a workspace; writing through it would truncate the link's target and
/// then rename the link itself into place as the registry.
#cfg(not(platform="windows"))
async test "an atomic save never writes through a guessable temp name" {
  let root : @pathx.Path = Path(@fs.tmpdir(prefix="openseek-fsx-symlink-"))
  defer @fs.rmdir(root.to_string(), recursive=true)
  let victim = root.join("victim.txt")
  @fsx.write_text_atomic(victim, "precious")
  let planted = root.join("registry.json.tmp")
  @fs.symlink(planted.to_string(), target=victim.to_string())
  let file = root.join("registry.json")
  @fsx.write_text_atomic(file, "saved")
  assert_eq(@fsx.read_text(file), "saved")
  // The planted link is untouched, and so is what it points at.
  assert_eq(@fsx.read_text(victim), "precious")
  assert_true(@fs.kind(planted.to_string(), follow_symlink=false) is SymLink)
}

///|
async test "an exclusive lock makes the next holder wait for the release" {
  let root : @pathx.Path = Path(@fs.tmpdir(prefix="openseek-fsx-exclusive-"))
  defer @fs.rmdir(root.to_string(), recursive=true)
  let file = root.join("registry.json")
  let log : Array[String] = []
  @async.with_task_group(group => {
    let first = @fsx.FileLock::acquire(file)
    group.spawn_bg(() => {
      let second = @fsx.FileLock::acquire(file)
      defer second.release()
      log.push("second acquired")
    })
    // Long enough for the waiter to reach the lock and block on it.
    @async.sleep(100)
    log.push("first releasing")
    first.release()
  })
  assert_eq(log, ["first releasing", "second acquired"])
}

///|
/// A save that cannot land must leave what occupies the path alone, and not
/// take that for a stale target to clear out of the way.
async test "an atomic save refuses a target that is not a regular file" {
  let root : @pathx.Path = Path(@fs.tmpdir(prefix="openseek-fsx-kind-"))
  defer @fs.rmdir(root.to_string(), recursive=true)
  let occupied = root.join("registry.json")
  @fsx.ensure_dir(occupied)
  let kept = occupied.join("keep.txt")
  @fsx.write_text_atomic(kept, "precious")
  let refused = try {
    @fsx.write_text_atomic(occupied, "clobber")
    false
  } catch {
    _ => true
  }
  assert_true(refused)
  assert_eq(@fsx.read_text(kept), "precious")
  // The refusal must also not leave its half-finished temp file behind.
  assert_eq(temp_leftovers(root, "registry.json"), [])
}

///|
/// A released lock must leave nothing behind that keeps the next acquire out
/// — the failure this catches is `release` closing the descriptor without
/// unlocking, which only shows up on the second acquire.
async test "a lock can be retaken after release" {
  let root : @pathx.Path = Path(@fs.tmpdir(prefix="openseek-fsx-retake-"))
  defer @fs.rmdir(root.to_string(), recursive=true)
  let file = root.join("registry.json")
  for _ in 0..<3 {
    let lock = @fsx.FileLock::acquire(file)
    @fsx.write_text_atomic(file, "held")
    lock.release()
  }
  assert_eq(@fsx.read_text(file), "held")
}
