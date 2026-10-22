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
const MaxLive : Int32 = 16

///|
/// How many of them may be workers: each builds and tests in a worktree or a
/// directory of its own, which costs the machine, where a read-only child
/// mostly waits on the model. Eight keeps a simplify sweep's workers and
/// their reviewers inside `MaxLive`.
const MaxWorkers : Int32 = 8

///|
/// How many subagents one script may start in all.
const ScriptQuota : Int32 = 64

///|
/// How long a script stays pinned past the wall-clock cap after its last
/// child ended, to collect what it left.
const CollectAllowanceMs : Int64 = 300_000

///|
/// What the launcher knows of one owner: the model ("model") or a script's
/// program.
priv struct Owner {
  // Every job it started, live or ended: what it may address.
  jobs : Map[String, Unit]
  // The ones still live.
  live : Map[String, Unit]
  mut closed : Bool
  mut starts : Int32
  mut last_end_ms : Int64?
}

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
  env : Map[String, String]
  result_dir : String
  spawn : (async () -> Unit) -> Unit
  max_live : Int32
  max_workers : Int32
  grace_ms : Int32
  delivery_timeout_ms : Int32
  mut live : Int32
  // Captured reports by child session, kept for as long as this engine
  // runs, so a report whose store failed can still be read.
  reports : Map[String, Json]
  owners : Map[String, Owner]
  // The sessions of workers live in their worktrees, from before their
  // worktree is forked until it is captured, or in their directories.
  working : Map[String, Unit]
  // The directory each worker that works in place holds, by its session,
  // until its job has ended.
  directories : Map[String, String]
  // Worker sessions whose hand-off reached the model through this engine:
  // through their own job, or reported by `recover`.
  known : Map[String, Unit]
  // Workers admitted whose session is not claimed yet, so not in `working`:
  // counted against the cap from admission, which does not suspend.
  mut admitting : Int32
}

///|
/// A launcher for the session whose job runtime is `runtime` and whose
/// children's sessions `children` claims. `program` and `args` start a
/// child up to its kind (the engine's own binary, a managed `run`, its model
/// and endpoint); `cwd` is where it runs, and `env` is added to the
/// environment it inherits (a credential, kept off its command line). Result files are written in
/// `result_dir`, which is created when needed.
pub fn[X] Launcher::Launcher(
  scope : @agent_runtime.AgentTaskScope[X],
  runtime~ : @bgjobs.BgJobRuntime,
  children~ : @agent_subrun.ChildSession,
  program~ : String,
  args~ : Array[String],
  cwd? : String,
  env? : Map[String, String],
  result_dir~ : String,
  max_live~ : Int32 = MaxLive,
  max_workers~ : Int32 = MaxWorkers,
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
    env: env.unwrap_or(Map([])),
    result_dir,
    spawn: task => group.spawn_bg(task, no_wait=true, allow_failure=true),
    max_live,
    max_workers,
    grace_ms,
    delivery_timeout_ms,
    live: 0,
    reports: Map([]),
    owners: Map([]),
    working: Map([]),
    directories: Map([]),
    known: Map([]),
    admitting: 0,
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
  // Set by the cancel handler before it closes stdin, so teardown (which
  // requests no stop) is known too: a request write that fails after this
  // failed because of it, not first.
  mut stopping : Bool
  // The request could not be delivered, and that came first.
  mut delivery_failed : Bool
  mut workspace : @protocol.SubagentWorkspace
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
    workspace: self.workspace,
  }
}

