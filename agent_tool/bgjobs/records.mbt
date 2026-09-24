///|
fn artifact_basename(path : String) -> String {
  let path = path.replace_all(old="\\", new="/")
  match path.rev_split_once("/") {
    Some((_, name)) => name.to_owned()
    None => path
  }
}

///|
fn BgJob::record(self : BgJob, runtime : BgJobRuntime) -> @protocol.JobRecord {
  let state : @protocol.JobState = match self.exec.status() {
    Exited(_) | Killed if self.phase is (Live | Finishing) => Stopping
    Running | Backgrounded =>
      if self.requested_stop {
        Stopping
      } else {
        Running
      }
    Exited(code) => Exited(code)
    Killed =>
      Stopped(
        if self.exec.output_error() is Some(_) {
          "capture_failed"
        } else if self.exec.killed_by_output_limit() {
          "output_limit"
        } else if self.exec.killed_by_time_limit() {
          "time_limit"
        } else if self.requested_stop {
          "user"
        } else {
          "session_ended"
        },
      )
  }
  {
    generation: runtime.generation,
    id: self.id,
    revision: self.revision,
    command: self.command,
    description: self.description,
    cwd: self.exec.cwd(),
    state,
    started_at_ms: self.exec.started_at_ms(),
    backgrounded_at_ms: self.backgrounded_at_ms,
    finished_at_ms: self.exec.finished_at_ms(),
    last_output_at_ms: self.exec.last_output_at_ms(),
    output_file: self.exec.spill_path().map(artifact_basename),
    output_persistent: runtime.persistent_logs,
    output_bytes: self.exec.output_bytes(),
    output_chars: self.exec.size(),
    output_truncated: self.exec.output_truncated(),
    invalid_utf8: self.exec.had_invalid_utf8(),
    output_error: self.exec.output_error(),
    persistence_error: self.persistence_error,
    cleanup_error: self.cleanup_error,
    data: self.data.map(get => get()),
  }
}

///|
/// The current runtime's opaque generation, used to reject stale controls.
pub fn BgJobRuntime::generation(self : BgJobRuntime) -> String {
  self.generation
}

///|
/// Current-runtime snapshots whose first publication has been attempted.
/// Unlike list()/snapshot(), this excludes jobs still being registered. The
/// Desktop host reads durable history separately from session metadata files.
pub fn BgJobRuntime::records(self : BgJobRuntime) -> Array[@protocol.JobRecord] {
  [
    for _, job in self.jobs if job.announced => job.record(self)
  ]
}

///|
/// Started and Updated events can be frequent (a program's trace publishes on
/// every nested call), so their storage write is bounded: a slow disk must not
/// stall every other job's publication behind the lock. The one terminal write
/// is exempt. It happens once per job, nothing retries it later, and a restart
/// reads it to learn that the job is over; late beats lost.
fn persistence_deadline_ms(kind : @protocol.JobEventKind) -> Int? {
  match kind {
    Finished | Failed => None
    Started | Updated => Some(5000)
  }
}

///|
async fn BgJobRuntime::publish(
  self : BgJobRuntime,
  id : String,
  kind : @protocol.JobEventKind,
) -> Unit {
  self.publish_record(id, kind, persistence_deadline_ms(kind), record => {
    if self.persistent_logs && self.spill_dir is Some(dir) {
      let path = "\{dir}/\{@protocol.job_storage_name(id)}.json"
      let temporary = "\{path}.tmp"
      @fs.write_file(
        temporary,
        record.to_json().stringify(),
        create_mode=CreateOrTruncate,
        sync=Data,
        permission=0o600,
      )
      @fs.rename(temporary, path, replace=true)
      sync_job_directories(dir)
    }
  })
}

