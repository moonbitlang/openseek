// The idle reaper: stops serve processes nobody has used for a while.
//
// An engine is spawned by the first op that needs one and, left alone, lives
// until the app exits, so a long session accumulates one process (and one
// polling follower) per conversation ever prompted. Nothing conversational
// lives in that process — the durable record is the only memory, and the next
// start spawns a fresh engine against it — so an engine that has sat between
// turns long enough is stopped the same way a workspace detach stops one:
// stdin EOF, then the follower's final scan.

///|
/// How long an engine may sit between turns, untouched, before it is stopped:
/// twelve hours.
///
/// Generous on purpose. An idle engine costs little — a few megabytes and a
/// follower's poll — so there is nothing to win by reclaiming one promptly,
/// and stopping it has a price: the next prompt waits for a spawn, and what
/// the process held beyond the record (its tool state, its caches) starts
/// over. The deadline is here to bound how many engines an app left open for
/// days can accumulate, so it only has to be shorter than that: a
/// conversation used in the morning still has its engine in the afternoon,
/// and one untouched since yesterday does not.
const EngineIdleTimeoutMs : Int64 = 43200000L

///|
/// How often the reaper looks. An engine therefore outlives its deadline by at
/// most this much.
const EngineIdleScanMs = 60000

///|
/// Wall-clock milliseconds, as engine activity stamps record them. Wall time
/// on purpose: a machine that slept for the night comes back with engines
/// that really were idle that long.
fn engine_clock_ms() -> Int64 {
  @sys.now().reinterpret_as_int64()
}

///|
/// Record that this engine did, or was asked to do, something just now.
fn ServeEngine::touch(self : ServeEngine) -> Unit {
  self.last_activity_ms = engine_clock_ms()
}

///|
/// The engine in this slot, when the host may stop it: nothing is being
/// prepared against the slot, the engine is between turns with nothing queued
/// behind it, nobody is waiting on a job reply from it, and it has gone
/// untouched for `idle_ms`.
///
/// A pending approval needs no check of its own: a tool can only ask inside
/// an open turn, and an open turn is `Running`.
fn SessionSlot::idle_engine(
  self : SessionSlot,
  now~ : Int64,
  idle_ms~ : Int64,
) -> ServeEngine? {
  guard self.pending is None &&
    self.live() is Some(engine) &&
    engine.phase is Idle(..) &&
    engine.queued_runs.is_empty() &&
    engine.job_requests.is_empty() &&
    now - engine.last_activity_ms >= idle_ms else {
    return None
  }
  Some(engine)
}

///|
/// Whether this engine's background jobs give a reason to keep it — or it
/// would not say. Only the engine knows: jobs are children of the serve
/// process, and a finished one wakes its idle engine to record the notice.
///
/// A job counts against stopping while it runs, and for a full deadline after
/// it ends. The second half is not a courtesy. A job's state reads as
/// terminal from the moment its process exits, which is before the engine has
/// published the record and queued the completion notice; an engine stopped
/// in that window would take the notice with it. Treating a recent finish as
/// activity keeps the reaper out of the window without having to know how
/// wide it is. A terminal job with no finish time is one this cannot date, so
/// it counts too.
///
/// An unanswered or unexpected reply is "yes" as well: the reaper only stops
/// an engine it has positive evidence about, and asks again on its next scan.
async fn ServeEngine::jobs_hold_engine(
  self : ServeEngine,
  now~ : Int64,
  idle_ms~ : Int64,
) -> Bool {
  let reply = try {
    let request_id = @uuid.mint()
    self.job_request(request_id, JobsSnapshot(request_id~))
  } catch {
    _ => return true
  }
  guard reply is JobsSnapshot(jobs~, ..) else { return true }
  jobs.any(job => {
    guard job.state.is_terminal() && job.finished_at_ms is Some(finished) else {
      return true
    }
    now - finished < idle_ms
  })
}

///|
/// Stop every engine that has been idle for `idle_ms` as of `now`, and return
/// the sessions whose engines were stopped. The clock is a parameter so the
/// decision can be exercised without waiting for it.
///
/// No lock is held, unlike the detach drains this otherwise resembles: those
/// hold `workspace_lifecycle_lock` for the registry commit that follows, and
/// there is none here. What keeps a concurrent op safe is that the last look
/// at the slot and the condemnation are one synchronous step. An op that
/// claimed the slot before it is seen and the engine left alone; one that
/// arrives after finds no live engine, asks the pump for one, and the pump
/// joins this close before spawning — the same barrier a config-change
/// replacement takes.
async fn EngineManager::reap_idle_engines(
  self : EngineManager,
  now~ : Int64,
  idle_ms~ : Int64,
) -> Array[String] {
  guard self.pump is Serving(sessions~) else { return [] }
  let candidates : Array[(SessionSlot, ServeEngine)] = []
  for _, slot in sessions {
    if slot.idle_engine(now~, idle_ms~) is Some(engine) {
      candidates.push((slot, engine))
    }
  }
  let reaped : Array[String] = []
  for candidate in candidates {
    let (slot, engine) = candidate
    let seen = engine.last_activity_ms
    guard !engine.jobs_hold_engine(now~, idle_ms~) else { continue }
    // The probe suspended, so everything read before it is stale: a prompt
    // may have opened a turn, an op may have claimed the slot, the pump may
    // have been replaced. Look again, and require that nothing touched the
    // engine meanwhile — then condemn without suspending in between
    // (`close_and_wait` condemns before its first wait).
    guard self.pump is Serving(sessions=current) &&
      physical_equal(current, sessions) &&
      slot.idle_engine(now~, idle_ms~) is Some(still) &&
      physical_equal(still, engine) &&
      engine.last_activity_ms == seen else {
      continue
    }
    @xlog.info() <?
      {
        "event": "desktop_engine_idle_stop",
        "session": engine.session_key,
        "pid": engine.process.pid,
        "idle_ms": Json::number((now - seen).to_double()),
      }
    engine.close_and_wait() catch {
      error => {
        @xlog.warn() <?
          {
            "event": "desktop_engine_idle_stop_failed",
            "session": engine.session_key,
            "error": "\{error}",
          }
        continue
      }
    }
    // EOF retirement keeps a follower whose final scan failed, for a later
    // lifecycle drain to retry. Retry once here too: left installed it would
    // go on polling a record nothing writes. A second failure is not this
    // pass's to report — the next spawn, archive or detach joins it.
    if engine.follower is Some(follower) {
      stop_follower_instance(self, follower, writer_exited=true) catch {
        error =>
          @xlog.debug() <?
            {
              "event": "desktop_follower_final_scan_failed",
              "session": engine.session_key,
              "error": "\{error}",
            }
      }
    }
    reaped.push(engine.session_key)
  }
  reaped
}

///|
/// The reaper's loop, for one pump generation's lifetime.
async fn EngineManager::reap_idle_engines_forever(self : EngineManager) -> Unit {
  for ;; {
    @async.sleep(EngineIdleScanMs)
    ignore(
      self.reap_idle_engines(now=engine_clock_ms(), idle_ms=EngineIdleTimeoutMs),
    )
  }
}
