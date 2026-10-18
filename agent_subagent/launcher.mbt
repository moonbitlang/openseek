///|
/// How long a child has to take its request off its stdin before it is
/// stopped as undelivered. A request is one line; a child that reads nothing
/// for this long is not going to.
const DeliveryTimeoutMs : Int32 = 10_000

///|
/// How long a stopped child has, once its stdin is closed, to flush its
/// result and exit before it is killed.
const StopGraceMs : Int32 = 10_000

///|
/// How many subagents one session may have live at once.
const MaxLive : Int32 = 4

///|
/// The engine's launcher of subagents: each child is a background job of the
/// session's job runtime, so it shares the job lifecycle (ids, records, stop,
/// the loop-owned wait, the exit notice) and adds a typed
/// `@protocol.SubagentInfo` to the job's record.
///
/// A child is `<program> <args...> --kind <kind> --result-file <file>
/// --session <parent>-sr-N --session-root <root> --claim <token>`: the
/// session is claimed for it first (`@agent_subrun.ChildSession::claim`), its
/// one request line is written to its stdin, and the pipe is held open until
/// the child is stopped, when closing it is the child's cue to wind down.
/// What it achieved is read from its result file once it has ended.
///
/// A child is not reaped at the job runtime's wall-clock cap: it is bounded
/// by its own step budget and context ceiling.
struct Launcher {
  runtime : @bgjobs.BgJobRuntime
  children : @agent_subrun.ChildSession
  store : @store.SessionStore
  program : String
  args : Array[String]
  cwd : String?
  result_dir : String
  spawn : (async () -> Unit) -> Unit
  max_live : Int32
  grace_ms : Int32
  delivery_timeout_ms : Int32
  mut live : Int32
  // Captured reports by child session, kept for as long as this engine
  // runs, so a report whose store failed can still be read.
  reports : Map[String, Json]
}

///|
/// A launcher for the session whose job runtime is `runtime` and whose
/// children's sessions `children` claims. `program` and `args` start a
/// child up to its kind (the engine's own binary, a managed `run`, its model
/// and endpoint); `cwd` is where it runs. Result files are written in
/// `result_dir`, which is created when needed.
pub fn[X] Launcher::Launcher(
  scope : @agent_runtime.AgentTaskScope[X],
  runtime~ : @bgjobs.BgJobRuntime,
  children~ : @agent_subrun.ChildSession,
  program~ : String,
  args~ : Array[String],
  cwd? : String,
  result_dir~ : String,
  max_live~ : Int32 = MaxLive,
  grace_ms~ : Int32 = StopGraceMs,
  delivery_timeout_ms~ : Int32 = DeliveryTimeoutMs,
) -> Launcher {
  let group = scope.group()
  {
    runtime,
    children,
    store: SessionStore(children.root()),
    program,
    args: args.copy(),
    cwd,
    result_dir,
    spawn: task => group.spawn_bg(task, no_wait=true, allow_failure=true),
    max_live,
    grace_ms,
    delivery_timeout_ms,
    live: 0,
    reports: Map([]),
  }
}

///|
/// What `Launcher::start` did.
pub(all) enum StartResult {
  /// The child is running as job `job_id`, recording to `session`.
  Started(job_id~ : String, session~ : String)
  /// As many subagents as the session may have are live; nothing was
  /// started and nothing was spent. Retry after one ends.
  Busy
  /// The child could not be started, with the reason.
  Unavailable(String)
}

///|
/// One child's settling facts, filled in when it ends.
priv struct Child {
  kind : String
  label : String
  session : String
  launch : @protocol.SubagentLaunch
  mut outcome : @protocol.SubagentOutcome?
  mut usage : @protocol.SubagentUsage?
  mut report : @protocol.SubagentReport?
  mut delivery_failed : Bool
}

///|
fn Child::info(self : Child) -> @protocol.SubagentInfo {
  {
    kind: self.kind,
    label: self.label,
    session: self.session,
    launch: self.launch,
    outcome: self.outcome,
    usage: self.usage,
    report: self.report,
    workspace: InPlace,
  }
}

///|
/// The number of subagents live now.
pub fn Launcher::live(self : Launcher) -> Int32 {
  self.live
}

///|
/// The report a child of this engine captured, by its session; `None` when
/// it captured none.
pub fn Launcher::report(self : Launcher, session : String) -> Json? {
  self.reports.get(session)
}

