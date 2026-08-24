// One host per runtime directory, and the liveness signal that decides when
// that rule may be enforced.
//
// `App::single_instance` hands a later launch to whichever process holds the
// identity's lock. That process is the right destination only while it is
// still running its event loop. A host stuck in CEF's shutdown is not: it
// keeps its lock, and its instance listener runs on its own thread, so the
// launch is accepted, enqueued, acknowledged — and then never acted on,
// because the thread that would act on it is the stuck one. The user sees
// the app simply stop opening, with no error anywhere for us to react to.
//
// So the rule is enforced conditionally. A host stamps a heartbeat from its
// event loop for as long as it owns the runtime directory; a launch that
// finds a *live* process whose stamp has stopped advancing declines to hand
// over and starts on its own instead. That is the pre-`single_instance`
// behaviour, which is degraded but usable — and the shared state it lands in
// is the state `@fsx.FileLock` already serializes.

///|
/// The file a host stamps while it owns the runtime directory. Its sidecar
/// lock is what "owning" means: the holder is the host, and only the holder
/// stamps, so a stamp never describes a process other than the lock's owner.
fn heartbeat_file(runtime_dir : @pathx.Path) -> @pathx.Path {
  runtime_dir.join("host-heartbeat")
}

///|
/// How often the owning host restamps. Short enough that a launch never
/// waits on it, long enough to stay invisible next to everything else the
/// event loop does.
const HeartbeatIntervalMs = 5_000

///|
/// How far behind a stamp may fall before its host looks like it has stopped.
/// Well past the interval, so ordinary lateness never reaches it.
const HeartbeatStaleMs : UInt64 = 60_000

///|
/// How long a stamp that already looks abandoned is watched before its host
/// is declared stopped. Longer than one interval, so a host that is merely
/// late — the machine was suspended, and its heartbeat task has not run since
/// the wake — is guaranteed the chance to produce one stamp.
const HeartbeatConfirmMs : Int = HeartbeatIntervalMs * 2

///|
/// The single-instance identity for `runtime_dir`.
///
/// Keyed by the runtime directory rather than the bundle, because the
/// directory is what one host owns: two builds sharing it must not both run,
/// and two checkouts with separate `dev-state` directories share nothing and
/// must not exclude each other. It also keeps a development host from
/// silently swallowing the launch of the installed app.
///
/// The path is canonicalized first, because two spellings of one directory
/// are still one host. `/tmp` and `/private/tmp`, or a checkout reached once
/// through a symlinked parent, would otherwise win separate elections and
/// both run — and the one that then lost the claim would carry on with no
/// heartbeat at all, invisible to `can_hand_off_to`. The workspace registry
/// collapses aliases for the same reason.
pub async fn identity(runtime_dir : @pathx.Path) -> String {
  let canonical = @fs.realpath(runtime_dir.to_string()) catch {
    error if @async.is_being_cancelled() => raise error
    // A directory that cannot be resolved keeps its lexical spelling: every
    // launch that cannot resolve it agrees on that same fallback.
    _ => runtime_dir.to_string()
  }
  "community.moonbit.proton.openseek-desktop:" + canonical
}

///|
/// This host's claim on `runtime_dir`, held for as long as the process runs.
/// Dropping it is the kernel's job: a host that dies — cleanly, by signal, or
/// stuck and then killed — releases it without leaving anything to clean up,
/// which is why the claim is a lock and not a recorded pid.
priv struct Claim {
  lock : @fsx.FileLock
  runtime_dir : @pathx.Path
}

///|
/// Whether this launch may be given to whoever owns `runtime_dir` — the
/// question `single_instance` asks, answered before enabling it.
///
/// True in two different situations, because both want the rule enforced:
/// nobody owns the directory, so this process becomes the owner; or the owner
/// is running its event loop and will act on what it is handed. False only
/// for the state in between — an owner that is alive but has stopped
/// stamping, where a hand-off is accepted by its listener thread and then
/// never acted on, and the launch simply disappears.
///
/// A probe, deliberately: it takes the claim only to see whether it can, and
/// lets go again. Keeping it would pair the claim with a process that has not
/// yet won the single-instance election and may be the one that forwards and
/// exits, leaving the surviving primary with no heartbeat and every later
/// launch mistaking it for healthy.
///
/// Only a live owner's stamp is ever read. A stamp left behind by a host that
/// exited holds no lock, so it is never consulted at all.
pub async fn can_hand_off_to(runtime_dir : @pathx.Path) -> Bool {
  match @fsx.FileLock::try_acquire(heartbeat_file(runtime_dir), Exclusive) {
    Some(lock) => {
      lock.release()
      true
    }
    None => {
      let stamped = read_stamp(runtime_dir)
      guard stamp_is_behind(stamped) else { return true }
      // A machine resuming from suspend leaves exactly this evidence: the
      // owner's heartbeat task has not been scheduled since the wake, so its
      // stamp is as old as the sleep was long, and its loop is perfectly
      // healthy. One stamp settles it. The wait falls only on this already
      // suspicious path, and a launch that takes a few extra seconds beats
      // one that starts a rival host against a working one.
      @async.sleep(HeartbeatConfirmMs)
      read_stamp(runtime_dir) != stamped
    }
  }
}

