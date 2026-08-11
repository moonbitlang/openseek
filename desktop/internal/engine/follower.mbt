// The session follower: the host's second reader of a conversation's durable
// record. While a desktop-managed engine can write to a session's store, one
// follower actor per session tails the record through the bundled engine's
// own reader (`sessions show` — shared lock, torn-write repair and header
// parsing all come with it) and broadcasts each newly committed event as a
// canonical `session.event` notification. Those commits, plus the
// `session.load` snapshot, are the durable transcript's only sources on the
// client; the live `agent.event` stream only settles transient stream and
// lifecycle state in commit-aware clients (docs/remote-protocol.md).
//
// The actor is the design's ordering backbone: every read of the record —
// watcher-less kicks, the poll fallback, a routed `session.load`, the final
// scan on engine exit, the archive drain — goes through one serial loop, so
// a session's commits reach the hub in sequence order and a stop
// acknowledgment really means "no scan is in flight and none will start".
// Followers run only while the host manages a writer for the session (the
// serve engine's lifetime, spawn to EOF); an idle session's `session.load`
// reads the record directly, one-shot.

///|
/// How often the actor re-checks the store file without being kicked. Kicks
/// from the engine's own stdout events provide the low-latency wakeups (an
/// append is always accompanied by a nearby event — a behavioral invariant,
/// not a contract), so this poll is the safety net for the exceptions:
/// external CLI writers sharing the session, and any append whose event was
/// lost or reordered.
const FollowerPollMs = 1000

///|
/// Load callers backpressure here instead of accumulating an unbounded
/// waiter array in the actor. The control inbox has one reserved logical
/// slot for each collapsed message kind (Kick, Load, Stop), so Stop can
/// always be queued even when loads are saturated.
const FollowerLoadQueueSize = 32

///|
/// A cheap change fingerprint for the store file, checked before spending a
/// `sessions show` on a kick: size catches every append (the file grows),
/// mtime catches the store's repair paths that rewrite instead of appending.
priv struct FileSignature {
  size : Int64
  mtime_s : Int64
  mtime_ns : Int
} derive(Eq)

///|
priv enum FollowerMsg {
  // Something may have been appended: scan when the file signature moved.
  Kick
  // A `session.load` routed through the actor: force a scan — broadcasting
  // any fresh commits — and reply with the full session JSON.
  Load
  // Stop after a final scan. `writer_exited` is supplied only by a caller
  // that has crossed the process-exit barrier; it lets a brand-new session
  // with no record file retire as an empty drain. The completed generation
  // is a drain barrier: no scan is in flight and none will start, so the
  // record can be moved.
  Stop(final_scan~ : Bool, writer_exited~ : Bool, generation~ : Int)
}

///|
priv enum FollowerLoadReply {
  LoadOk(@protocol.SessionDocument)
  LoadFailed(String)
  // The follower was already draining; the caller waits/retries the actor.
  LoadStopped
}

///|
/// A queued load can be deactivated if its control message cannot be
/// scheduled. The actor still removes that bounded queue entry, but never
/// tries to answer an abandoned reply channel.
priv struct FollowerLoadRequest {
  reply : @async.Queue[FollowerLoadReply]
  mut active : Bool
}

///|
/// A lifecycle Finished that was published before the follower could prove
/// the matching durable frontier. The actor retains published entries until
/// retirement as an idempotence ledger: a concurrent producer cannot enqueue
/// the same run again while another boundary emission is suspended.
priv struct PendingDurableFinish {
  run_id : String
  mut published : Bool
}

///|
priv struct SessionFollower {
  session : String
  root : @pathx.Absolute
  inbox : @async.Queue[FollowerMsg]
  // Bounded load requests. One Load control message drains and answers a
  // whole batch from this queue with one snapshot.
  load_requests : @async.Queue[FollowerLoadRequest]
  // One queued Kick at a time: a delta storm collapses to a single pending
  // wakeup instead of an unbounded backlog of identical messages.
  mut kick_pending : Bool
  mut load_pending : Bool
  mut stopping : Bool
  mut retired : Bool
  // Stop callers poll a generation-stamped result, avoiding a consumable
  // one-shot ack (and an unbounded waiter collection). A failed final scan
  // completes the generation with an error and reactivates the actor.
  mut stop_generation : Int
  mut completed_stop_generation : Int
  mut completed_stop_error : String?
  mut stop_observers : Int
  // Pending run identities belong to this retryable drain, not to the serve
  // handle: EOF may retire a dead handle while a failed final scan deliberately
  // leaves this actor alive for archive/detach to retry later.
  durable_finishes : Array[PendingDurableFinish]
  // The highest sequence already broadcast. Commits at or below it are old
  // news; the frontier only advances, so a scan can never re-broadcast.
  mut watermark : Int
  // Signature of the store file as of the last completed scan (taken before
  // the scan read it, so a write racing the read re-triggers). `None` until
  // the first scan, or when the file cannot be examined.
  mut consumed : FileSignature?
}

///|
/// Remember that `run_id` needs an exact post-Finished durable boundary.
/// Registration is idempotent across the semantic-terminal and failed-command
/// paths, which may race while the child is shutting down.
fn SessionFollower::expect_durable_finish(
  self : SessionFollower,
  run_id : String,
) -> Unit {
  for pending in self.durable_finishes {
    if pending.run_id == run_id {
      return
    }
  }
  self.durable_finishes.push({ run_id, published: false })
}

///|
/// Publish every retained boundary at the frontier proved by this successful
/// final scan. Keep successful entries as the actor's dedupe ledger; failed
/// emissions stay pending and make the Stop fail so a later caller retries.
async fn SessionFollower::publish_durable_finishes(
  self : SessionFollower,
  sink : EventSink,
) -> Unit {
  // Emission suspends, so a concurrent failed-command path can append while
  // this loop runs. Re-read the length to include it before retirement.
  let mut index = 0
  while index < self.durable_finishes.length() {
    let pending = self.durable_finishes[index]
    if !pending.published {
      emit_durable_boundary(sink, pending.run_id, self.session, self.watermark)
      pending.published = true
    }
    index = index + 1
  }
}

///|
/// Where the store keeps this session's event log. Duplicating the store's
/// layout here is only a fast-path optimization — the signature check that
/// uses it skips redundant `sessions show` spawns. If the layout ever moves
/// upstream, the signature reads `None`, every kick scans, and behavior
/// stays correct (just slower).
fn session_store_file(root : @pathx.Absolute, session : String) -> String {
  root
  .join("sessions")
  .join(session)
  .join("openseek_session-\{session}.jsonl")
  .to_string()
}

///|
async fn file_signature(path : String) -> FileSignature? {
  let file = @fs.open(path, mode=ReadOnly) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  defer file.close()
  let size = file.size() catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  let (mtime_s, mtime_ns) = file.mtime() catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  Some({ size, mtime_s, mtime_ns })
}

