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
  }
}

///|
/// The current runtime's opaque generation, used to reject stale controls.
pub fn BgJobRuntime::generation(self : BgJobRuntime) -> String {
  self.generation
}

///|
/// Current-runtime snapshots only. The Desktop host reads durable history
/// separately from the session metadata files.
pub fn BgJobRuntime::records(self : BgJobRuntime) -> Array[@protocol.JobRecord] {
  [
    for _, job in self.jobs => job.record(self)
  ]
}

///|
async fn BgJobRuntime::publish(
  self : BgJobRuntime,
  id : String,
  kind : @protocol.JobEventKind,
) -> Unit {
  self.publish_lock.acquire()
  defer self.publish_lock.release()
  guard self.jobs.get(id) is Some(job) else { return }
  if kind != Started {
    job.revision += 1
  }
  job.persistence_error = None
  // One immutable revision is shared by persistence and the lifecycle event.
  // Execution status/output may advance while filesystem writes are awaiting.
  let record = job.record(self)
  if self.persistent_logs && self.spill_dir is Some(dir) {
    let path = "\{dir}/\{id}.json"
    let temporary = "\{path}.tmp"
    try {
      @fs.write_file(
        temporary,
        record.to_json().stringify(),
        create_mode=CreateOrTruncate,
        sync=Data,
        permission=0o600,
      )
      @fs.rename(temporary, path, replace=true)
    } catch {
      error => job.persistence_error = Some("failed to persist job: \{error}")
    }
  }
  if self.on_job_event is Some(publish) {
    publish(kind, { ..record, persistence_error: job.persistence_error, })
  }
}

///|
async fn BgJobRuntime::finish_job(self : BgJobRuntime, id : String) -> Unit {
  @async.protect_from_cancel(() => {
    guard self.jobs.get(id) is Some(job) && !job.completion_published else {
      return
    }
    if job.on_terminal is Some(cleanup) {
      job.on_terminal = None
      cleanup() catch {
        error => job.cleanup_error = Some("\{error}")
      }
    }
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
    job.completion_published = true
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
