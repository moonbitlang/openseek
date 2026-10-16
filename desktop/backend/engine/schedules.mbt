// Lightweight, host-owned schedules. Every execution is an independent CLI
// session. The UI polls snapshots; no renderer owns a timer or child process.
//
// Host processes of one user share a runtime directory, and so this store: a
// release build beside a development build, two windows of one build. Each
// keeps the state in memory, times the entries itself, and saves the whole
// state back, so two of them would start every due entry twice and erase each
// other's saves. The store therefore has one owner at a time — the first host
// to reach it, for as long as that process lives. Only the owner runs
// entries and writes the file. Every other host reads what the owner last
// saved and refuses changes, and takes over when the owner is gone.

///|
const ScheduleConcurrency = 4

///|
pub struct Schedules {
  manager : EngineManager
  directory : @pathx.Path?
  lock : @async.Mutex
  // This process's hold on the store: an exclusive lock on a file inside it,
  // kept open for the life of the process, so the operating system gives it
  // up however the process ends. `None` while another host owns the store,
  // or before this one has reached it.
  mut ownership : @fs.File?
  // The owner's view of the store. A host that does not own it caches
  // nothing: what it would remember is another process's to change.
  mut state : @protocol.SchedulesReply?
  processes : Map[String, @process.Process]
  stopped : Map[String, Unit]
  priv mut accepting : Bool
  priv mut claiming : Int32
}

///|
pub fn Schedules::Schedules(
  manager : EngineManager,
  runtime_dir : @pathx.Path?,
) -> Schedules {
  {
    manager,
    directory: runtime_dir.map(dir => dir.join("schedules")),
    lock: Mutex(),
    ownership: None,
    state: None,
    processes: Map([]),
    stopped: Map([]),
    accepting: true,
    claiming: 0,
  }
}

///|
fn schedule_now() -> Int64 {
  @sys.now().reinterpret_as_int64()
}

///|
fn schedule_next(timing : @protocol.ScheduleTiming, now : Int64) -> Int64? {
  match timing {
    Once(at) => if at > now { Some(at) } else { None }
    Every(minutes) => Some(now + minutes.to_int64() * 60000)
  }
}

///|
fn recover_schedules(
  state : @protocol.SchedulesReply,
  now : Int64,
) -> @protocol.SchedulesReply {
  {
    entries: state.entries.map(entry => {
      if entry.enabled {
        let next_at = match entry.next_at {
          Some(at) if at > now => Some(at)
          _ => schedule_next(entry.spec.timing, now)
        }
        { ..entry, next_at, run_requested: false, enabled: next_at is Some(_), }
      } else {
        { ..entry, run_requested: false, }
      }
    }),
    runs: state.runs.map(run => {
      if run.status is Running {
        { ..run, status: Interrupted, finished_at: Some(now), }
      } else {
        run
      }
    }),
  }
}

///|
fn Schedules::directory(self : Schedules) -> @pathx.Path raise EngineError {
  match self.directory {
    Some(dir) => dir
    None =>
      raise EngineError("Local schedules need an available host data directory")
  }
}

///|
/// What a client is told when it tries to change schedules through a host
/// that does not own the store.
const ScheduleForeignOwner = "Schedules are run by another SeekMoon open on this computer; change them there"

///|
// Caller holds the lock. Whether this process owns the store, claiming it
// when no running host does. A host that finds it taken asks again on its
// next call, which is how it takes over once the owner has exited.
async fn Schedules::owns(self : Schedules) -> Bool {
  if self.ownership is Some(_) {
    return true
  }
  let dir = self.directory()
  @fsx.ensure_dir(dir)
  let file = @fs.open(
    dir.join("owner.lock").to_string(),
    mode=ReadWrite,
    create_mode=OpenOrCreate,
  )
  errdefer file.close()
  guard file.try_lock(Exclusive) else {
    file.close()
    return false
  }
  self.ownership = Some(file)
  true
}

///|
// What the store's file says. Never treat corrupt/unreadable state as an
// empty list. The owner replaces the file by rename, so a host reading it
// without owning the store sees one complete save or the other.
async fn Schedules::read(self : Schedules) -> @protocol.SchedulesReply {
  let dir = self.directory()
  @fsx.ensure_dir(dir)
  match @fsx.read_text_if_exists(dir.join("schedules.json")) {
    None => { entries: [], runs: [], }
    Some(text) => {
      let json = @json.parse(text)
      guard json is { "version": 1, "state": value, .. } else {
        raise EngineError("Unsupported schedule store version")
      }
      @json.from_json(value)
    }
  }
}