///|
/// The typed store events committed after `watermark`, in file order (the
/// store guarantees ascending sequences).
fn commits_after(
  session : @protocol.SessionDocument,
  watermark : Int,
) -> Array[@protocol.SessionEvent] {
  let fresh : Array[@protocol.SessionEvent] = []
  for event in session.events.unwrap_or([]) {
    if event.sequence > watermark {
      fresh.push(event)
    }
  }
  fresh
}

///|
/// The highest event sequence in a session JSON — what a snapshot's
/// watermark is. 0 for a record with no events.
fn session_max_sequence(session : @protocol.SessionDocument) -> Int {
  let mut max = 0
  for event in commits_after(session, 0) {
    if event.sequence > max {
      max = event.sequence
    }
  }
  max
}

///|
/// One scan: read the record through `sessions show`, broadcast everything
/// committed past the watermark, advance it, and return the full session
/// JSON. Without `force~`, a scan whose file signature matches the last
/// consumed one is skipped (`None`). Raises when the record cannot be read —
/// the watermark then stays put, so the next scan retries the same span.
async fn SessionFollower::scan(
  self : SessionFollower,
  sink : EventSink,
  manager : EngineManager,
  force~ : Bool,
) -> @protocol.SessionDocument? {
  let signature = file_signature(session_store_file(self.root, self.session))
  if !force && signature is Some(_) && signature == self.consumed {
    return None
  }
  let output = session_show_stdout(manager, self.session, self.root)
  let session_json = @json.parse(output) catch {
    _ => raise EngineError("engine returned a malformed session")
  }
  let session : @protocol.SessionDocument = @json.from_json(session_json) catch {
    _ => raise EngineError("engine returned a malformed session")
  }
  for event in commits_after(session, self.watermark) {
    emit(
      sink,
      SessionCommit({ session: self.session, sequence: event.sequence, event }),
    )
    self.watermark = event.sequence
  }
  self.consumed = signature
  Some(session)
}

///|
/// The actor. Baseline first: adopt the record's current frontier without
/// broadcasting — anything committed before this follower existed reaches
/// clients through `session.load`, not through a replay storm — then serve
/// the inbox serially until a Stop, with a poll ticker as the kick fallback.
/// The ready ack releases the spawn path only after the baseline, so the
/// engine cannot append before the follower is watching.
async fn SessionFollower::run(
  self : SessionFollower,
  sink : EventSink,
  manager : EngineManager,
  ready : @async.Queue[Unit],
) -> Unit {
  let follower = self
  // Cancellation can land during baseline, a blocking store scan, or an
  // in-flight load generation. Every exit retires this exact identity and
  // completes queued readers with LoadStopped instead of stranding reply.get.
  defer retire_follower_actor(manager, follower)
  let baseline_signature = file_signature(
    session_store_file(follower.root, follower.session),
  )
  let baseline = session_show_stdout(manager, follower.session, follower.root) catch {
    error if @async.is_being_cancelled() => raise error
    // No record yet (a session's first turn), or a transiently unreadable
    // one: start from 0. Over-broadcasting history later is safe — clients
    // drop commits at or below their own watermark — it only costs bytes.
    _ => ""
  }
  if !baseline.is_empty() {
    let document : @protocol.SessionDocument? = try
      @json.from_json(@json.parse(baseline))
    catch {
      _ => None
    } noraise {
      document => Some(document)
    }
    if document is Some(document) {
      follower.watermark = session_max_sequence(document)
      follower.consumed = baseline_signature
    }
  }
  ready.put(())
  let mut retired_generation = 0
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      for ;; {
        @async.sleep(FollowerPollMs)
        kick_follower_inbox(follower)
      }
    })
    for ;; {
      match follower.inbox.get() {
        Kick => {
          follower.kick_pending = false
          ignore(
            follower.scan(sink, manager, force=false) catch {
              error if @async.is_being_cancelled() => raise error
              error => {
                @xlog.debug() <?
                  {
                    "event": "desktop_follower_scan_failed",
                    "session": follower.session,
                    "error": "\{error}",
                  }
                None
              }
            },
          )
        }
        Load => {
          let response = try follower.scan(sink, manager, force=true) catch {
            error if @async.is_being_cancelled() => raise error
            error => LoadFailed("\{error}")
          } noraise {
            Some(json) => LoadOk(json)
            // Unreachable — a forced scan never skips — but total.
            None => LoadFailed("session read produced nothing")
          }
          // Keep `load_pending` set while draining. Reply queues are fresh
          // Blocking(1) queues, so these puts do not suspend; every caller
          // that joined before the queue is observed empty receives this
          // one snapshot. A later caller queues the next Load generation.
          for ;; {
            let request = follower.load_requests.try_get() catch { _ => None }
            match request {
              Some(request) =>
                if request.active {
                  request.active = false
                  request.reply.put(response)
                }
              None => {
                follower.load_pending = false
                break
              }
            }
          }
        }
        Stop(final_scan~, writer_exited~, generation~) => {
          let mut failure = if final_scan {
            try {
              // Everything the departed writer persisted is broadcast
              // before this generation can retire successfully.
              ignore(follower.scan(sink, manager, force=true))
              None
            } catch {
              error if @async.is_being_cancelled() => raise error
              error =>
                // A first prompt can be cancelled after a partial stdin
                // write but before the engine creates its durable record.
                // Once the caller has proved the writer exited, an absent
                // pinned record file and a zero watermark together prove
                // there is no durable tail to drain. `@fs.exists` returns
                // false only for ENOENT and propagates permission/stat
                // failures; an existing malformed or unreadable record
                // therefore keeps the follower active for a later retry.
                if writer_exited && follower.watermark == 0 {
                  try
                    @fs.exists(
                      session_store_file(follower.root, follower.session),
                    )
                  catch {
                    verify_error if @async.is_being_cancelled() =>
                      raise verify_error
                    verify_error =>
                      Some(
                        "\{error}; failed to verify session record: \{verify_error}",
                      )
                  } noraise {
                    true => Some("\{error}")
                    false => None
                  }
                } else {
                  Some("\{error}")
                }
            }
          } else {
            None
          }
          // Both a readable snapshot and the exact-zero proof above are
          // successful drains. Publish pending lifecycle boundaries at this
          // single seam before retirement; a sink failure keeps the actor
          // installed so another Stop can retry the unacknowledged entries.
          if final_scan && failure is None {
            failure = try {
              follower.publish_durable_finishes(sink)
              None
            } catch {
              error if @async.is_being_cancelled() => raise error
              error => Some("\{error}")
            }
          }
          if failure is Some(detail) {
            // A failed final scan is not a drain. Keep the actor installed
            // and polling, and publish the exact failure to every caller
            // waiting on this stop generation.
            follower.completed_stop_generation = generation
            follower.completed_stop_error = Some(detail)
            if follower.stop_observers == 0 {
              follower.stopping = false
            }
          } else {
            retired_generation = generation
            break
          }
        }
      }
    }
    group.return_immediately(())
  })
  // Publish the successful generation before removing the identity. A stop
  // waiter can therefore distinguish this deliberate retirement from an
  // actor that vanished without completing its final scan.
  follower.completed_stop_generation = retired_generation
  follower.completed_stop_error = None
}

