///|
/// Default retained-output budget for a background job's inline preview, in
/// characters. Matches the `shell` tool's foreground default so a command reads
/// the same whether it runs in the foreground or the background. Full output
/// beyond this spills to the job's file (see `ShellOutputSink`).
let default_max_output_chars : Int = 12000

///|
/// Terminal or live state of a background job.
///
/// - `Running`: still executing (a detached-but-running execution also reads as
///   `Running` — a poller has no separate "detached" state).
/// - `Exited(code)`: exited on its own with `code`.
/// - `Stopped`: cancelled (`stop`, a reader error, or teardown) before exit.
pub(all) enum BgJobStatus {
  Running
  Exited(Int)
  Stopped
} derive(Eq)

///|
/// Default wall-clock lifetime for a background job (thirty minutes): long
/// enough for real builds and suites, short enough that a runaway spinner —
/// issue #419 saw one burn 131 minutes unnoticed — is reaped and surfaced.
pub let default_hard_timeout_ms : Int = 1_800_000

///|
/// Session-scoped registry of background ("detached") jobs, each backed by one
/// shared `@shell_exec.ShellExecution` (a process on `scope.group()`, a
/// file-backed output sink, and a status flag). Every child is spawned on the
/// session group, so its process is cancelled when the session's task group ends.
///
/// Cancellation reaches only the directly spawned process: the process library
/// exposes no process-group kill, so a command that daemonizes its own children
/// can leave descendants running after the job is reported terminal.
///
/// One `BgJobRuntime` is created per session and shared by the `shell`
/// (`run_in_background`), `shell_output`, and `shell_stop` tools. `new` captures
/// the session group in a spawn closure, so the runtime is not generic and can be
/// an optional tool argument.
pub struct BgJobRuntime {
  // Spawn a `ShellExecution` on the captured session group: (program, args, cwd,
  // inline-preview budget, spill path) -> execution. Captured so the runtime type
  // is not generic.
  priv spawn_exec : async (String, Array[String], String?, Int, String?) -> @shell_exec.ShellExecution
  // Spawn a *foreground* execution on the same session group: memory-only output
  // capped at the budget and killed if it fills, so the shell tool's foreground
  // path shares the execution model (and can be detached on timeout) without
  // re-deriving generic spawning at each call site.
  priv spawn_foreground_exec : async (String, Array[String], String?, Int) -> @shell_exec.ShellExecution
  // Spawn a *retained* foreground execution (may be detached on timeout):
  // file-backed with a large hard cap, but still killed on exceeding the inline
  // cap so a timed command that floods output is an immediate output-limit error;
  // `background()` clears that kill so a detached-under-the-limit job keeps
  // growing. The `String?` is the spill path.
  priv spawn_foreground_retained_exec : async (
    String,
    Array[String],
    String?,
    Int,
    String?,
  ) -> @shell_exec.ShellExecution
  // Spawn a per-job watcher task on that same group.
  priv spawn_watcher : (async () -> Unit) -> Unit
  // Directory for per-job spill files (full output beyond the inline preview).
  // None → memory-only jobs (no full-output file).
  priv spill_dir : String?
  // Wall-clock lifetime cap for any registered job, measured from process
  // start (an adopted job keeps its original deadline). Bounded lifetime,
  // not machine protection: the kill reaches the direct child only, so a
  // spinning grandchild can be orphaned — true process-group kill is
  // upstream work in moonbitlang/async. Tests shrink it to fire cheaply.
  priv hard_timeout_ms : Int
  // Called once, with the terminal snapshot, when a job exits on its own (not on
  // `stop`/teardown) — e.g. to push a completion notice into the agent loop.
  priv on_job_exit : ((BgJobSnapshot) -> Unit)?
  priv jobs : Map[String, BgJob]
  priv mut next_index : Int
  // Separate counter for the spill files of detachable foreground executions
  // (which are not registered until adopted), so their `fg-<n>.out` files never
  // collide with a job's `bg-<n>.out`.
  priv mut fg_index : Int
}

///|
/// One background job: session-visible metadata plus the shared execution that
/// owns the process, output, and status. Fully private — callers see only a
/// `BgJobSnapshot`.
priv struct BgJob {
  id : String
  command : String
  cwd : String?
  exec : @shell_exec.ShellExecution
  // Sandbox metadata carried from the launch (opaque to bgjobs) so a reader can
  // apply the same source-write-denial detection the foreground path does.
  source_write_sandboxed : Bool
  sandbox_denial_subjects : Array[String]
}