///|
// Caller holds the lock and owns the store. The first load after taking
// ownership settles what the previous owner left behind: runs it was still
// executing are over, and deadlines that passed while nobody owned the store
// are skipped rather than replayed.
async fn Schedules::load(self : Schedules) -> @protocol.SchedulesReply {
  if self.state is Some(state) {
    return state
  }
  let recovered = recover_schedules(self.read(), schedule_now())
  self.commit(recovered)
  recovered
}

///|
async fn Schedules::commit(
  self : Schedules,
  state : @protocol.SchedulesReply,
) -> Unit {
  let dir = self.directory()
  let temp = dir.join("schedules.tmp")
  let json : Json = { "version": 1, "state": state.to_json() }
  @fs.write_file(
    temp.to_string(),
    json.stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
  )
  {
    let file = @fs.open(temp.to_string(), mode=ReadWrite)
    defer file.close()
    file.sync()
  }
  @fs.rename(temp.to_string(), dir.join("schedules.json").to_string())
  self.state = Some(state)
}

///|
pub async fn Schedules::list(self : Schedules) -> @protocol.SchedulesReply {
  self.lock.acquire()
  defer self.lock.release()
  if self.owns() {
    self.load()
  } else {
    // Another host's schedules, as it last saved them. Reading must not
    // recover or write: that would end the owner's running entries on disk.
    self.read()
  }
}

///|
pub async fn Schedules::save(
  self : Schedules,
  payload : @protocol.ScheduleSavePayload,
) -> @protocol.SchedulesReply {
  @async.protect_from_cancel(() => {
    self.lock.acquire()
    defer self.lock.release()
    guard self.owns() else { raise EngineError(ScheduleForeignOwner) }
    let state = self.load()
    // Validate typed callers too, and resolve only registered project paths.
    let spec : @protocol.ScheduleSpec = @json.from_json(payload.spec.to_json())
    if spec.workspace is Some(workspace) {
      guard @pathx.Absolute::from_uri_path(workspace) is Some(path) &&
        @workspaces.registered_dir(path) is Some(_) else {
        raise EngineError("Choose an attached project for this schedule")
      }
    }
    let next_at = schedule_next(spec.timing, schedule_now())
    guard next_at is Some(_) else {
      raise EngineError("Choose a time in the future")
    }
    let id = match payload.id {
      Some(id) => {
        guard state.entries.any(entry => entry.id == id) else {
          raise EngineError("Schedule no longer exists")
        }
        id
      }
      None => @uuid.mint()
    }
    guard !payload.run_now || !schedule_running(state, id) else {
      raise EngineError("This schedule is already running")
    }
    let entry : @protocol.ScheduleEntry = {
      id,
      spec,
      enabled: true,
      run_requested: payload.run_now,
      notice: None,
      next_at,
    }
    let entries = state.entries.copy()
    match entries.search_by(entry => entry.id == id) {
      Some(index) => entries[index] = entry
      None => entries.push(entry)
    }
    let next = { ..state, entries, }
    self.commit(next)
    next
  })
}

///|
fn schedule_running(state : @protocol.SchedulesReply, id : String) -> Bool {
  state.runs.any(run => run.schedule_id == id && run.status is Running)
}

///|
pub async fn Schedules::action(
  self : Schedules,
  payload : @protocol.ScheduleActionPayload,
) -> @protocol.SchedulesReply {
  @async.protect_from_cancel(() => {
    self.lock.acquire()
    defer self.lock.release()
    guard self.owns() else { raise EngineError(ScheduleForeignOwner) }
    let state = self.load()
    guard state.entries.search_by(entry => entry.id == payload.id)
      is Some(index) else {
      raise EngineError("Schedule no longer exists")
    }
    let entry = state.entries[index]
    let entries = state.entries.copy()
    match payload.action {
      "pause" =>
        entries[index] = {
          ..entry,
          enabled: false,
          run_requested: false,
          next_at: None,
        }
      "resume" => {
        let next_at = schedule_next(entry.spec.timing, schedule_now())
        guard next_at is Some(_) else {
          raise EngineError(
            "This one-time schedule has passed; edit its time or run it now",
          )
        }
        entries[index] = { ..entry, enabled: true, next_at, }
      }
      "run" => {
        guard !schedule_running(state, entry.id) && !entry.run_requested else {
          raise EngineError("This schedule is already running or queued")
        }
        entries[index] = { ..entry, run_requested: true, }
      }
      "stop" =>
        for run in state.runs {
          if run.schedule_id == entry.id && run.status is Running {
            self.stopped[run.id] = ()
            if self.processes.get(run.id) is Some(process) {
              process.cancel()
            }
          }
        }
      "delete" => {
        guard !schedule_running(state, entry.id) else {
          raise EngineError("Stop this run before deleting its schedule")
        }
        ignore(entries.remove(index))
      }
      _ => raise EngineError("Unknown schedule action")
    }
    let next = { ..state, entries, }
    self.commit(next)
    next
  })
}