///|
/// Remove exactly this follower generation and make every queued caller
/// observe retirement. Closing is synchronous, so startup rollback can use
/// this from a cancellation path even when the follower task itself belongs
/// to a task group that is already being torn down. The identity check only
/// guards the manager entry; a stale actor is still closed without touching
/// the successor that replaced it.
fn retire_follower_actor(
  manager : EngineManager,
  follower : SessionFollower,
) -> Unit {
  if follower.retired {
    return
  }
  follower.retired = true
  if manager.followers.get(follower.session) is Some(current) &&
    physical_equal(current, follower) {
    manager.followers.remove(follower.session)
  }
  follower.inbox.close(clear=true)
  follower.load_requests.close()
  // Defensive completion for any request that crossed retirement. Normal
  // Stop ordering drains every pre-Stop Load first; startup cancellation can
  // happen earlier, so those readers get an explicit retry signal here.
  for ;; {
    let request = follower.load_requests.try_get() catch { _ => None }
    match request {
      Some(request) =>
        if request.active {
          request.active = false
          ignore(request.reply.try_put(LoadStopped) catch { _ => false })
        }
      None => break
    }
  }
}

///|
/// Queue a Kick, collapsing repeats while one is already pending. Safe to
/// call from anywhere; a closed inbox (the actor is retiring) refuses it
/// quietly.
fn kick_follower_inbox(follower : SessionFollower) -> Unit {
  if follower.stopping || follower.kick_pending {
    return
  }
  if (follower.inbox.try_put(Kick) catch { _ => false }) {
    follower.kick_pending = true
  }
}

///|
/// Wake `session`'s follower, if any — the engine consumer calls this on
/// every stdout event, which is what gives commits their low latency.
fn EngineManager::kick_follower(self : EngineManager, session : String) -> Unit {
  if self.followers.get(session) is Some(follower) {
    kick_follower_inbox(follower)
  }
}

///|
/// Make sure a follower is watching `config.session` before its engine can
/// write, and only return once its baseline scan is done. Runs inside the
/// pump's spawn path, so the follower task lives in the same task group as
/// the engines. The returned identity is present only when this call installed
/// a new follower; its caller owns startup rollback until the engine reader
/// and consumer have both been scheduled. A session root can still be absent
/// only when the durable store cannot be resolved; in that case there is no
/// record for a follower to scan.
async fn[G] ensure_follower(
  sink~ : EventSink,
  group~ : @async.TaskGroup[G],
  manager~ : EngineManager,
  config~ : RunConfig,
) -> SessionFollower? {
  guard config.session_root is Some(root) else { return None }
  let session = config.session
  // A predecessor draining its final scan removes itself from the map when
  // done; wait for that rather than racing it with a second broadcaster for
  // the same session (per-session commit order is the design's backbone).
  for ;; {
    match manager.followers.get(session) {
      Some(follower) => {
        if !follower.stopping && follower.root.to_string() == root.to_string() {
          return None
        }
        // Join an in-flight drain, or retire an active follower attached to
        // another session root. A failed final scan propagates and prevents
        // a child for the new root from being spawned.
        stop_follower(manager, session, writer_exited=false)
      }
      None => break
    }
  }
  let follower : SessionFollower = {
    session,
    root,
    inbox: Queue(kind=Blocking(3)),
    load_requests: Queue(kind=Blocking(FollowerLoadQueueSize)),
    kick_pending: false,
    load_pending: false,
    stopping: false,
    retired: false,
    stop_generation: 0,
    completed_stop_generation: 0,
    completed_stop_error: None,
    stop_observers: 0,
    durable_finishes: [],
    watermark: 0,
    consumed: None,
  }
  manager.followers[session] = follower
  let ready : @async.Queue[Unit] = Queue(kind=Blocking(1))
  group.spawn_bg(no_wait=true, allow_failure=true, () => {
    follower.run(sink, manager, ready)
  })
  ready.get() catch {
    error => {
      // The actor lives in the pump group rather than this caller's task, so
      // cancelling startup does not cancel it. Retire it synchronously here;
      // waiting for a Stop would deadlock if the pump group is also exiting.
      discard_follower_startup(manager, follower)
      raise error
    }
  }
  Some(follower)
}

///|
/// Stop `session`'s follower and wait for its final scan to drain. This is
/// the barrier archive relies on: after it returns, no scan is in flight and
/// none will start, so the record directory can be moved without a late
/// `sessions show` broadcasting from beyond the grave.
async fn stop_follower(
  manager : EngineManager,
  session : String,
  writer_exited~ : Bool,
  final_scan? : Bool = true,
) -> Unit {
  guard manager.followers.get(session) is Some(follower) else { return }
  stop_follower_instance(manager, follower, writer_exited~, final_scan~)
}

///|
/// Stop one captured follower generation, but only while it is still the
/// manager's current identity. EOF cleanup captures this before publishing
/// the engine-exit latch, so a delayed cleanup can never stop a successor.
async fn stop_follower_instance(
  manager : EngineManager,
  follower : SessionFollower,
  writer_exited~ : Bool,
  final_scan? : Bool = true,
) -> Unit {
  let session = follower.session
  guard manager.followers.get(session) is Some(current) &&
    physical_equal(current, follower) else {
    return
  }
  let generation = if follower.stopping {
    follower.stop_generation
  } else {
    // This flag is set before the first possible yield. No load/kick can
    // slip behind the drain request, and ensure_follower can never mistake
    // this generation for an active reusable actor.
    follower.stopping = true
    follower.stop_generation = follower.stop_generation + 1
    let generation = follower.stop_generation
    let queued = follower.inbox.try_put(
      Stop(final_scan~, writer_exited~, generation~),
    ) catch {
      _ => false
    }
    if !queued {
      follower.completed_stop_generation = generation
      follower.completed_stop_error = Some("follower control queue is closed")
      follower.stopping = false
      raise EngineError("follower control queue is closed")
    }
    generation
  }
  follower.stop_observers = follower.stop_observers + 1
  defer {
    follower.stop_observers = follower.stop_observers - 1
    // Keep a failed generation closed while any of its callers still need
    // to observe the result. The last observer reactivates the actor, after
    // which a later lifecycle operation may start a fresh retry generation.
    if follower.stop_generation == generation &&
      follower.completed_stop_generation == generation &&
      follower.completed_stop_error is Some(_) &&
      follower.stop_observers == 0 {
      follower.stopping = false
    }
  }
  for ;; {
    if follower.completed_stop_generation == generation {
      if follower.completed_stop_error is Some(detail) {
        raise EngineError(detail)
      }
      return
    }
    guard manager.followers.get(session) is Some(current) &&
      physical_equal(current, follower) else {
      raise EngineError("follower retired without completing its final scan")
    }
    @async.sleep(10)
  }
}

