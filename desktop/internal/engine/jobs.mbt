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
  let live_ids : Map[String, Bool] = Map([])
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
            live_ids[key] = true
          }
        _ => errors.push("Unexpected job snapshot reply")
      }
    }
  }
  let generations = @fs.readdir(directory) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => []
    error => {
      errors.push("Cannot list job history: \{error}")
      []
    }
  }
  for generation in generations {
    if !@wire.valid_job_component(generation) {
      continue
    }
    let names = @fs.readdir("\{directory}/\{generation}") catch {
      error => {
        errors.push("Cannot read generation \{generation}: \{error}")
        continue
      }
    }
    for name in names {
      if !name.has_suffix(".json") {
        continue
      }
      let id = name[:name.length() - 5].to_owned()
      let key = "\{generation}/\{id}"
      if records.contains(key) {
        continue
      }
      try read_job_record(directory, generation, id) catch {
        error => errors.push("Cannot read job \{key}: \{error}")
      } noraise {
        record => records[key] = record
      }
    }
  }
  let sorted = records.values().to_array()
  sorted.sort_by((a, b) => {
    let order = b.backgrounded_at_ms.compare(a.backgrounded_at_ms)
    if order != 0 {
      order
    } else {
      "\{a.generation}/\{a.id}".compare("\{b.generation}/\{b.id}")
    }
  })
  let start = payload.offset.min(sorted.length())
  let end = (start + 100).min(sorted.length())
  let jobs : Array[@protocol.JobView] = []
  for index in start..<end {
    let record = sorted[index]
    jobs.push(
      job_view(
        directory,
        record,
        live_ids.contains("\{record.generation}/\{record.id}"),
      ),
    )
  }
  {
    jobs,
    errors,
    next_offset: if end < sorted.length() {
      Some(end)
    } else {
      None
    },
  }
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
  let mut end = bytes.length()
  if end > start {
    let mut lead = end - 1
    while lead > start && (bytes[lead].to_int() & 0xc0) == 0x80 {
      lead -= 1
    }
    let byte = bytes[lead].to_int()
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
  )
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