///|
/// Keep publication ordered and, when a deadline is given, bound the storage
/// work. Submitted I/O still has to settle safely; this is not a hard kill of
/// kernel operations. In-memory records and events carry a persistence
/// failure on timeout.
async fn BgJobRuntime::publish_record(
  self : BgJobRuntime,
  id : String,
  kind : @protocol.JobEventKind,
  persistence_timeout_ms : Int?,
  persist : async (@protocol.JobRecord) -> Unit,
) -> Unit {
  self.publish_lock.acquire()
  defer self.publish_lock.release()
  // A release can grant the lock to a waiter that was cancelled before it
  // resumed. Yielding here lets the runtime raise its own cancellation signal,
  // so the caller's task group sees a cancellation rather than a failure.
  if @async.is_being_cancelled() {
    @async.pause()
  }
  guard self.jobs.get(id) is Some(job) else { return }
  if kind == Updated && job.phase == Published {
    return
  }
  if kind != Started {
    job.revision += 1
  }
  job.persistence_error = None
  // One immutable revision is shared by persistence and the lifecycle event.
  // Execution status/output may advance while filesystem writes are awaiting.
  let record = job.record(self)
  try {
    match persistence_timeout_ms {
      Some(ms) => @async.with_timeout(ms, () => persist(record))
      None => persist(record)
    }
  } catch {
    @async.WaitedTaskAlreadyCancelled as error => raise error
    error => job.persistence_error = Some("failed to persist job: \{error}")
  }
  job.announced = true
  if self.on_job_event is Some(publish) {
    publish(kind, { ..record, persistence_error: job.persistence_error, })
  }
}

///|
/// Make the metadata rename and new generation/jobs directory entries durable
/// where directory sync is supported, matching the session store's best-effort
/// policy. This does not add per-chunk fsync to the output stream.
async fn sync_job_directories(dir : String) -> Unit {
  for path in [dir, "\{dir}/..", "\{dir}/../.."] {
    let directory = @fs.open(path, mode=ReadOnly) catch { _ => continue }
    defer directory.close()
    directory.sync() catch {
      _ => ()
    }
  }
}

///|
async fn BgJobRuntime::finish_job(self : BgJobRuntime, id : String) -> Unit {
  @async.protect_from_cancel(() => {
    guard self.jobs.get(id) is Some(job) && job.phase != Published else {
      return
    }
    if job.phase != Live {
      while job.phase != Published {
        self.settled.wait()
      }
      return
    }
    job.phase = Finishing
    if job.on_terminal is Some(cleanup) {
      job.on_terminal = None
      cleanup() catch {
        error => job.cleanup_error = Some("\{error}")
      }
    }
    // Completed jobs retain immutable data, not the live supplier and all the
    // program/runtime resources it captured.
    job.data = job.data.map(supply => {
      let final_data = supply()
      () => final_data
    })
    job.phase = CleanedUp
    let record = job.record(self)
    let failed = match record.state {
      Exited(code) => code != 0
      Stopped(reason) => reason != "user" && reason != "session_ended"
      _ => false
    }
    self.publish(
      id,
      if failed || job.cleanup_error is Some(_) {
        Failed
      } else {
        Finished
      },
    )
    if self.on_job_exit is Some(callback) &&
      self.snapshot(id) is Some(snapshot) &&
      (
        snapshot.status is Exited(_) ||
        snapshot.killed_by_output_limit ||
        snapshot.killed_by_time_limit ||
        snapshot.output_error is Some(_)
      ) {
      callback(snapshot)
    }
    job.phase = Published
    self.settled.broadcast()
  })
}

///|
/// Finalize after the owning group has joined its children, under cancellation
/// protection. No live process or writer remains when terminal metadata is saved.
pub async fn BgJobRuntime::finalize(self : BgJobRuntime) -> Unit {
  for id, _ in self.jobs {
    self.finish_job(id)
  }
}

///|
/// Publish fresh launcher metadata under the owning job. Terminal records have
/// the final snapshot and never receive a later Updated event.
pub async fn BgJobRuntime::metadata_changed(
  self : BgJobRuntime,
  id : String,
) -> Unit {
  self.publish(id, Updated)
  // A live job's metadata is only as durable as the record that carries it:
  // a publication that could not be persisted must reach the caller, which
  // retains it as a trace error and fails the job at its end.
  if self.jobs.get(id) is Some(job) &&
    job.phase != Published &&
    job.persistence_error is Some(error) {
    fail("job metadata not persisted: \{error}")
  }
}