///|
/// Roll back a follower initialized before process startup commits. No
/// prompt can have reached a child yet, hence no writer has a final commit
/// to scan; this is synchronous actor initialization cleanup, not a drain.
fn discard_follower_startup(
  manager : EngineManager,
  follower : SessionFollower,
) -> Unit {
  retire_follower_actor(manager, follower)
}

///|
/// Queue a bounded, coalesced snapshot request. When the request queue is
/// full, `put` backpressures this caller; Stop remains independent in the
/// three-slot control inbox and can always overtake load saturation after
/// the single pending Load generation.
async fn request_follower_load(follower : SessionFollower) -> FollowerLoadReply {
  if follower.stopping {
    return LoadStopped
  }
  let reply : @async.Queue[FollowerLoadReply] = Queue(kind=Blocking(1))
  let request : FollowerLoadRequest = { reply, active: true }
  // The request must be present before its collapsed control signal. A full
  // queue backpressures here; once accepted, either the current Load scan
  // drains it or this caller schedules the next generation.
  follower.load_requests.put(request) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return LoadStopped
  }
  if request.active && !follower.load_pending {
    follower.load_pending = true
    let queued = follower.inbox.try_put(Load) catch { _ => false }
    if !queued {
      follower.load_pending = false
      request.active = false
      return LoadStopped
    }
  }
  reply.get()
}

// The follower's pure core: watermark diffing over `sessions show` output
// and the store-layout fast path. The actor itself (baseline, serial loop,
// stop drain) needs a live engine binary and is exercised end to end.

///|
test "commits_after filters typed events by watermark in file order" {
  let session : @protocol.SessionDocument = {
    version: None,
    id: Some("s"),
    system_prompt: None,
    events: Some([
      { sequence: 1, ts: None, item: User({ content: "one" }) },
      { sequence: 2, ts: None, item: User({ content: "two" }) },
      { sequence: 3, ts: None, item: User({ content: "three" }) },
    ]),
  }
  let fresh = commits_after(session, 1)
  inspect(fresh.length(), content="2")
  inspect(fresh[0].sequence, content="2")
  inspect(fresh[1].sequence, content="3")
  inspect(commits_after(session, 3).length(), content="0")
}

///|
test "commits_after tolerates a session without events" {
  let session : @protocol.SessionDocument = {
    version: None,
    id: Some("s"),
    system_prompt: None,
    events: None,
  }
  inspect(commits_after(session, 0).length(), content="0")
}

///|
test "session_max_sequence is the snapshot's watermark" {
  let session : @protocol.SessionDocument = {
    version: None,
    id: Some("s"),
    system_prompt: None,
    events: Some([
      { sequence: 5, ts: None, item: User({ content: "five" }) },
      { sequence: 9, ts: None, item: User({ content: "nine" }) },
      { sequence: 7, ts: None, item: User({ content: "seven" }) },
    ]),
  }
  inspect(session_max_sequence(session), content="9")
  inspect(session_max_sequence({ ..session, events: Some([]) }), content="0")
}

///|
test "session_store_file follows the store layout" {
  let path = session_store_file(
    @pathx.Path("/tmp/store-root").resolve(),
    "desktop-abc",
  )
  assert_true(
    path.has_suffix("sessions/desktop-abc/openseek_session-desktop-abc.jsonl"),
  )
}

///|
#cfg(not(platform="windows"))
fn follower_test_config(
  engine : String,
  session : String,
  root : @pathx.Absolute,
) -> RunConfig {
  {
    task: "test",
    api_key: "test",
    api_url: None,
    model: "test",
    max_steps: 1,
    engine,
    cwd: None,
    session,
    session_root: Some(root),
  }
}