///|
/// Own `runtime_dir` and stamp for it for as long as this host runs, taking
/// the claim as soon as it is free.
///
/// Call this from the process that won the single-instance election and
/// nowhere else. That is what keeps the claim and the primary the same
/// process, so the heartbeat always describes the host a later launch would
/// actually be handed to.
///
/// It waits rather than gives up, because the primary can legitimately find
/// the claim taken: a host that started on the stopped-owner path holds no
/// single-instance identity, so its claim outlives the election it never
/// entered. Giving up there would leave this — the process every later launch
/// is handed to — with no heartbeat at all, and a launch reading the other
/// host's fresh stamp would go on handing itself to this one however stuck it
/// became. Waiting costs nothing and ends the moment that host exits.
///
/// That wait is why `on_claimed` exists. Anything else this host does to the
/// runtime directory's shared state has to run inside it rather than beside
/// it: a task spawned alongside this one would act on the directory during
/// the wait — while it still belongs to the host being waited out. Passing
/// the work here is what makes "we own this" its precondition. It runs once,
/// in this task, so a failure there stops the heartbeat too; give it
/// something that handles its own errors.
pub async fn hold(
  runtime_dir : @pathx.Path,
  retry_interval_ms? : Int = HeartbeatIntervalMs,
  on_claimed? : async () -> Unit,
) -> Unit {
  for ;; {
    if claim(runtime_dir) is Some(held) {
      // `claim` has already stamped, so the delay this adds before the first
      // restamp costs nothing a reader can observe.
      if on_claimed is Some(claimed) {
        claimed()
      }
      return held.run()
    }
    @async.sleep(retry_interval_ms)
  }
}

///|
/// Take ownership of `runtime_dir` for this host, or `None` if another
/// process holds it.
async fn claim(runtime_dir : @pathx.Path) -> Claim? {
  guard @fsx.FileLock::try_acquire(heartbeat_file(runtime_dir), Exclusive)
    is Some(lock) else {
    return None
  }
  // Stamp before anyone can read it, so a launch racing this one never finds
  // a fresh lock beside the previous host's abandoned stamp.
  stamp(runtime_dir)
  Some({ lock, runtime_dir })
}

///|
/// Restamp for as long as the host runs. Spawned on the app's task group, so
/// the stamp advances exactly while the loop that would act on a hand-off is
/// running — which is the whole signal.
async fn Claim::run(self : Claim) -> Unit {
  for ;; {
    @async.sleep(HeartbeatIntervalMs)
    stamp(self.runtime_dir)
  }
}

///|
/// Record the current wall clock. Written atomically: a launch reading this
/// file concurrently must see one complete stamp or the previous one, never a
/// half-written number that would parse as ancient and read as a dead host.
async fn stamp(runtime_dir : @pathx.Path) -> Unit {
  @fsx.write_text_atomic(
    heartbeat_file(runtime_dir),
    @env.now().to_string(),
    permission=0o600,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    // A stamp that cannot be written leaves the previous one to go stale, so
    // the failure mode is "a later launch starts its own instance" — the
    // degraded-but-working side, which is where an unwritable runtime
    // directory belongs anyway.
    _ => ()
  }
}

///|
/// The owning host's last stamp, or `None` when there is nothing readable
/// where one belongs.
async fn read_stamp(runtime_dir : @pathx.Path) -> UInt64? {
  let text = (@fsx.try_read_text(heartbeat_file(runtime_dir)) catch {
    error if @async.is_being_cancelled() => raise error
    _ => None
  }).unwrap_or("")
  Some(@string.parse_uint64(text.trim())) catch {
    _ => None
  }
}

///|
/// Whether a stamp is far enough behind the clock to look abandoned. Absent
/// or unparsable counts as behind: something holds the lock while the file
/// that should describe it says nothing.
fn stamp_is_behind(stamped : UInt64?) -> Bool {
  guard stamped is Some(stamped) else { return true }
  let now = @env.now()
  // A stamp from the future is a clock that moved backwards, not a dead host.
  guard now > stamped else { return false }
  now - stamped > HeartbeatStaleMs
}