///|
// Only the host's primary app-lifetime group starts this loop. Sleep and
// application downtime never accumulate executions to replay on the next tick.
pub async fn Schedules::run(
  self : Schedules,
  on_run_changed~ : (@protocol.ScheduleRun) -> Unit,
  sink~ : EventSink,
  on_workspaces~ : (Array[String]) -> Unit,
) -> Unit {
  @async.with_task_group(group => {
    for ;; {
      let launches = self.take_due() catch {
        error => {
          @xlog.warn() <?
            { "event": "schedules_unavailable", "message": "\{error}" }
          @async.sleep(5000)
          continue
        }
      }
      for (entry, run) in launches {
        on_run_changed(run)
        group.spawn_bg(() => {
          self.execute(
            entry,
            run,
            on_finished=on_run_changed,
            sink~,
            on_workspaces~,
          )
        })
      }
      @async.sleep(1000)
    }
  })
}

///|
async fn Schedules::take_due(
  self : Schedules,
  at? : Int64,
) -> Array[(@protocol.ScheduleEntry, @protocol.ScheduleRun)] {
  self.claiming += 1
  defer {
    self.claiming -= 1
  }
  @async.protect_from_cancel(() => {
    self.lock.acquire()
    defer self.lock.release()
    // Only the owner starts entries; every other host's loop idles here
    // until the store is free.
    guard self.owns() else { return [] }
    let state = self.load()
    guard self.accepting else { return [] }
    let now = at.unwrap_or_else(schedule_now)
    let entries = state.entries.copy()
    let runs = state.runs.copy()
    let launches : Array[(@protocol.ScheduleEntry, @protocol.ScheduleRun)] = []
    let mut active = runs.filter(run => run.status is Running).length()
    let mut changed = false
    for index, entry in entries {
      let due = entry.enabled && entry.next_at is Some(at) && at <= now
      guard entry.run_requested || due else { continue }
      let running = schedule_running(state, entry.id)
      // Explicit Run now waits for capacity. Periodic ticks never build a backlog.
      if entry.run_requested && (running || active >= ScheduleConcurrency) {
        continue
      }
      let next_at = if due {
        schedule_next(entry.spec.timing, now)
      } else {
        entry.next_at
      }
      entries[index] = {
        ..entry,
        next_at,
        run_requested: false,
        enabled: entry.enabled && next_at is Some(_),
      }
      changed = true
      let notice = if running {
        Some("Skipped: the previous run is still active")
      } else if active >= ScheduleConcurrency {
        Some("Skipped: all four execution slots were busy")
      } else if !entry.run_requested &&
        entry.next_at is Some(at) &&
        now - at > 60000 {
        Some("Skipped: the host missed the scheduled time")
      } else {
        None
      }
      entries[index] = { ..entries[index], notice, }
      guard notice is None else { continue }
      let id = @uuid.mint()
      let run : @protocol.ScheduleRun = {
        id,
        schedule_id: entry.id,
        name: entry.spec.name,
        workspace: entry.spec.workspace.unwrap_or_else(() => {
          guard @home.dir() is Some(home) else {
            raise EngineError(
              "Automatic tasks need an available home directory",
            )
          }
          home
          .join("OpenSeek")
          .join("Scheduled")
          .join(entry.id)
          .resolve()
          .resource_path()
        }),
        session: "scheduled-\{id}",
        started_at: now,
        finished_at: None,
        status: Running,
        log_path: self.directory().join("\{id}.log").to_string(),
      }
      ignore(@journal.before("schedule.admit", subject=run.id))
      runs.push(run)
      launches.push((entry, run))
      active += 1
    }
    if changed {
      self.commit({ entries, runs, })
    }
    launches
  })
}

///|
pub fn Schedules::stop_admission(self : Schedules) -> Unit {
  self.accepting = false
}

///|
pub fn Schedules::has_active_work(self : Schedules) -> Bool {
  self.claiming > 0 ||
  !self.processes.is_empty() ||
  (self.state is Some(state) && state.runs.any(run => run.status is Running))
}