///|
#cfg(not(platform="windows"))
async test "failed final scan keeps the follower active and propagates" {
  let dir = @fs.tmpdir(prefix="openseek-follower-stop-")
  let engine = dir + "/engine.sh"
  let root : @pathx.Absolute = @pathx.Path(dir + "/root").resolve()
  let record : @pathx.Path = Path(session_store_file(root, "s-fail"))
  @fsx.ensure_dir(record.dirname())
  @fs.write_file(record.to_string(), "record", create_mode=CreateOrTruncate)
  @fs.write_file(
    engine,
    "#!/bin/sh\nprintf '%s' 'show failed' >&2\nexit 7\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let sink = EventSink(fn(_) { () })
  @async.with_task_group(group => {
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(engine, "s-fail", root),
      ),
    )
    guard manager.followers.get("s-fail") is Some(follower) else {
      fail("expected follower")
    }
    let detail = try {
      stop_follower(manager, "s-fail", writer_exited=true)
      "no error"
    } catch {
      EngineError(detail) => detail
      error if @async.is_being_cancelled() => raise error
      error => "\{error}"
    }
    assert_true(detail.contains("show failed"))
    assert_true(
      manager.followers.get("s-fail") is Some(current) &&
      physical_equal(current, follower),
    )
    assert_false(follower.stopping)
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "zero-watermark durable boundary survives a failed final scan" {
  let dir = @fs.tmpdir(prefix="openseek-follower-durable-zero-")
  let engine = dir + "/engine.sh"
  let calls = dir + "/calls"
  let session = "s-durable-zero"
  let root : @pathx.Absolute = @pathx.Path(dir + "/root").resolve()
  let record : @pathx.Path = Path(session_store_file(root, session))
  @fsx.ensure_dir(record.dirname())
  @fs.write_file(record.to_string(), "record", create_mode=CreateOrTruncate)
  let script =
    $|#!/bin/sh
    $|calls='\{calls}'
    $|count=0
    $|if [ -f "$calls" ]; then count=$(cat "$calls"); fi
    $|count=$((count + 1))
    $|printf '%s' "$count" > "$calls"
    $|case "$count" in
    $|  1) printf '%s' '{"events":[]}' ;;
    $|  2) printf '%s' 'transient show failure' >&2; exit 7 ;;
    $|  *) printf '%s' '{"events":[]}' ;;
    $|esac
    $|
  @fs.write_file(engine, script, create_mode=CreateOrTruncate)
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { emitted.push(event) })
  @async.with_task_group(group => {
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(engine, session, root),
      ),
    )
    guard manager.followers.get(session) is Some(follower) else {
      fail("expected follower")
    }
    follower.expect_durable_finish("r-durable-zero")
    follower.expect_durable_finish("r-durable-zero")
    let detail = try {
      stop_follower(manager, session, writer_exited=true)
      "no error"
    } catch {
      EngineError(detail) => detail
      error if @async.is_being_cancelled() => raise error
      error => "\{error}"
    }
    assert_true(detail.contains("transient show failure"))
    assert_true(
      follower.durable_finishes
      is [{ run_id: "r-durable-zero", published: false }],
    )
    assert_false(emitted.iter().any(event => event is DurableBoundary(_)))

    let retry_a = group.spawn(() => {
      stop_follower(manager, session, writer_exited=true)
    })
    let retry_b = group.spawn(() => {
      stop_follower(manager, session, writer_exited=true)
    })
    retry_a.wait()
    retry_b.wait()
    stop_follower(manager, session, writer_exited=true)
    let boundaries : Array[Int] = []
    for event in emitted {
      if event is DurableBoundary(payload) && payload.run_id == "r-durable-zero" {
        boundaries.push(payload.sequence)
      }
    }
    assert_eq(boundaries, [0])
    assert_true(follower.durable_finishes[0].published)
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "absent first record publishes one exact-zero durable boundary" {
  let dir = @fs.tmpdir(prefix="openseek-follower-durable-absent-")
  let engine = dir + "/engine.sh"
  let session = "s-durable-absent"
  let root : @pathx.Absolute = @pathx.Path(dir + "/root").resolve()
  @fs.write_file(
    engine,
    "#!/bin/sh\nprintf '%s' 'show failed' >&2\nexit 7\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { emitted.push(event) })
  @async.with_task_group(group => {
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(engine, session, root),
      ),
    )
    guard manager.followers.get(session) is Some(follower) else {
      fail("expected follower")
    }
    follower.expect_durable_finish("r-durable-absent")
    stop_follower(manager, session, writer_exited=true)
    stop_follower(manager, session, writer_exited=true)

    let boundaries : Array[Int] = []
    for event in emitted {
      if event is DurableBoundary(payload) &&
        payload.run_id == "r-durable-absent" {
        boundaries.push(payload.sequence)
      }
    }
    assert_eq(boundaries, [0])
    assert_true(follower.retired)
    assert_true(manager.followers.get(session) is None)
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "nonzero durable boundary survives a failed final scan" {
  let dir = @fs.tmpdir(prefix="openseek-follower-durable-tail-")
  let engine = dir + "/engine.sh"
  let calls = dir + "/calls"
  let session = "s-durable-tail"
  let root : @pathx.Absolute = @pathx.Path(dir + "/root").resolve()
  let record : @pathx.Path = Path(session_store_file(root, session))
  @fsx.ensure_dir(record.dirname())
  @fs.write_file(record.to_string(), "record", create_mode=CreateOrTruncate)
  let script =
    $|#!/bin/sh
    $|calls='\{calls}'
    $|count=0
    $|if [ -f "$calls" ]; then count=$(cat "$calls"); fi
    $|count=$((count + 1))
    $|printf '%s' "$count" > "$calls"
    $|case "$count" in
    $|  1) printf '%s' '{"events":[]}' ;;
    $|  2) printf '%s' 'transient show failure' >&2; exit 7 ;;
    $|  *) printf '%s' '{"events":[{"sequence":1,"ts":0,"item":{"kind":"user","payload":{"content":"done"}}}]}' ;;
    $|esac
    $|
  @fs.write_file(engine, script, create_mode=CreateOrTruncate)
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { emitted.push(event) })
  @async.with_task_group(group => {
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(engine, session, root),
      ),
    )
    guard manager.followers.get(session) is Some(follower) else {
      fail("expected follower")
    }
    follower.expect_durable_finish("r-durable-tail")
    stop_follower(manager, session, writer_exited=true) catch {
      EngineError(detail) =>
        assert_true(detail.contains("transient show failure"))
      error if @async.is_being_cancelled() => raise error
      error => raise error
    }

    stop_follower(manager, session, writer_exited=true)
    let relevant : Array[EngineEvent] = []
    for event in emitted {
      match event {
        SessionCommit(payload) if payload.session == session =>
          relevant.push(event)
        DurableBoundary(payload) if payload.run_id == "r-durable-tail" =>
          relevant.push(event)
        _ => ()
      }
    }
    assert_true(
      relevant
      is [
        SessionCommit({ sequence: 1, .. }),
        DurableBoundary({ sequence: 1, .. }),
      ],
    )
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "abrupt EOF retains a failed final drain for later boundary retry" {
  let dir = @fs.tmpdir(prefix="openseek-follower-abrupt-eof-")
  let engine_path = dir + "/engine.sh"
  let calls = dir + "/calls"
  let session = "s-abrupt-eof"
  let root : @pathx.Absolute = @pathx.Path(dir + "/root").resolve()
  let record : @pathx.Path = Path(session_store_file(root, session))
  @fsx.ensure_dir(record.dirname())
  @fs.write_file(record.to_string(), "record", create_mode=CreateOrTruncate)
  let script =
    $|#!/bin/sh
    $|calls='\{calls}'
    $|count=0
    $|if [ -f "$calls" ]; then count=$(cat "$calls"); fi
    $|count=$((count + 1))
    $|printf '%s' "$count" > "$calls"
    $|case "$count" in
    $|  1) printf '%s' '{"events":[]}' ;;
    $|  2) printf '%s' 'transient show failure' >&2; exit 7 ;;
    $|  *) printf '%s' '{"events":[]}' ;;
    $|esac
    $|
  @fs.write_file(engine_path, script, create_mode=CreateOrTruncate)
  assert_eq(@process.run("chmod", ["+x", engine_path]), 0)
  let manager = new_engine_manager(engine_path)
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { emitted.push(event) })
  @async.with_task_group(group => {
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(engine_path, session, root),
      ),
    )
    guard manager.followers.get(session) is Some(follower) else {
      fail("expected follower")
    }
    let (child_stdin, writer) = @process.write_to_process()
    let process = @process.spawn(
      group,
      "/bin/sh",
      ["-c", "exit 7"],
      stdin=child_stdin,
      no_wait=true,
    )
    let engine : ServeEngine = {
      session_key: session,
      session_root: Some(root),
      spec_key: "test",
      writer,
      command_lock: Mutex(),
      process,
      sink,
      follower: Some(follower),
      exit: { process_done: false, done: false },
      latest_run: Some("r-abrupt-eof"),
      phase: Running(cancel_requested=false, compact_queued=false),
      accepts_commands: true,
      steer_runs: SteerRunTracker::new(),
    }
    let sessions : Map[String, SessionSlot] = Map([])
    let slot = slot_for(sessions, session)
    slot.engine = Some(engine)
    manager.pump = Serving(sessions~)
    let messages : @async.Queue[StreamMessage] = Queue(
      kind=Blocking(EngineStreamQueueSize),
    )
    messages.put(StreamExited(7))
    let stderr_task = group.spawn(no_wait=true, () => "")
    engine.run(manager, messages, stderr_task)

    assert_true(engine.exit.done)
    assert_true(slot.engine is None)
    assert_true(
      follower.durable_finishes
      is [{ run_id: "r-abrupt-eof", published: false }],
    )
    let mut finished_index = -1
    let mut early_boundaries = 0
    for index, event in emitted {
      match event {
        Finished(payload) if payload.run_id == "r-abrupt-eof" => {
          assert_true(payload.durable_sequence is None)
          finished_index = index
        }
        DurableBoundary(payload) if payload.run_id == "r-abrupt-eof" =>
          early_boundaries = early_boundaries + 1
        _ => ()
      }
    }
    assert_true(finished_index >= 0)
    assert_eq(early_boundaries, 0)

    stop_follower(manager, session, writer_exited=true)
    let mut boundary_index = -1
    let mut boundary_count = 0
    for index, event in emitted {
      if event is DurableBoundary(payload) && payload.run_id == "r-abrupt-eof" {
        assert_eq(payload.sequence, 0)
        boundary_index = index
        boundary_count = boundary_count + 1
      }
    }
    assert_eq(boundary_count, 1)
    assert_true(boundary_index > finished_index)
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "workspace detach drains an orphaned pending follower before commit" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let dir = @fs.tmpdir(prefix="openseek-detach-orphan-follower-")
  let global_root : @pathx.Absolute = @pathx.Path(dir + "/global").resolve()
  let workspace : @pathx.Absolute = @pathx.Path(dir + "/workspace").resolve()
  let root = workspace_session_root(workspace)
  let engine_path = dir + "/engine.sh"
  let calls = dir + "/calls"
  let session = "s-detach-orphan"
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", global_root.to_string())
  defer restore_session_root_env(previous)
  @fsx.ensure_dir(workspace.to_path())
  ignore(attach_workspace(workspace.to_string(), fn(_) { () }))
  let record : @pathx.Path = Path(session_store_file(root, session))
  @fsx.ensure_dir(record.dirname())
  @fs.write_file(record.to_string(), "record", create_mode=CreateOrTruncate)
  let script =
    $|#!/bin/sh
    $|calls='\{calls}'
    $|count=0
    $|if [ -f "$calls" ]; then count=$(cat "$calls"); fi
    $|count=$((count + 1))
    $|printf '%s' "$count" > "$calls"
    $|case "$count" in
    $|  1) printf '%s' '{"events":[]}' ;;
    $|  2) printf '%s' 'transient show failure' >&2; exit 7 ;;
    $|  *) printf '%s' '{"events":[]}' ;;
    $|esac
    $|
  @fs.write_file(engine_path, script, create_mode=CreateOrTruncate)
  assert_eq(@process.run("chmod", ["+x", engine_path]), 0)
  let manager = new_engine_manager(engine_path)
  let sessions : Map[String, SessionSlot] = Map([])
  manager.pump = Serving(sessions~)
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { emitted.push(event) })
  @async.with_task_group(group => {
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(engine_path, session, root),
      ),
    )
    guard manager.followers.get(session) is Some(follower) else {
      fail("expected follower")
    }
    follower.expect_durable_finish("r-detach-orphan")
    stop_follower(manager, session, writer_exited=true) catch {
      EngineError(detail) =>
        assert_true(detail.contains("transient show failure"))
      error if @async.is_being_cancelled() => raise error
      error => raise error
    }
    assert_false(follower.retired)

    let committed_after_boundary : Ref[Bool] = Ref(false)
    let detached = detach_workspace(manager, workspace.to_string(), fn(_) {
      committed_after_boundary.val = emitted
        .iter()
        .any(event => {
          event
          is DurableBoundary({ run_id: "r-detach-orphan", sequence: 0, .. })
        })
    })
    assert_true(committed_after_boundary.val)
    assert_eq(detached.workspaces, [])
    assert_true(follower.retired)
    assert_true(manager.followers.get(session) is None)
    let boundaries : Array[Int] = []
    for event in emitted {
      if event is DurableBoundary(payload) &&
        payload.run_id == "r-detach-orphan" {
        boundaries.push(payload.sequence)
      }
    }
    assert_eq(boundaries, [0])
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "workspace detach refuses an idle engine whose follower cannot drain" {
  let dir = @fs.tmpdir(prefix="openseek-detach-follower-stop-")
  let workspace : @pathx.Absolute = @pathx.Path(dir + "/workspace").resolve()
  let root = workspace_session_root(workspace)
  let engine_path = dir + "/engine.sh"
  let session = "s-detach-fail"
  let record : @pathx.Path = Path(session_store_file(root, session))
  @fsx.ensure_dir(record.dirname())
  @fs.write_file(record.to_string(), "record", create_mode=CreateOrTruncate)
  @fs.write_file(
    engine_path,
    "#!/bin/sh\nprintf '%s' 'show failed' >&2\nexit 7\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine_path]), 0)
  let manager = new_engine_manager(engine_path)
  let sink = EventSink(fn(_) { () })
  @async.with_task_group(group => {
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(engine_path, session, root),
      ),
    )
    guard manager.followers.get(session) is Some(follower) else {
      fail("expected follower")
    }
    let (child_stdin, writer) = @process.write_to_process()
    let process = @process.spawn(
      group,
      "/bin/sh",
      ["-c", "sleep 30"],
      stdin=child_stdin,
      cancel_handler=@process.graceful_cancel(timeout=10),
      no_wait=true,
    )
    let engine : ServeEngine = {
      session_key: session,
      session_root: Some(root),
      spec_key: "test",
      writer,
      command_lock: Mutex(),
      process,
      sink,
      follower: Some(follower),
      // The real EOF consumer reaches this state after its first failed final
      // scan. Detach must retry the still-live follower and propagate again.
      exit: { process_done: true, done: true },
      latest_run: Some("r-detach-fail"),
      phase: Idle,
      accepts_commands: false,
      steer_runs: SteerRunTracker::new(),
    }
    let sessions : Map[String, SessionSlot] = Map([])
    let slot = slot_for(sessions, session)
    slot.engine = Some(engine)
    manager.pump = Serving(sessions~)
    let detail = try {
      manager.close_engines_for_workspace(workspace)
      "no error"
    } catch {
      EngineError(detail) => detail
      error if @async.is_being_cancelled() => raise error
      error => "\{error}"
    }
    assert_true(detail.contains("show failed"))
    assert_true(
      manager.followers.get(session) is Some(current) &&
      physical_equal(current, follower),
    )
    assert_false(follower.stopping)
    discard_follower_startup(manager, follower)
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "record stat failure is not mistaken for an empty final drain" {
  let dir = @fs.tmpdir(prefix="openseek-follower-stat-")
  let engine = dir + "/engine.sh"
  let root : @pathx.Absolute = @pathx.Path(dir + "/not-a-directory").resolve()
  // Looking up the pinned record beneath a regular file deterministically
  // raises ENOTDIR. That verification failure must complete Stop as failed
  // and leave the actor installed, never masquerade as ENOENT.
  @fs.write_file(root.to_string(), "file", create_mode=CreateOrTruncate)
  @fs.write_file(
    engine,
    "#!/bin/sh\nprintf '%s' 'show failed' >&2\nexit 7\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let sink = EventSink(fn(_) { () })
  @async.with_task_group(group => {
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(engine, "s-stat", root),
      ),
    )
    guard manager.followers.get("s-stat") is Some(follower) else {
      fail("expected follower")
    }
    let detail = try {
      stop_follower(manager, "s-stat", writer_exited=true)
      "no error"
    } catch {
      EngineError(detail) => detail
      error if @async.is_being_cancelled() => raise error
      error => "\{error}"
    }
    assert_true(detail.contains("show failed"))
    assert_true(detail.contains("failed to verify session record"))
    assert_true(
      manager.followers.get("s-stat") is Some(current) &&
      physical_equal(current, follower),
    )
    assert_false(follower.stopping)
    discard_follower_startup(manager, follower)
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "root change retires the old follower before installing another" {
  let dir = @fs.tmpdir(prefix="openseek-follower-root-")
  let engine = dir + "/engine.sh"
  @fs.write_file(
    engine,
    "#!/bin/sh\nprintf '%s' '{\"events\":[]}'\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let sink = EventSink(fn(_) { () })
  let root_a : @pathx.Absolute = @pathx.Path(dir + "/a").resolve()
  let root_b : @pathx.Absolute = @pathx.Path(dir + "/b").resolve()
  @async.with_task_group(group => {
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(engine, "s-root", root_a),
      ),
    )
    guard manager.followers.get("s-root") is Some(first) else {
      fail("expected first follower")
    }
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(engine, "s-root", root_b),
      ),
    )
    guard manager.followers.get("s-root") is Some(second) else {
      fail("expected replacement follower")
    }
    assert_false(physical_equal(first, second))
    assert_eq(second.root.to_string(), root_b.to_string())
    discard_follower_startup(manager, second)
  })
  @fs.rmdir(dir, recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "one Load control message answers a bounded request batch" {
  let dir = @fs.tmpdir(prefix="openseek-follower-load-")
  let engine = dir + "/engine.sh"
  let count = dir + "/count"
  @fs.write_file(
    engine,
    "#!/bin/sh\nn=0\nif [ -f '\{count}' ]; then n=$(cat '\{count}'); fi\nn=$((n + 1))\nprintf '%s' \"$n\" > '\{count}'\nprintf '%s' '{\"events\":[]}'\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let sink = EventSink(fn(_) { () })
  @async.with_task_group(group => {
    ignore(
      ensure_follower(
        sink~,
        group~,
        manager~,
        config=follower_test_config(
          engine,
          "s-load",
          @pathx.Path(dir + "/root").resolve(),
        ),
      ),
    )
    guard manager.followers.get("s-load") is Some(follower) else {
      fail("expected follower")
    }
    let replies : Array[@async.Queue[FollowerLoadReply]] = []
    for _ in 0..<8 {
      let reply : @async.Queue[FollowerLoadReply] = Queue(kind=Blocking(1))
      replies.push(reply)
      follower.load_requests.put({ reply, active: true })
    }
    follower.load_pending = true
    assert_true(follower.inbox.try_put(Load))
    for reply in replies {
      assert_true(reply.get() is LoadOk(_))
    }
    assert_eq(@fs.read_file(count).text(), "2")
    discard_follower_startup(manager, follower)
  })
  @fs.rmdir(dir, recursive=true)
}

///|
fn follower_state_fixture(session : String) -> SessionFollower {
  {
    session,
    root: @pathx.Path("/tmp/follower-state-fixture").resolve(),
    inbox: Queue(kind=Blocking(3)),
    load_requests: Queue(kind=Blocking(1)),
    kick_pending: false,
    load_pending: false,
    stopping: false,
    retired: false,
    stop_generation: 0,
    completed_stop_generation: 0,
    completed_stop_error: None,
    stop_observers: 0,
    durable_finishes: [],
    watermark: 0,
    consumed: None,
  }
}

///|
#cfg(not(platform="windows"))
async test "failed command stays unusable through close timeout and repeated cancel" {
  let manager = new_engine_manager("unused")
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(fn(event) { emitted.push(event) })
  let follower = follower_state_fixture("s-timeout")
  manager.followers["s-timeout"] = follower
  @async.with_task_group(group => {
    let (child_stdin, writer) = @process.write_to_process()
    let process = @process.spawn(
      group,
      "/bin/sh",
      ["-c", "sleep 30"],
      stdin=child_stdin,
      cancel_handler=@process.graceful_cancel(timeout=10),
      no_wait=true,
    )
    let engine : ServeEngine = {
      session_key: "s-timeout",
      session_root: None,
      spec_key: "test",
      writer,
      command_lock: Mutex(),
      process,
      sink,
      follower: Some(follower),
      exit: { process_done: false, done: false },
      latest_run: Some("r-timeout"),
      phase: Running(cancel_requested=false, compact_queued=false),
      accepts_commands: true,
      steer_runs: SteerRunTracker::new(),
    }
    let sessions : Map[String, SessionSlot] = Map([])
    let slot = slot_for(sessions, "s-timeout")
    slot.engine = Some(engine)
    manager.pump = Serving(sessions~)
    let cleanup = group.spawn(() => {
      retire_failed_command(manager, engine, "partial command")
    })
    @async.sleep(20)
    cleanup.cancel()
    @async.sleep(20)
    cleanup.cancel()
    let cancelled = try {
      cleanup.wait()
      false
    } catch {
      error if @async.is_cancellation_error(error) => true
      _ => false
    }
    assert_true(cancelled)
    assert_false(engine.accepts_commands)
    assert_true(engine.phase is Idle)
    assert_true(engine.latest_run is None)
    assert_true(
      follower.durable_finishes is [{ run_id: "r-timeout", published: false }],
    )
    assert_false(engine.exit.done)
    assert_true(slot.engine is Some(current) && physical_equal(current, engine))
    assert_true(
      manager.followers.get("s-timeout") is Some(current) &&
      physical_equal(current, follower),
    )
    assert_false(follower.retired)
    assert_true(open_run_engine(manager, run_id="r-timeout") is None)
    let mut errors = 0
    let mut finishes = 0
    for event in emitted {
      match event {
        Error(payload) if payload.run_id == Some("r-timeout") =>
          errors = errors + 1
        Finished(payload) if payload.run_id == "r-timeout" => {
          assert_true(payload.durable_sequence is None)
          finishes = finishes + 1
        }
        _ => ()
      }
    }
    assert_eq(errors, 1)
    assert_eq(finishes, 1)
    discard_follower_startup(manager, follower)
    group.return_immediately(())
  })
}

///|
test "startup rollback closes waiters and preserves a successor identity" {
  let manager = new_engine_manager("unused")
  let abandoned = follower_state_fixture("s-startup")
  let reply : @async.Queue[FollowerLoadReply] = Queue(kind=Blocking(1))
  let request : FollowerLoadRequest = { reply, active: true }
  assert_true(abandoned.load_requests.try_put(request))
  manager.followers["s-startup"] = abandoned
  discard_follower_startup(manager, abandoned)
  assert_true(manager.followers.get("s-startup") is None)
  assert_false(request.active)
  assert_true(reply.try_get() is Some(LoadStopped))
  assert_false(abandoned.inbox.try_put(Kick) catch { _ => false })

  let stale = follower_state_fixture("s-startup")
  let successor = follower_state_fixture("s-startup")
  manager.followers["s-startup"] = successor
  discard_follower_startup(manager, stale)
  assert_true(
    manager.followers.get("s-startup") is Some(current) &&
    physical_equal(current, successor),
  )
  assert_true(successor.inbox.try_put(Kick))
}

///|
test "pump reset completes every queued follower load" {
  let manager = new_engine_manager("unused")
  let follower = follower_state_fixture("s-reset")
  let reply : @async.Queue[FollowerLoadReply] = Queue(kind=Blocking(1))
  let request : FollowerLoadRequest = { reply, active: true }
  assert_true(follower.load_requests.try_put(request))
  manager.followers["s-reset"] = follower
  manager.pump = Serving(sessions=Map([]))
  reset_engine_generation(manager, Ref(None))
  assert_true(manager.pump is Stopped)
  assert_true(manager.followers.get("s-reset") is None)
  assert_false(request.active)
  assert_true(reply.try_get() is Some(LoadStopped))
}

///|
async test "identity-scoped stop never retires a successor" {
  let manager = new_engine_manager("unused")
  let departed = follower_state_fixture("s-exit")
  let successor = follower_state_fixture("s-exit")
  manager.followers["s-exit"] = successor
  stop_follower_instance(manager, departed, writer_exited=false)
  assert_true(
    manager.followers.get("s-exit") is Some(current) &&
    physical_equal(current, successor),
  )
  assert_false(successor.stopping)
  assert_true(successor.inbox.try_get() is None)
}

///|
#cfg(not(platform="windows"))
async test "cancelling follower baseline removes its startup identity" {
  let dir = @fs.tmpdir(prefix="openseek-follower-cancel-")
  let engine = dir + "/engine.sh"
  @fs.write_file(
    engine,
    "#!/bin/sh\nsleep 30\nprintf '%s' '{\"events\":[]}'\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine]), 0)
  let manager = new_engine_manager(engine)
  let sink = EventSink(fn(_) { () })
  @async.with_task_group(group => {
    let startup = group.spawn(() => {
      ignore(
        ensure_follower(
          sink~,
          group~,
          manager~,
          config=follower_test_config(
            engine,
            "s-cancel",
            @pathx.Path(dir + "/root").resolve(),
          ),
        ),
      )
    })
    while manager.followers.get("s-cancel") is None {
      @async.pause()
    }
    startup.cancel()
    let cancelled = try {
      startup.wait()
      false
    } catch {
      error if @async.is_cancellation_error(error) => true
      _ => false
    }
    assert_true(cancelled)
    assert_true(manager.followers.get("s-cancel") is None)
    group.return_immediately(())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "load request is queued before its collapsed control message" {
  let follower = follower_state_fixture("s-order")
  @async.with_task_group(group => {
    let caller = group.spawn(() => request_follower_load(follower))
    assert_true(follower.inbox.get() is Load)
    let request = follower.load_requests.get()
    assert_true(request.active)
    request.active = false
    request.reply.put(
      LoadOk({ version: None, id: None, system_prompt: None, events: Some([]) }),
    )
    assert_true(caller.wait() is LoadOk(_))
  })
}

///|
async test "backpressured load schedules the next control generation" {
  let follower = follower_state_fixture("s-backpressure")
  let placeholder : @async.Queue[FollowerLoadReply] = Queue(kind=Blocking(1))
  follower.load_requests.put({ reply: placeholder, active: false })
  follower.load_pending = true
  @async.with_task_group(group => {
    let caller = group.spawn(() => request_follower_load(follower))
    @async.pause()
    // Freeing the sole request slot accepts and wakes the blocked caller.
    // Model the previous Load generation finishing before that caller runs.
    ignore(follower.load_requests.get())
    follower.load_pending = false
    assert_true(follower.inbox.get() is Load)
    let request = follower.load_requests.get()
    assert_true(request.active)
    request.active = false
    request.reply.put(
      LoadOk({ version: None, id: None, system_prompt: None, events: Some([]) }),
    )
    assert_true(caller.wait() is LoadOk(_))
  })
}

///|
async test "stop requires its generation proof when follower identity vanishes" {
  let manager = new_engine_manager("unused")
  let follower = follower_state_fixture("s-stop-proof")
  manager.followers["s-stop-proof"] = follower
  @async.with_task_group(group => {
    let caller = group.spawn(() => {
      try {
        stop_follower(manager, "s-stop-proof", writer_exited=false)
        "no error"
      } catch {
        EngineError(detail) => detail
        error if @async.is_being_cancelled() => raise error
        error => "\{error}"
      }
    })
    guard follower.inbox.get() is Stop(generation~, ..) else {
      fail("expected Stop")
    }
    manager.followers.remove("s-stop-proof")
    let detail = caller.wait()
    assert_true(detail.contains("without completing"))

    let completed = follower_state_fixture("s-stop-complete")
    manager.followers["s-stop-complete"] = completed
    let successful = group.spawn(() => {
      stop_follower(manager, "s-stop-complete", writer_exited=false)
      true
    })
    guard completed.inbox.get() is Stop(generation=completed_generation, ..) else {
      fail("expected second Stop")
    }
    completed.completed_stop_generation = completed_generation
    completed.completed_stop_error = None
    manager.followers.remove("s-stop-complete")
    assert_true(successful.wait())
    ignore(generation)
  })
}