///|
async test "the identity separates runtime directories and repeats for one" {
  let installed : @pathx.Path = "/Users/u/Library/Application Support/SeekMoon"
  let checkout : @pathx.Path = "/src/openseek/desktop/target/dev-state"
  assert_eq(identity(installed), identity(installed))
  assert_not_eq(identity(installed), identity(checkout))
}

///|
/// The claim is the liveness fact: a launch that can take the lock knows no
/// host is running, whatever any leftover stamp says.
async test "an unclaimed runtime directory is claimable" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-instance-free-")
  guard claim(root) is Some(held) else { fail("expected a free claim") }
  held.lock.release()
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
/// A host that exited leaves its stamp behind. Nothing holds the lock, so
/// that stamp must never be read — the next launch is simply the new owner.
async test "a stamp left by an exited host is not read at all" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-instance-stale-")
  @fsx.write_text_atomic(heartbeat_file(root), "1")
  assert_true(can_hand_off_to(root))
  guard claim(root) is Some(held) else {
    fail("an abandoned stamp must not block a claim")
  }
  held.lock.release()
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
/// The owner is alive and stamping: hand the launch over.
async test "a live owner with a fresh stamp takes the launch" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-instance-live-")
  guard claim(root) is Some(owner) else { fail("expected the first claim") }
  assert_true(can_hand_off_to(root))
  assert_true(claim(root) is None)
  owner.lock.release()
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
/// The owner is alive and has stopped stamping: keep the launch for ourselves
/// rather than feed it to a process that will not act on it.
async test "a live owner with a stopped stamp cannot be handed to" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-instance-stopped-")
  guard claim(root) is Some(owner) else { fail("expected the first claim") }
  // The owner's loop stopped long ago; only the process is still there.
  @fsx.write_text_atomic(heartbeat_file(root), "1")
  assert_false(can_hand_off_to(root))
  owner.lock.release()
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
/// Work that acts on the runtime directory belongs after the claim, not
/// beside it. A primary can reach its lifecycle hook while a bypass host
/// still owns the directory, and an update sweep running there would clear
/// that host's staging directory or the relaunch marker it is about to act
/// on.
async test "owner-only work waits until the claim is taken" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-instance-claimed-")
  guard claim(root) is Some(other) else { fail("expected the first claim") }
  let swept : Ref[Bool] = Ref(false)
  @async.with_task_group(group => {
    group.spawn_bg(allow_failure=true, () => {
      hold(root, retry_interval_ms=10, on_claimed=fn() { swept.val = true })
    })
    // Many retries' worth of waiting, all of it while the directory is still
    // the other host's.
    @async.sleep(50)
    assert_false(swept.val)
    other.lock.release()
    @async.sleep(50)
    assert_true(swept.val)
    group.return_immediately(())
  })
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
/// The primary can find the claim already taken — a host that started on the
/// stopped-owner path holds one without ever entering an election. Giving up
/// there would leave the process every later launch is handed to with no
/// heartbeat at all, so it waits the other host out instead.
async test "a primary that loses the claim takes it when the holder leaves" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-instance-wait-")
  guard claim(root) is Some(other) else { fail("expected the first claim") }
  @async.with_task_group(group => {
    group.spawn_bg(allow_failure=true, () => hold(root, retry_interval_ms=10))
    // Many retries' worth of waiting changes nothing while the other host is
    // there — the claim stays that host's.
    @async.sleep(50)
    assert_true(claim(root) is None)
    other.lock.release()
    // Now nobody else holds it, so a claim that still cannot be taken can
    // only be the waiting host's — and it stamps, which is what makes the
    // heartbeat describe the process a launch would be handed to.
    @async.sleep(50)
    assert_true(claim(root) is None)
    assert_true(can_hand_off_to(root))
    group.return_immediately(())
  })
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
/// The probe must not keep what it takes. Two launches racing here both find
/// the directory free and both go on to the single-instance election; if the
/// probe held on, the loser would carry the claim out of the process and the
/// winning primary would run with no heartbeat at all.
async test "the probe leaves the claim free for the election winner" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-instance-probe-")
  assert_true(can_hand_off_to(root))
  assert_true(can_hand_off_to(root))
  guard claim(root) is Some(held) else {
    fail("probing must not consume the claim")
  }
  held.lock.release()
  @fs.rmdir(root.to_string(), recursive=true)
}
