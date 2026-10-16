///|
pub(all) enum Status {
  Ready
  Draining
  RecoveryRequired
  Stopped
} derive(Eq, Debug)

///|
pub(all) enum RequestKind {
  Query
  Connection
  Control
  Mutation
} derive(Eq, Debug)

///|
/// Conservative classification: a new endpoint is a persistent mutation until
/// it is explicitly reviewed. Recovery exposes only the server controller's
/// diagnostics; normal host queries can themselves trigger migration/recovery.
pub fn request_kind(method_ : String) -> RequestKind {
  match method_ {
    "agent.cancel"
    | "agent.approval"
    | "codex.account.login.cancel"
    | "codex.turn.interrupt"
    | "codex.server_request.respond"
    | "jobs.stop" => Control
    "fs.watch"
    | "fs.unwatch"
    | "fs.cancel_search_files"
    | "fs.cancel_search_text"
    | "fs.cancel_search_semantic" => Connection
    "fs.resolve_reference"
    | "fs.read_file"
    | "fs.preview_content"
    | "fs.read_directory"
    | "fs.stat_files"
    | "fs.search_files"
    | "fs.search_text"
    | "fs.search_semantic"
    | "fs.browse"
    | "agent.runs"
    | "session.list"
    | "session.export_content"
    | "session.load"
    | "session.list_archived"
    | "session.load_archived"
    | "workspace.list"
    | "settings.get"
    | "workspace.settings_get"
    | "schedules.list"
    | "codex.status"
    | "codex.thread.read"
    | "codex.thread.history.read"
    | "codex.thread.list"
    | "codex.account.read"
    | "codex.model.list"
    | "codex.server_request.list"
    | "codex.skills.list"
    | "codex.file.search"
    | "git.branch"
    | "git.pull_request"
    | "git.changes"
    | "git.history"
    | "git.commit_changes"
    | "git.original_file"
    | "github.pull_request"
    | "github.review_file"
    | "jobs.list"
    | "jobs.read" => Query
    _ => Mutation
  }
}

///|
pub suberror AdmissionError {
  AdmissionError(String)
}

///|
priv struct Operation {
  invoke : async () -> Json
  reply : @async.Queue[Result[Json, Error]]
  bytes : Int32
  method_ : String
  subject : String?
}

///|
/// Admission and drain mutate the same state without suspension. Accepted
/// mutations run in the service group even if the requesting socket disappears.
pub struct Admission {
  priv mut state : Status
  priv mut active : Int32
  priv mut bytes : Int32
  priv operations : @async.Queue[Operation]
}

///|
pub fn Admission::Admission() -> Admission {
  { state: Ready, active: 0, bytes: 0, operations: Queue(kind=Blocking(128)), }
}

///|
pub fn Admission::status(self : Admission) -> Status {
  self.state
}

///|
pub fn Admission::pending(self : Admission) -> Int32 {
  self.active
}

///|
pub fn Admission::drain(self : Admission) -> Unit {
  if self.state == Ready {
    self.state = Draining
  }
}

///|
pub fn Admission::require_recovery(self : Admission) -> Unit {
  self.state = RecoveryRequired
}

///|
pub fn Admission::check(self : Admission, kind : RequestKind) -> Unit raise {
  match self.state {
    Ready => ()
    Draining if kind is (Query | Control) => ()
    _ => raise AdmissionError("host is \{self.state.name()}")
  }
}

///|
pub async fn Admission::invoke(
  self : Admission,
  method_ : String,
  params : Json,
  invoke : async () -> Json,
) -> Json {
  let kind = request_kind(method_)
  self.check(kind)
  if kind is Query {
    return invoke()
  }
  if kind is Connection {
    guard self.active < 128 else {
      raise AdmissionError("host operation capacity exceeded")
    }
    self.active += 1
    defer {
      self.active -= 1
    }
    return invoke()
  }
  let bytes = @utf8.encode(params.stringify()).length()
  guard self.active < 128 && bytes <= 64 * 1024 * 1024 - self.bytes else {
    raise AdmissionError("host operation capacity exceeded")
  }
  let reply : @async.Queue[Result[Json, Error]] = Queue(kind=Blocking(1))
  let subject = match params {
    { "run_id": String(id), .. } | { "session": String(id), .. } => Some(id)
    _ => None
  }
  guard self.operations.try_put({ invoke, reply, bytes, method_, subject, }) else {
    raise AdmissionError("host operation queue is full")
  }
  self.active += 1
  self.bytes += bytes
  match reply.get() {
    Ok(value) => value
    Err(error) => raise error
  }
}

///|
pub async fn Admission::run(self : Admission) -> Unit {
  defer {
    self.state = Stopped
    self.operations.close(error=AdmissionError("host stopped"))
    while (self.operations.try_get() catch { _ => None }) is Some(operation) {
      operation.reply.close(
        error=AdmissionError("host stopped before operation"),
      )
      self.active -= 1
      self.bytes -= operation.bytes
    }
  }
  @async.with_task_group(group => {
    for ;; {
      let operation = self.operations.get()
      group.spawn_bg(() => {
        defer {
          self.active -= 1
          self.bytes -= operation.bytes
          operation.reply.close(
            error=AdmissionError("host stopped during operation"),
          )
        }
        let result = try {
          let record = @journal.before(
            operation.method_,
            subject?=operation.subject,
          )
          let value = (operation.invoke)()
          @journal.returned(record, value)
          Ok(value)
        } catch {
          error => Err(error)
        }
        ignore(operation.reply.try_put(result))
      })
    }
  })
}

///|
pub fn Status::name(self : Status) -> String {
  match self {
    Ready => "ready"
    Draining => "draining"
    RecoveryRequired => "recovery_required"
    Stopped => "stopped"
  }
}

///|
pub extend Status with Eq::{equal, not_equal}

///|
pub extend Status with Debug::{to_repr}

///|
pub extend RequestKind with Eq::{equal, not_equal}

///|
pub extend RequestKind with Debug::{to_repr}
