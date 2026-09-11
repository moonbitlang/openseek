///|
/// Locate the exact store selected by the conversation, including archives.
async fn jobs_directory(scope : @protocol.JobsScope) -> String {
  guard @session_store.safe_session_id(scope.session) else {
    raise EngineError("invalid session id")
  }
  let root = match scope.workspace {
    Some(hint) => {
      let store = @session_store.ArchivedStore::for_workspace(hint)
      store.root
    }
    None => {
      let root = if scope.archived {
        @session_store.archived_root_of(scope.session)
      } else {
        @session_store.root_of(scope.session)
      }
      guard root is Some(root) else {
        raise EngineError("no attached workspace holds this conversation")
      }
      root
    }
  }
  let root = if scope.archived {
    @session_store.archived_root(root)
  } else {
    root
  }
  let session = root.join("sessions").join(Relative(scope.session)).to_string()
  guard @fs.kind(session) is Directory else {
    raise EngineError("session directory is unavailable")
  }
  jobs_store_path(root, scope.session)
}

///|
fn EngineManager::jobs_engine(
  self : EngineManager,
  scope : @protocol.JobsScope,
) -> ServeEngine? {
  guard !scope.archived &&
    self.pump is Serving(sessions~) &&
    sessions.get(scope.session) is Some(slot) else {
    return None
  }
  slot.live()
}

///|
/// Correlated replies belong to this exact engine handle. Retirement closes
/// pending requests; neither a new turn nor a replacement process can answer.
async fn ServeEngine::job_request(
  self : ServeEngine,
  request_id : String,
  command : @wire.Command,
) -> @wire.Event {
  let reply : @async.Queue[@wire.Event] = Queue(kind=Blocking(1))
  self.job_requests[request_id] = reply
  defer self.job_requests.remove(request_id)
  let ack : @async.Queue[EngineError?] = Queue(kind=Blocking(1))
  guard self.submit(
    command,
    failure_reason="background job command could not be delivered",
    ack~,
  ) else {
    raise EngineError("background job engine is unavailable")
  }
  @async.with_timeout(5000, () => {
    if ack.get() is Some(error) {
      raise error
    }
    reply.get()
  })
}

///|
async fn read_job_record(
  directory : String,
  generation : String,
  id : String,
) -> @wire.JobRecord {
  guard @wire.valid_job_component(generation) && @wire.valid_job_component(id) else {
    raise EngineError("invalid job identity")
  }
  let file = @fs.open("\{directory}/\{generation}/\{id}.json", mode=ReadOnly)
  defer file.close()
  guard file.kind() is Regular else {
    raise EngineError("job metadata is not a regular file")
  }
  let size = file.size()
  guard size <= 1048576L else {
    raise EngineError("job metadata exceeds 1 MiB")
  }
  let bytes = file.read_exactly_at(size.to_int(), position=0L)
  let record : @wire.JobRecord = @json.from_json(
    @json.parse(@utf8.decode(bytes)),
  )
  guard record.generation == generation && record.id == id else {
    raise EngineError("job metadata identity does not match its directory")
  }
  record
}

///|
async fn job_view(
  directory : String,
  record : @wire.JobRecord,
  live : Bool,
) -> @protocol.JobView {
  let mut record = record
  let mut error : String? = None
  if !live && !record.state.is_terminal() {
    try {
      let owner = @fs.open(
        "\{directory}/\{record.generation}/owner.lock",
        mode=ReadWrite,
      )
      defer owner.close()
      if owner.try_lock(Exclusive) {
        record = { ..record, state: Interrupted, }
      } else {
        error = Some(
          "The owner is running outside this Desktop connection; controls are unavailable.",
        )
      }
    } catch {
      failure => error = Some("Cannot verify the job owner: \{failure}")
    }
  }
  let output_path = record.output_file.map(name => {
    "\{directory}/\{record.generation}/\{name}"
  })
  {
    job: record,
    output_path,
    controllable: live && !record.state.is_terminal(),
    error,
  }
}

///|
/// Page durable history and overlay an authoritative live-engine snapshot.
pub async fn list_jobs(
  manager : EngineManager,
  payload : @protocol.JobsListPayload,
) -> @protocol.JobsListReply {
  let scope = payload.scope
  let guard_record = manager.begin_record_read(scope.session)
  defer manager.end_record_read(scope.session, guard_record)
  let directory = jobs_directory(scope)
  let errors : Array[String] = []
  let records : Map[String, @wire.JobRecord] = Map([])
  if manager.jobs_engine(scope) is Some(engine) {
    // Verify workspace placement as well as the session id before requesting
    // live data; duplicate session ids in different stores must stay isolated.
    if engine.session_root is Some(root) &&
      directory == jobs_store_path(root, scope.session) {
      guard @uuid.mint() is Some(request_id) else {
        raise EngineError("could not allocate a job request id")
      }
      try engine.job_request(request_id, JobsSnapshot(request_id~)) catch {
        error => errors.push("Live job refresh failed: \{error}")
      } noraise {
        JobsSnapshot(jobs~, ..) =>
          for job in jobs {
            let key = "\{job.generation}/\{job.id}"
            records[key] = job
          }
        _ => errors.push("Unexpected job snapshot reply")
      }
    }
  }
  let page = job_history_page(directory, records, payload.offset, errors)
  let selected = match payload.selected {
    None => None
    Some(target) => {
      guard target.scope == scope else {
        raise EngineError("selected job scope mismatch")
      }
      try
        selected_job_view(directory, records, target.generation, target.job_id)
      catch {
        error => {
          errors.push("Cannot refresh selected job: \{error}")
          None
        }
      } noraise {
        view => Some(view)
      }
    }
  }
  { ..page, selected, }
}