///|
/// An immutable view of a job's current state. `output` is the inline preview
/// (the first inline-budget characters); the *full* output — when `over_inline_cap`
/// — is read with `BgJobRuntime::read_output`.
pub struct BgJobSnapshot {
  id : String
  command : String
  cwd : String?
  status : BgJobStatus
  output : String
  output_truncated : Bool
  over_inline_cap : Bool
  size : Int
  seq : Int
  exit_code : Int?
  // Preserved so a reader can match the foreground path's error semantics: mark
  // binary output as an error, and detect a sandboxed source-write denial.
  had_invalid_utf8 : Bool
  source_write_sandboxed : Bool
  sandbox_denial_subjects : Array[String]
  // The job was killed by the output-limit watchdog (flooded past the hard cap),
  // not stopped on request — surfaced so the kill is never silent.
  killed_by_output_limit : Bool
  // The job was killed by the wall-clock reaper (outlived hard_timeout_ms),
  // not stopped on request — surfaced for the same reason.
  killed_by_time_limit : Bool
}

///|
/// Create an empty runtime whose jobs are owned by `scope.group()`. Jobs spill
/// full output into `spill_dir` (per-job files); omit it for memory-only jobs.
/// `hard_output_cap` bounds any single job's *full* retained output (characters);
/// the watchdog kills a job that floods past it — production uses the default,
/// tests shrink it to exercise the watchdog cheaply.
pub fn[X] BgJobRuntime::new(
  scope : @agent_runtime.AgentTaskScope[X],
  spill_dir? : String,
  hard_output_cap? : Int = @shell_exec.default_hard_cap,
  hard_timeout_ms? : Int = default_hard_timeout_ms,
  on_job_exit? : (BgJobSnapshot) -> Unit,
) -> BgJobRuntime {
  let group = scope.group()
  {
    spawn_exec: (program, args, cwd, max_output_chars, spill_path) => {
      // Background retention: inline preview up to the budget, full output to
      // the spill file, and the hard-cap watchdog so a flooding job is killed
      // (and surfaced) rather than left burning CPU with its output dropped.
      @shell_exec.ShellExecution::start(
        scope,
        program~,
        args~,
        cwd?,
        inline_cap=max_output_chars,
        hard_cap=hard_output_cap,
        spill_path?,
        kill_at_hard_cap=true,
      )
    },
    spawn_foreground_exec: (program, args, cwd, max_output_chars) => {
      // Foreground output-limit semantics: cap at exactly `max_output_chars`
      // (inline == hard) and kill on overflow, so exceeding it is reported as the
      // output-limit error, never silently dropped. Foreground is memory-only (no
      // spill) — full output is a background-job feature.
      @shell_exec.ShellExecution::start(
        scope,
        program~,
        args~,
        cwd?,
        inline_cap=max_output_chars,
        hard_cap=max_output_chars,
        kill_when_full=true,
      )
    },
    spawn_foreground_retained_exec: (
      program,
      args,
      cwd,
      max_output_chars,
      spill_path,
    ) => {
      // kill_at_hard_cap so that once detached (kill_when_full cleared by
      // `background()`), the job is still bounded in output like any other.
      @shell_exec.ShellExecution::start(
        scope,
        program~,
        args~,
        cwd?,
        inline_cap=max_output_chars,
        hard_cap=hard_output_cap,
        spill_path?,
        kill_when_full=true,
        kill_at_hard_cap=true,
      )
    },
    spawn_watcher: task => {
      group.spawn_bg(task, no_wait=true, allow_failure=true)
    },
    spill_dir,
    hard_timeout_ms,
    on_job_exit,
    jobs: {},
    next_index: 1,
    fg_index: 1,
  }
}

///|
fn BgJobRuntime::next_id(self : BgJobRuntime) -> String {
  let id = "bg-\{self.next_index}"
  self.next_index += 1
  id
}