///|
/// Start one subagent of `kind` on `input` and return at once.
///
/// Admission takes a slot with no suspension, so of five simultaneous
/// starts in a session with four slots one is `Busy`. A start that fails
/// after that gives its slot back; an ordinal it claimed stays consumed.
/// `validate` is the kind's report check: a child is `Captured` only with a
/// result for this request whose output it accepts, and what it returns is
/// the report kept.
pub async fn Launcher::start(
  self : Launcher,
  kind~ : String,
  input~ : Json,
  label~ : String,
  max_steps? : Int32,
  launch~ : @protocol.SubagentLaunch,
  validate~ : (Json) -> Result[Json, String],
) -> StartResult {
  guard self.live < self.max_live else { return Busy }
  self.live += 1
  let held = Ref(true)
  let release = () => {
    if held.val {
      held.val = false
      self.live -= 1
    }
  }
  let claimed = self.children.claim() catch {
    error => {
      release()
      return Unavailable("could not claim a child session: \{error}")
    }
  }
  let session = claimed.session
  let result_file = "\{self.result_dir}/\{session}.result.json"
  let child : Child = {
    kind,
    label,
    session,
    launch,
    outcome: None,
    usage: None,
    report: None,
    delivery_failed: false,
  }
  let (child_stdin, writer) = try {
    @fs.mkdir(self.result_dir, recursive=true, allow_exist=true)
    @process.write_to_process()
  } catch {
    error => {
      release()
      return Unavailable("could not prepare child \{session}: \{error}")
    }
  }
  let handler = @process.CancellationHandler(pid => {
    writer.close()
    @async.sleep(self.grace_ms)
    (@process.hard_cancel().0)(pid)
  })
  let args = [
    ..self.args,
    "--kind",
    kind,
    "--result-file",
    result_file,
    "--session",
    session,
    "--session-root",
    self.children.root(),
    "--claim",
    claimed.token,
  ]
  let job_id = self.runtime.start(
    program=self.program,
    args~,
    // The token is the child's alone: the job's recorded command omits it.
    command="openseek run --kind \{kind} --session \{session}",
    description=label,
    cwd?=self.cwd,
    stdin=child_stdin,
    cancel_handler=handler,
    on_end=end => {
      defer release()
      defer writer.close()
      self.settle(child, end, result_file~, validate~)
    },
    subagent=() => child.info(),
    reaped=false,
  ) catch {
    error => {
      writer.close()
      release()
      return Unavailable("could not start child \{session}: \{error}")
    }
  }
  let request : @protocol.RunRequest = {
    request_id: Some(session),
    kind: Some(kind),
    input,
    max_steps,
  }
  let line = request.to_json().stringify() + "\n"
  (self.spawn)(() => {
    @async.with_timeout(self.delivery_timeout_ms, () => writer.write(line)) catch {
      _ => {
        child.delivery_failed = true
        ignore(self.runtime.stop(job_id))
      }
    }
  })
  Started(job_id~, session~)
}

///|
/// What a child left in its result file: `None` when it left none.
priv enum Left {
  Result(@protocol.RunResult)
  Unreadable(String)
}

///|
async fn read_result(path : String) -> Left? {
  let text = @fs.read_file(path).text() catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => return None
    error => return Some(Unreadable("\{error}"))
  }
  Some(Result(@protocol.parse_run_result(@json.parse(text)))) catch {
    error => Some(Unreadable("\{error}"))
  }
}

///|
/// Decide how `child` ended and what it spent, store its report, and drop
/// its result file. Runs in the job's finish sequence, before its terminal
/// record, so the record and the exit notice carry the outcome.
async fn Launcher::settle(
  self : Launcher,
  child : Child,
  end : @bgjobs.JobEnd,
  result_file~ : String,
  validate~ : (Json) -> Result[Json, String],
) -> Unit {
  let left = read_result(result_file)
  // A report for this request that its kind accepts wins over every way
  // the child could have been ended: one written during a stop's grace
  // still counts.
  let accepted = match left {
    Some(Result({ status: Completed(output~), request_id: Some(id), .. })) if id ==
      child.session =>
      match validate(output) {
        Ok(report) => Ok(report)
        Err(problem) => Err("report rejected: \{problem}")
      }
    _ => Err("")
  }
  child.outcome = Some(
    match (accepted, end) {
      (Ok(_), _) => Captured
      _ if child.delivery_failed => Failed("request not delivered")
      (_, CaptureFailed(reason)) => Failed("output not captured: \{reason}")
      (_, OutputLimit) => Failed("output limit exceeded")
      (_, TimeLimit) => TimedOut
      (_, Stopped) => Stopped
      (Err(rejected), Exited(code)) =>
        match left {
          Some(Result({ status: Completed(..), .. })) if rejected != "" =>
            Failed(rejected)
          Some(Result({ status, .. })) => outcome_of(status, code~)
          Some(Unreadable(reason)) => Failed("unreadable result: \{reason}")
          None => Failed("exited with code \{code} without a result")
        }
    },
  )
  child.usage = Some(
    match left {
      Some(Result({ usage: Some(usage), steps, .. })) =>
        Known(
          steps=steps.unwrap_or(0),
          prompt_tokens=usage.prompt_tokens,
          completion_tokens=usage.completion_tokens,
          cost_usd=None,
          source=Result,
          unaccounted=None,
        )
      Some(Result(_)) => Unavailable("the child never reached its turn")
      Some(Unreadable(_)) | None => Unavailable("the child left no result")
    },
  )
  if accepted is Ok(report) {
    self.reports[child.session] = report
    child.report = Some(self.store_report(child.session, report))
  }
  @async.protect_from_cancel(() => @fs.remove(result_file)) catch {
    _ => ()
  }
}

///|
/// How a child that exited on its own with a result but no accepted report
/// ended.
fn outcome_of(
  status : @protocol.RunStatus,
  code~ : Int32,
) -> @protocol.SubagentOutcome {
  match status {
    NoReport => NoReport
    MaxStepsExhausted => MaxSteps
    ContextYield(..) => ContextYield
    Aborted(reason~) | Interrupted(reason~) | Failed(reason~) => Failed(reason)
    // A completed run whose request id is not this child's.
    Completed(..) =>
      Failed("exited with code \{code} with a result for another request")
  }
}

///|
/// Keep `report` beside the child's transcript: written to a sibling, then
/// renamed into place, so a reader never sees half of one.
async fn Launcher::store_report(
  self : Launcher,
  session : String,
  report : Json,
) -> @protocol.SubagentReport {
  try {
    let path = self.store.report_file(SessionId(session))
    let temporary = "\{path}.tmp"
    @fs.write_file(
      temporary,
      report.stringify(),
      create_mode=CreateOrTruncate,
      sync=Data,
    )
    @fs.rename(temporary, path, replace=true)
    Stored
  } catch {
    error => StoreFailed("\{error}")
  }
}