///|
/// Enumerate lightweight names, then decode only the requested page. Runtime
/// creation stamps and monotonic bg-N ids keep completed records in stable
/// order; output writes and terminal metadata updates cannot reshuffle pages.
async fn job_history_page(
  directory : String,
  live : Map[String, @wire.JobRecord],
  offset : Int,
  errors : Array[String],
) -> @protocol.JobsListReply {
  guard offset >= 0 else { raise EngineError("invalid history offset") }
  let names = @fs.readdir(directory) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => []
    error => {
      errors.push("Cannot list job history: \{error}")
      []
    }
  }
  for _, record in live {
    if !names.contains(record.generation) {
      names.push(record.generation)
    }
  }
  let generations : Array[(String, (Int64, Int)?)] = []
  for name in names {
    if !@wire.valid_job_component(name) {
      continue
    }
    let kind = Some(@fs.kind("\{directory}/\{name}")) catch {
      error => {
        errors.push("Cannot inspect runtime \{name}: \{error}")
        None
      }
    }
    // Reject only entries known to be invalid. An inspection error must not
    // discard readable metadata or the authoritative live-engine overlay.
    let stamp = match kind {
      Some(Directory) =>
        Some(@fs.mtime("\{directory}/\{name}/owner.lock")) catch {
          @os_error.OSError(_) as error if error.is_ENOENT() => None
          error => {
            errors.push("Cannot inspect runtime \{name}: \{error}")
            None
          }
        }
      Some(_) => {
        errors.push("Cannot inspect runtime \{name}: not a directory")
        guard live.iter().any(entry => entry.1.generation == name) else {
          continue
        }
        None
      }
      None => None
    }
    generations.push((name, stamp))
  }
  generations.sort_by((a, b) => {
    match (a.1, b.1) {
      (Some(x), Some(y)) => {
        let seconds = y.0.compare(x.0)
        if seconds != 0 {
          seconds
        } else {
          let nanos = y.1.compare(x.1)
          if nanos != 0 {
            nanos
          } else {
            b.0.compare(a.0)
          }
        }
      }
      (Some(_), None) => -1
      (None, Some(_)) => 1
      (None, None) => b.0.compare(a.0)
    }
  })
  let candidates : Array[(String, String)] = []
  let mut skipped = 0
  scan~: for (generation, _) in generations {
    let files = @fs.readdir("\{directory}/\{generation}") catch {
      error => {
        errors.push("Cannot read generation \{generation}: \{error}")
        []
      }
    }
    let ids = files.filter_map(name => {
      if name.has_suffix(".json") {
        Some(name[:name.length() - 5].to_owned())
      } else {
        None
      }
    })
    for _, record in live {
      if record.generation == generation && !ids.contains(record.id) {
        ids.push(record.id)
      }
    }
    ids.sort_by((a, b) => {
      let length = b.length().compare(a.length())
      if length != 0 {
        length
      } else {
        b.compare(a)
      }
    })
    for id in ids {
      if skipped < offset {
        skipped += 1
        continue
      }
      candidates.push((generation, id))
      if candidates.length() > 100 {
        break scan~
      }
    }
  }
  let jobs : Array[@protocol.JobView] = []
  for index in 0..<candidates.length().min(100) {
    let (generation, id) = candidates[index]
    let key = "\{generation}/\{id}"
    let record = match live.get(key) {
      Some(record) => record
      None =>
        read_job_record(directory, generation, id) catch {
          error => {
            errors.push("Cannot read job \{key}: \{error}")
            continue
          }
        }
    }
    jobs.push(job_view(directory, record, live.contains(key)))
  }
  {
    jobs,
    errors,
    selected: None,
    next_offset: if candidates.length() > 100 {
      Some(offset + 100)
    } else {
      None
    },
  }
}

///|
async fn selected_job_view(
  directory : String,
  live : Map[String, @wire.JobRecord],
  generation : String,
  id : String,
) -> @protocol.JobView {
  let key = "\{generation}/\{id}"
  let record = match live.get(key) {
    Some(record) => record
    None => read_job_record(directory, generation, id)
  }
  job_view(directory, record, live.contains(key))
}