///|
/// Spawn a *foreground* execution on the session group: memory-only output
/// capped at `max_output_chars` and killed if it fills. The shell tool's
/// foreground path uses this so foreground and background share one execution
/// model — and a timed-out foreground command can be `adopt`-ed (detached)
/// rather than killed. Positional to match the shell tool's spawner type.
pub async fn BgJobRuntime::spawn_foreground(
  self : BgJobRuntime,
  program : String,
  args : Array[String],
  cwd : String?,
  max_output_chars : Int,
) -> @shell_exec.ShellExecution {
  (self.spawn_foreground_exec)(program, args, cwd, max_output_chars)
}

///|
/// Spawn a foreground execution that may be *detached* (adopted) on timeout: it
/// uses the background retention config — file-backed (spill), a large hard cap,
/// no output-limit kill — so that if it is detached and keeps producing output,
/// `shell_output` still sees it. The foreground output-limit (over
/// `max_output_chars`) is enforced by the caller at display time, not by killing;
/// the caller's `timeout_ms` bounds the wait. Reuses the background spawn with a
/// distinct `fg-<n>.out` spill file.
pub async fn BgJobRuntime::spawn_foreground_retained(
  self : BgJobRuntime,
  program : String,
  args : Array[String],
  cwd : String?,
  max_output_chars : Int,
) -> @shell_exec.ShellExecution {
  let spill_path = self.spill_dir.map(dir => {
    let index = self.fg_index
    self.fg_index += 1
    "\{dir}/fg-\{index}.out"
  })
  (self.spawn_foreground_retained_exec)(
    program, args, cwd, max_output_chars, spill_path,
  )
}

///|
/// Spawn `program args` as a background job on the session group and return its
/// id. The job keeps running after this returns; `command` is the human-readable
/// command line shown to the model.
pub async fn BgJobRuntime::start(
  self : BgJobRuntime,
  program~ : String,
  args~ : Array[String],
  command~ : String,
  cwd? : String,
  max_output_chars? : Int = default_max_output_chars,
  source_write_sandboxed? : Bool = false,
  sandbox_denial_subjects? : Array[String] = [],
) -> String {
  // Reserve one id and use it for both the spill file and the registry entry, so
  // the job id and its `<id>.out` file never diverge.
  let id = self.next_id()
  let spill_path = self.spill_dir.map(dir => "\{dir}/\{id}.out")
  let exec = (self.spawn_exec)(program, args, cwd, max_output_chars, spill_path)
  self.register(
    id,
    exec,
    command~,
    cwd?,
    source_write_sandboxed~,
    sandbox_denial_subjects~,
  )
  id
}

///|
/// Register an already-running `ShellExecution` as a background job and return
/// its id. Used by detach-on-timeout: a foreground command that outlived its
/// timeout is `background()`-ed and adopted here, so `shell_output`/`shell_stop`
/// and the completion notice see it like any explicit background job.
pub fn BgJobRuntime::adopt(
  self : BgJobRuntime,
  exec : @shell_exec.ShellExecution,
  command~ : String,
  cwd? : String,
  source_write_sandboxed? : Bool = false,
  sandbox_denial_subjects? : Array[String] = [],
) -> String {
  let id = self.next_id()
  self.register(
    id,
    exec,
    command~,
    cwd?,
    source_write_sandboxed~,
    sandbox_denial_subjects~,
  )
  id
}

///|
/// Add a job to the registry under `id` and start its exit watcher.
fn BgJobRuntime::register(
  self : BgJobRuntime,
  id : String,
  exec : @shell_exec.ShellExecution,
  command~ : String,
  cwd? : String,
  source_write_sandboxed~ : Bool,
  sandbox_denial_subjects~ : Array[String],
) -> Unit {
  self.jobs[id] = {
    id,
    command,
    cwd,
    exec,
    source_write_sandboxed,
    sandbox_denial_subjects,
  }
  // Watch for the job ending on its own and fire `on_job_exit` once: a natural
  // exit, or the output-limit watchdog killing a flooding job — both must be
  // surfaced (a watchdog kill silently eating an unwatched job would look like
  // it just never finished). A requested stop (shell_stop, session teardown) is
  // already user-visible and fires nothing. The job entry is set above before
  // the watcher runs (the watcher first awaits the exit, ≥ one tick later), so
  // `snapshot(id)` always resolves.
  (self.spawn_watcher)(() => {
    exec.wait()
    guard self.on_job_exit is Some(callback) else { return }
    guard self.snapshot(id) is Some(snapshot) else { return }
    guard snapshot.status is Exited(_) ||
      snapshot.killed_by_output_limit ||
      snapshot.killed_by_time_limit else {
      return
    }
    callback(snapshot)
  })
  // Wall-clock reaper: every registered job has a bounded lifetime measured
  // from its process start, so a detached job's foreground wait counts
  // against the same deadline. The trip marks the reason before cancelling,
  // and the exit watcher above surfaces it like an output-limit kill.
  let remaining = self.hard_timeout_ms.to_int64() -
    (@env.now().reinterpret_as_int64() - exec.started_at_ms())
  (self.spawn_watcher)(() => {
    if remaining > 0L {
      @async.sleep(remaining.to_int())
    }
    exec.kill_for_time_limit()
  })
}

