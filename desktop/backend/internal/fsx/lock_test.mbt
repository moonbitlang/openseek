// The lock belongs to the open file description, not the process, so two
// acquires of one path contend inside a single process through exactly the
// mechanism a second host would hit. That is what makes these tests
// meaningful without spawning a helper process.

///|
/// The lock must not be redirectable: an attached repository can ship
/// `.openseek/worktrees.json.lock` as a link, and following it would both
/// create a file wherever it points and lock the wrong inode.
#cfg(not(platform="windows"))
async test "a lock refuses a sidecar that is not a regular file" {
  let root : @pathx.Path = Path(@fs.tmpdir(prefix="openseek-fsx-locklink-"))
  defer @fs.remove(root.to_string(), recursive=true)
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
async test "an exclusive lock makes the next holder wait for the release" {
  let root : @pathx.Path = Path(@fs.tmpdir(prefix="openseek-fsx-exclusive-"))
  defer @fs.remove(root.to_string(), recursive=true)
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
/// A released lock must leave nothing behind that keeps the next acquire out
/// — the failure this catches is `release` closing the descriptor without
/// unlocking, which only shows up on the second acquire.
async test "a lock can be retaken after release" {
  let root : @pathx.Path = Path(@fs.tmpdir(prefix="openseek-fsx-retake-"))
  defer @fs.remove(root.to_string(), recursive=true)
  let file = root.join("registry.json")
  for _ in 0..<3 {
    let lock = @fsx.FileLock::acquire(file)
    @fsx.write_text(file, "held")
    lock.release()
  }
  assert_eq(@fsx.read_text(file), "held")
}