///|
/// How many subagents may be live at once.
pub fn Launcher::max_live(self : Launcher) -> Int32 {
  self.max_live
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
/// or is cancelled after that gives its slot back; an ordinal it claimed
/// stays consumed. A started child holds its slot until its job's terminal
/// record is published.
/// `validate` is the kind's report check: a child is `Captured` only with a
/// result for this request whose output it accepts, and what it returns is
/// the report kept.
///
/// With a `workplace`, the child is a worker. In a `Worktree` it runs in a
/// worktree forked for it from the launching checkout, whose geometry is
/// added to its `input` (an object), and what it changed there is captured
/// from git and handed over when it ends. In a `Directory` it runs there,
/// which no other running worker's directory may overlap, and what it changed
/// is left there.
pub async fn Launcher::start(
  self : Launcher,
  kind~ : String,
  input~ : Json,
  label~ : String,
  max_steps? : Int32,
  launch~ : @protocol.SubagentLaunch,
  validate~ : (Json) -> Result[Json, String],
  workplace? : Workplace,
) -> StartResult {
  guard workplace is None || input is Object(_) else {
    return Unavailable("a worker's input must be an object")
  }
  guard workplace is None ||
    self.working.length() + self.admitting < self.max_workers else {
    return Unavailable(
      "\{self.max_workers} workers are already running; wait for one to end (job_wait) and start this one again",
    )
  }
  let owner = self.owner(launch)
  guard !owner.closed else {
    return Unavailable("its owner has ended and can start nothing more")
  }
  guard !(launch is Script(_)) || owner.starts < ScriptQuota else {
    return Unavailable("a script may start at most \{ScriptQuota} subagents")
  }
  guard self.live < self.max_live else { return Busy }
  self.live += 1
  let held = Ref(true)
  let release = () => {
    if held.val {
      held.val = false
      self.live -= 1
    }
  }
  // A worker holds its place under the cap until it is in `working`.
  let admitting = Ref(workplace is Some(_))
  if admitting.val {
    self.admitting += 1
  }
  let admitted = () => {
    if admitting.val {
      admitting.val = false
      self.admitting -= 1
    }
  }
  // Until the job is registered, every way out, cancellation included,
  // gives the slot back; after, the job does once it is published.
  let registered = Ref(false)
  errdefer {
    admitted()
    if !registered.val {
      release()
    }
  }
  let claimed = self.children.claim() catch {
    error => {
      admitted()
      release()
      return Unavailable("could not claim a child session: \{error}")
    }
  }
  let session = claimed.session
  // A start cut short before its job is registered leaves no worker: its
  // session leaves the running set too, so recovery can take what it forked,
  // and its directory is free.
  errdefer (if !registered.val {
    self.working.remove(session)
    self.directories.remove(session)
  })
  // A worker's worktree, forked once its session is known: the session
  // names it. From here until it is captured, recovery leaves it alone.
  let (provisioned, workspace, input) : (
    @subtask.Provisioned?,
    @protocol.SubagentWorkspace,
    Json,
  ) = match (workplace, input) {
    (Some(Worktree(slice)), Object(fields)) => {
      self.working[session] = ()
      admitted()
      match self.provision(slice, claimed) {
        Ok(provisioned) =>
          (
            Some(provisioned),
            Worktree(worktree_of(provisioned.entry)),
            worker_input(fields, provisioned),
          )
        Err(reason) => {
          self.working.remove(session)
          release()
          return Unavailable("could not fork a worktree: \{reason}")
        }
      }
    }
    (Some(Directory(path)), Object(fields)) => {
      self.working[session] = ()
      admitted()
      let held = match self.resolve_directory(path) {
        Ok(resolved) =>
          self.reserve_directory(session, resolved.directory).map(_ => resolved)
        Err(reason) => Err(reason)
      }
      match held {
        Ok(resolved) =>
          (
            None,
            Directory(path=resolved.directory),
            directory_input(fields, resolved),
          )
        Err(reason) => {
          self.working.remove(session)
          release()
          return Unavailable("could not give it \{path}: \{reason}")
        }
      }
    }
    _ => (None, InPlace, input)
  }
  // A start that fails from here gives its worktree or directory up.
  let abandon = async fn() {
    if provisioned is Some(provisioned) {
      ignore(@subtask.discard(provisioned.geometry, provisioned.entry))
    }
    self.working.remove(session)
    self.directories.remove(session)
  }
  let result_file = "\{self.result_dir}/\{session}.result.json"
  let child : Child = {
    kind,
    label,
    session,
    launch,
    outcome: None,
    usage: None,
    report: None,
    stopping: false,
    delivery_failed: false,
    workspace,
  }
  let (child_stdin, writer) = try {
    @fs.mkdir(self.result_dir, recursive=true, allow_exist=true)
    @process.write_to_process()
  } catch {
    error => {
      abandon()
      release()
      return Unavailable("could not prepare child \{session}: \{error}")
    }
  }
  let handler = @process.CancellationHandler(pid => {
    child.stopping = true
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
    cwd?=match workspace {
      Worktree(worktree) => Some(worktree.path)
      Directory(path~) => Some(path)
      InPlace => self.cwd
    },
    stdin=child_stdin,
    extra_env=self.env,
    cancel_handler=handler,
    on_end=end => {
      defer writer.close()
      // Left to recovery if capturing is cut short.
      defer self.working.remove(session)
      // The child has exited: its directory is free.
      defer self.directories.remove(session)
      self.settle(child, end, result_file~, validate~)
      if provisioned is Some(provisioned) {
        capture(child, provisioned)
      }
    },
    on_published=() => {
      release()
      owner.live.remove(child.session)
      owner.last_end_ms = Some(@env.now().reinterpret_as_int64())
    },
    subagent=() => child.info(),
    reaped=false,
  ) catch {
    error => {
      writer.close()
      abandon()
      release()
      return Unavailable("could not start child \{session}: \{error}")
    }
  }
  registered.val = true
  // Its hand-off reaches the model through its own job from here on.
  if workplace is Some(Worktree(_)) {
    self.known[session] = ()
  }
  owner.starts += 1
  owner.jobs[job_id] = ()
  owner.live[child.session] = ()
  let request : @protocol.RunRequest = {
    request_id: Some(session),
    kind: Some(kind),
    input,
    max_steps,
  }
  let line = request.to_json().stringify() + "\n"
  (self.spawn)(() => {
    @async.with_timeout(self.delivery_timeout_ms, () => writer.write(line)) catch {
      _ =>
        // Failed because the child was already being ended: a stop, a
        // watchdog (recorded when requested) or teardown (its handler).
        if !child.stopping && !self.runtime.stop_requested(job_id) {
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
  /// A result answering this child's request.
  Answered(@protocol.RunResult)
  /// A readable result, but for another request: not this child's account.
  Foreign
  /// A result file that could not be read, with the reason.
  Unreadable(String)
}

///|
async fn read_result(path : String, request_id : String) -> Left? {
  let text = @fs.read_file(path).text() catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => return None
    error => return Some(Unreadable("\{error}"))
  }
  let result = @protocol.parse_run_result(@json.parse(text)) catch {
    error => return Some(Unreadable("\{error}"))
  }
  Some(
    if result.request_id is Some(id) && id == request_id {
      Answered(result)
    } else {
      Foreign
    },
  )
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
  let left = read_result(result_file, child.session)
  let (accepted, rejected) : (Json?, String?) = match left {
    Some(Answered({ status: Completed(output~), .. })) =>
      match validate(output) {
        Ok(report) => (Some(report), None)
        Err(problem) => (None, Some(problem))
      }
    _ => (None, None)
  }
  // A report for this request that its kind accepts wins over every way
  // the child could have been ended: one written during a stop's grace
  // still counts. Otherwise the first cause of the end decides.
  child.outcome = Some(
    match (accepted, end) {
      (Some(_), _) => Captured
      _ if child.delivery_failed => Failed("request not delivered")
      (_, CaptureFailed(reason)) => Failed("output not captured: \{reason}")
      (_, OutputLimit) => Failed("output limit exceeded")
      (_, TimeLimit) => TimedOut
      (_, Stopped) => Stopped
      (_, Exited(code)) =>
        match (left, rejected) {
          (_, Some(problem)) => Failed("report rejected: \{problem}")
          (Some(Answered({ status: NoReport, .. })), _) => NoReport
          (Some(Answered({ status: MaxStepsExhausted, .. })), _) => MaxSteps
          (Some(Answered({ status: ContextYield(..), .. })), _) => ContextYield
          (Some(Answered({ status: Aborted(reason~), .. })), _)
          | (Some(Answered({ status: Interrupted(reason~), .. })), _)
          | (Some(Answered({ status: Failed(reason~), .. })), _) =>
            Failed(reason)
          (Some(Answered({ status: Completed(..), .. })), None) =>
            Failed("report rejected")
          (Some(Foreign), _) =>
            Failed("exited with code \{code} with a result for another request")
          (Some(Unreadable(reason)), _) =>
            Failed("unreadable result: \{reason}")
          (None, _) => Failed("exited with code \{code} without a result")
        }
    },
  )
  child.usage = Some(
    match left {
      Some(Answered({ usage: Some(usage), steps, .. })) =>
        Known(
          steps~,
          prompt_tokens=usage.prompt_tokens,
          completion_tokens=usage.completion_tokens,
          cost_usd=None,
          source=Result,
          unaccounted=None,
        )
      Some(Answered(_)) => Unavailable("the child never reached its turn")
      Some(Foreign) => Unavailable("the child's result was for another request")
      Some(Unreadable(_)) | None => Unavailable("the child left no result")
    },
  )
  if accepted is Some(report) {
    self.reports[child.session] = report
    child.report = Some(
      try {
        self.store.save_report(SessionId(child.session), report)
        Stored
      } catch {
        error => StoreFailed("\{error}")
      },
    )
  }
  @async.protect_from_cancel(() => @fs.remove(result_file)) catch {
    _ => ()
  }
}

///|
/// How a subagent ended, in words for the model.
pub fn describe_outcome(outcome : @protocol.SubagentOutcome) -> String {
  match outcome {
    Captured => "reported"
    NoReport => "finished without a report"
    MaxSteps => "ran out of steps without a report"
    ContextYield => "filled its context window without a report"
    TimedOut => "timed out without a report"
    Stopped => "stopped"
    Failed(reason) => "failed: \{reason}"
  }
}

///|
/// The subagent part of job `job_id`, or `None` for a job that is not one.
pub fn Launcher::subagent(
  self : Launcher,
  job_id : String,
) -> @protocol.SubagentInfo? {
  self.runtime.snapshot(job_id).bind(snapshot => snapshot.subagent)
}

///|
/// What `Launcher::send` did with an instruction.
pub(all) enum SendResult {
  /// Posted; the child reads it at its next step. `receipt` is what its
  /// transcript records once it has.
  Sent(receipt~ : String)
  /// The child has not opened its inbox: it has not started yet (retry), or
  /// its kind takes no instructions.
  NotReady
  /// The child has ended; nothing was posted.
  Ended
  /// No subagent job with that id.
  Unknown
  /// The message itself was refused, with the reason.
  Invalid(String)
}

///|
/// Post `text` to the running subagent `job_id` as an instruction from this
/// session, which the child takes at its next step, where user steering
/// lands.
pub async fn Launcher::send(
  self : Launcher,
  job_id : String,
  text : String,
) -> SendResult {
  guard self.runtime.snapshot(job_id)
    is Some({ subagent: Some(info), status, .. }) else {
    return Unknown
  }
  guard info.outcome is None && status is Running else { return Ended }
  guard !text.is_blank() else { return Invalid("the message is blank") }
  guard text.char_length() <= @inbox.MaxTextChars else {
    return Invalid("the message is over \{@inbox.MaxTextChars} characters")
  }
  let message = @inbox.Message(from=self.children.parent(), text~)
  let path = self.store.inbox_path(SessionId(info.session)) catch {
    error => return Invalid("\{error}")
  }
  if @inbox.post(path, message) {
    Sent(receipt=message.receipt())
  } else {
    NotReady
  }
}

///|
/// The owner a launch belongs to, created on first sight.
fn Launcher::owner(self : Launcher, launch : @protocol.SubagentLaunch) -> Owner {
  let key = match launch {
    Direct => "model"
    Script(program~, ..) => program
  }
  match self.owners.get(key) {
    Some(owner) => owner
    None => {
      let owner : Owner = {
        jobs: Map([]),
        live: Map([]),
        closed: false,
        starts: 0,
        last_end_ms: None,
      }
      self.owners[key] = owner
      owner
    }
  }
}

///|
/// How many subagents script `program` has started so far.
pub fn Launcher::started_by(self : Launcher, program : String) -> Int32 {
  match self.owners.get(program) {
    Some(owner) => owner.starts
    None => 0
  }
}

///|
/// Whether `job_id` is a subagent script `program` started.
pub fn Launcher::owns(
  self : Launcher,
  program : String,
  job_id : String,
) -> Bool {
  self.owners.get(program) is Some(owner) && owner.jobs.contains(job_id)
}

///|
/// Whether script `program` must outlive the wall-clock cap for now: it has
/// a live subagent, or its last one ended under five minutes ago.
pub fn Launcher::pinned(self : Launcher, program : String) -> Bool {
  guard self.owners.get(program) is Some(owner) else { return false }
  if !owner.live.is_empty() {
    return true
  }
  match owner.last_end_ms {
    Some(ended) =>
      @env.now().reinterpret_as_int64() - ended < CollectAllowanceMs
    None => false
  }
}

///|
/// Script `program` has ended: it can start nothing more, and its live
/// subagents are asked to stop. It does not wait for them to end: it runs in
/// the script job's own finish sequence, and at shutdown a child's is only
/// reached after it.
pub async fn Launcher::close_owner(self : Launcher, program : String) -> Unit {
  guard self.owners.get(program) is Some(owner) else { return }
  owner.closed = true
  for job_id in owner.jobs.keys().to_array() {
    if self.runtime.snapshot(job_id) is Some({ status: Running, .. }) {
      ignore(self.runtime.request_stop(job_id))
    }
  }
}