///|
/// Map an execution status onto the background-job status a poller sees. A
/// detached-but-running execution reads as `Running`; a killed one as `Stopped`.
fn bg_status(status : @shell_exec.ExecStatus) -> BgJobStatus {
  match status {
    Running | Backgrounded => Running
    Exited(code) => Exited(code)
    Killed => Stopped
  }
}

///|
fn BgJob::to_snapshot(self : BgJob) -> BgJobSnapshot {
  {
    id: self.id,
    command: self.command,
    cwd: self.cwd,
    status: bg_status(self.exec.status()),
    output: self.exec.head(),
    output_truncated: self.exec.output_truncated(),
    over_inline_cap: self.exec.over_inline_cap(),
    size: self.exec.size(),
    seq: self.exec.seq(),
    exit_code: self.exec.exit_code(),
    had_invalid_utf8: self.exec.had_invalid_utf8(),
    source_write_sandboxed: self.source_write_sandboxed,
    sandbox_denial_subjects: self.sandbox_denial_subjects,
    killed_by_output_limit: self.exec.killed_by_output_limit(),
    killed_by_time_limit: self.exec.killed_by_time_limit(),
  }
}

///|
/// The current state of one job (inline preview), or `None` for an unknown id.
pub fn BgJobRuntime::snapshot(
  self : BgJobRuntime,
  id : String,
) -> BgJobSnapshot? {
  self.jobs.get(id).map(job => job.to_snapshot())
}

///|
/// The full output of one job (reads the spill file for a large job), or `None`
/// for an unknown id.
pub async fn BgJobRuntime::read_output(
  self : BgJobRuntime,
  id : String,
) -> String? {
  match self.jobs.get(id) {
    Some(job) => Some(job.exec.read_all())
    None => None
  }
}

///|
/// The last `n` characters of one job's output — a bounded window onto recent
/// output — or `None` for an unknown id. Used by `shell_output` so a poll cannot
/// flood the conversation with a large job's full log.
pub async fn BgJobRuntime::read_output_tail(
  self : BgJobRuntime,
  id : String,
  n : Int,
) -> String? {
  match self.jobs.get(id) {
    Some(job) => Some(job.exec.read_tail(n))
    None => None
  }
}

///|
/// Await the job reaching a terminal status, up to `timeout_ms`. Returns `true`
/// once terminal, `false` on deadline or an unknown id. This is the await
/// primitive behind `shell_output`'s `wait_ms`: a caller that needs the result
/// *now* blocks here once instead of burning model round trips on polling.
pub async fn BgJobRuntime::wait_exit(
  self : BgJobRuntime,
  id : String,
  timeout_ms : Int,
) -> Bool {
  match self.jobs.get(id) {
    Some(job) =>
      @async.with_timeout_opt(timeout_ms, () => job.exec.wait()) is Some(_)
    None => false
  }
}

///|
/// Snapshots of every job the session has started.
pub fn BgJobRuntime::list(self : BgJobRuntime) -> Array[BgJobSnapshot] {
  [
    for _, job in self.jobs => job.to_snapshot()
  ]
}

///|
/// Cancel a running job and return once it is terminal. Idempotent: an
/// already-terminal known job returns `true`; an unknown id returns `false`.
pub async fn BgJobRuntime::stop(self : BgJobRuntime, id : String) -> Bool {
  guard self.jobs.get(id) is Some(job) else { return false }
  let _ = job.exec.stop()
  true
}