///|
/// Trim a byte page to complete UTF-8 code points. Initial tail reads may
/// begin inside a character; subsequent reads must begin on a boundary.
fn job_utf8_window(bytes : Bytes, tail : Bool) -> (Int, Int) raise {
  let mut start = 0
  if tail {
    while start < bytes.length() && (bytes[start].to_int() & 0xc0) == 0x80 {
      start += 1
    }
  }
  guard start == bytes.length() || (bytes[start].to_int() & 0xc0) != 0x80 else {
    raise EngineError("log cursor is not on a UTF-8 boundary")
  }
  let mut end = bytes.length()
  if end > start {
    let mut lead = end - 1
    while lead > start && (bytes[lead].to_int() & 0xc0) == 0x80 {
      lead -= 1
    }
    let byte = bytes[lead].to_int()
    guard byte < 0x80 || (byte >= 0xc2 && byte <= 0xf4) else {
      raise EngineError("invalid UTF-8 in job output")
    }
    let width = if byte < 0x80 {
      1
    } else if byte < 0xe0 {
      2
    } else if byte < 0xf0 {
      3
    } else {
      4
    }
    if lead + width > end {
      end = lead
    }
  }
  ignore(@utf8.decode(bytes[start:end]))
  (start, end)
}

///|
/// Read at most 64 KiB without waiting for a newline or loading the whole log.
pub async fn read_job(
  manager : EngineManager,
  payload : @protocol.JobReadPayload,
) -> @protocol.JobReadReply {
  let scope = payload.target.scope
  let record_guard = manager.begin_record_read(scope.session)
  defer manager.end_record_read(scope.session, record_guard)
  let directory = jobs_directory(scope)
  let job = read_job_record(
    directory,
    payload.target.generation,
    payload.target.job_id,
  ) catch {
    metadata_error => {
      // A failed first metadata write must not make a retained live log
      // unreadable. Only the exact owning engine may supply this fallback.
      guard manager.jobs_engine(scope) is Some(engine) &&
        engine.session_root is Some(root) &&
        directory == jobs_store_path(root, scope.session) else {
        raise metadata_error
      }
      guard @uuid.mint() is Some(request_id) else {
        raise EngineError("could not allocate a job request id")
      }
      match engine.job_request(request_id, JobsSnapshot(request_id~)) {
        JobsSnapshot(jobs~, ..) => {
          guard jobs
            .iter()
            .find_first(job => {
              job.generation == payload.target.generation &&
              job.id == payload.target.job_id
            })
            is Some(job) else {
            raise metadata_error
          }
          job
        }
        _ => raise EngineError("unexpected job snapshot reply")
      }
    }
  }
  guard job.output_file is Some(name) else {
    raise EngineError("this job has no output file")
  }
  let path = "\{directory}/\{job.generation}/\{name}"
  read_job_page(path, payload.offset, payload.limit)
}

///|
async fn read_job_page(
  path : String,
  offset : Int64?,
  limit : Int,
) -> @protocol.JobReadReply {
  guard limit >= 4 &&
    limit <= 65536 &&
    (offset is None || (offset is Some(n) && n >= 0L)) else {
    raise EngineError("invalid log cursor or page limit")
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  guard file.kind() is Regular else {
    raise EngineError("job output is not a regular file")
  }
  let size = file.size()
  let start = match offset {
    Some(offset) => offset
    None => (size - limit.to_int64()).max(0L)
  }
  guard start <= size else {
    raise EngineError("job output was truncated; reload its tail")
  }
  let length = (size - start).min(limit.to_int64()).to_int()
  let bytes = file.read_exactly_at(length, position=start)
  let (skip, end) = job_utf8_window(bytes, offset is None && start > 0L)
  let next = start + end.to_int64()
  {
    text: @utf8.decode(bytes[skip:end]),
    start_offset: start + skip.to_int64(),
    next_offset: next,
    size,
    more: next < size,
    output_path: path,
  }
}

///|
/// Await the engine's settlement; a delivered request alone is not success.
pub async fn stop_job(
  manager : EngineManager,
  target : @protocol.JobTarget,
) -> @protocol.JobStopReply {
  let record_guard = manager.begin_record_read(target.scope.session)
  defer manager.end_record_read(target.scope.session, record_guard)
  let directory = jobs_directory(target.scope)
  guard manager.jobs_engine(target.scope) is Some(engine) &&
    engine.session_root is Some(root) &&
    directory == jobs_store_path(root, target.scope.session) else {
    raise EngineError("job controls require its current live engine")
  }
  guard @uuid.mint() is Some(request_id) else {
    raise EngineError("could not allocate a job request id")
  }
  match
    engine.job_request(
      request_id,
      JobStop(request_id~, generation=target.generation, job_id=target.job_id),
    ) {
    JobStopResult(generation~, job_id~, outcome~, ..) if generation ==
      target.generation &&
      job_id == target.job_id => { outcome, }
    _ => raise EngineError("unexpected job stop reply")
  }
}

///|
/// Normalize both sides of ownership comparisons. Native joins use backslashes
/// on Windows while stored engine roots use slash-normalized Absolute paths.
fn jobs_store_path(root : @pathx.Absolute, session : String) -> String {
  root
  .join("sessions")
  .join(Relative(session))
  .join("jobs")
  .normalize()
  .to_string()
}
