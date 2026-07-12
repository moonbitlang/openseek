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
    jobs: Map([]),
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

///|
/// Poll `id` until it leaves `Running`, failing after a bounded deadline so a
/// hung child can never hang the test. Async tests run in parallel, so each test
/// isolates its own runtime and jobs.
#cfg(not(platform="windows"))
async fn poll_until_terminal(
  rt : BgJobRuntime,
  id : String,
  ticks? : Int = 200,
) -> BgJobSnapshot {
  for _ in 0..<ticks {
    if rt.snapshot(id) is Some(snap) && !(snap.status is Running) {
      return snap
    }
    @async.sleep(25)
  }
  fail("bg job \{id} did not reach a terminal state in time")
}

///|
/// Await the first pushed exit notice, on the same 200 x 25ms budget as
/// `poll_until_terminal`.
#cfg(not(platform="windows"))
async fn wait_for_first(notices : Array[BgJobSnapshot]) -> Unit {
  for _ in 0..<200 {
    if notices.length() > 0 {
      return
    }
    @async.sleep(25)
  }
}

///|
#cfg(not(platform="windows"))
async test "bg job runs to completion and captures output" {
  @async.with_task_group(group => {
    let rt = BgJobRuntime::new(AgentTaskScope(group))
    let id = rt.start(
      program="sh",
      args=["-c", "printf hello"],
      command="printf hello",
    )
    let snap = poll_until_terminal(rt, id)
    assert_true(snap.status is Exited(0))
    assert_true(snap.output.contains("hello"))
    assert_true(snap.exit_code is Some(0))
  })
}

///|
#cfg(not(platform="windows"))
async test "bg job records a non-zero exit code" {
  @async.with_task_group(group => {
    let rt = BgJobRuntime::new(AgentTaskScope(group))
    let id = rt.start(program="sh", args=["-c", "exit 3"], command="exit 3")
    let snap = poll_until_terminal(rt, id)
    assert_true(snap.status is Exited(3))
    assert_true(snap.exit_code is Some(3))
  })
}

///|
#cfg(not(platform="windows"))
async test "stop terminates a running job" {
  @async.with_task_group(group => {
    let rt = BgJobRuntime::new(AgentTaskScope(group))
    let id = rt.start(program="sleep", args=["30"], command="sleep 30")
    @async.sleep(50)
    assert_true(rt.snapshot(id).unwrap().status is Running)
    assert_true(rt.stop(id))
    assert_true(rt.snapshot(id).unwrap().status is Stopped)
  })
}

///|
#cfg(not(platform="windows"))
async test "a large-output job spills; snapshot previews, read_output is full" {
  @async.with_task_group(group => {
    let rt = BgJobRuntime::new(AgentTaskScope(group), spill_dir="/tmp")
    let id = rt.start(
      program="sh",
      args=["-c", "seq 1 5000"],
      command="seq",
      max_output_chars=100,
    )
    let snap = poll_until_terminal(rt, id)
    assert_true(snap.status is Exited(0))
    assert_true(snap.over_inline_cap)
    // The snapshot output is a bounded preview...
    assert_true(snap.output.char_length() <= 100)
    // ...while read_output returns the full output from the spill file.
    let full = rt.read_output(id).unwrap()
    assert_true(full.has_prefix("1\n"))
    assert_true(full.contains("5000"))
  })
}

///|
#cfg(not(platform="windows"))
async test "adopt registers an already-running execution as a job" {
  @async.with_task_group(group => {
    let scope : @agent_runtime.AgentTaskScope[Unit] = AgentTaskScope(group)
    let rt = BgJobRuntime::new(scope)
    let exec = @shell_exec.ShellExecution::start(scope, program="sleep", args=[
      "30",
    ])
    let id = rt.adopt(exec, command="sleep 30")
    @async.sleep(50)
    assert_true(rt.snapshot(id).unwrap().status is Running)
    assert_true(rt.stop(id))
    assert_true(rt.snapshot(id).unwrap().status is Stopped)
  })
}

///|
#cfg(not(platform="windows"))
async test "on_job_exit fires once on a natural exit, never on stop" {
  @async.with_task_group(group => {
    let seen : Array[BgJobSnapshot] = []
    let rt = BgJobRuntime::new(AgentTaskScope(group), on_job_exit=snapshot => {
      seen.push(snapshot)
    })
    let done = rt.start(
      program="sh",
      args=["-c", "printf done"],
      command="printf done",
    )
    let stopped = rt.start(program="sleep", args=["30"], command="sleep 30")
    @async.sleep(50)
    assert_true(rt.stop(stopped))
    wait_for_first(seen)
    @async.sleep(50)
    // Exactly one notice — for the natural exit, not the stopped job.
    assert_true(seen.length() == 1)
    assert_true(seen[0].id == done)
    assert_true(seen[0].status is Exited(0))
  })
}

///|
#cfg(not(platform="windows"))
async test "snapshot, read_output, and stop handle unknown ids" {
  @async.with_task_group(group => {
    let rt = BgJobRuntime::new(AgentTaskScope(group))
    assert_true(rt.snapshot("nope") is None)
    assert_true(rt.read_output("nope") is None)
    assert_false(rt.stop("nope"))
  })
}

///|
#cfg(not(platform="windows"))
async test "start allocates one id per job (id matches its spill file)" {
  @async.with_task_group(group => {
    let rt = BgJobRuntime::new(AgentTaskScope(group), spill_dir="/tmp")
    // The first started job is bg-1 (not bg-2): start must not reserve an id for
    // the spill path and then allocate a second one for the registry entry.
    let a = rt.start(program="sh", args=["-c", "printf a"], command="a")
    assert_true(a == "bg-1")
    let b = rt.start(program="sh", args=["-c", "printf b"], command="b")
    assert_true(b == "bg-2")
  })
}

///|
#cfg(not(platform="windows"))
async test "two jobs run independently with distinct ids" {
  @async.with_task_group(group => {
    let rt = BgJobRuntime::new(AgentTaskScope(group))
    let a = rt.start(program="sh", args=["-c", "printf aaa"], command="a")
    let b = rt.start(program="sh", args=["-c", "printf bbb"], command="b")
    assert_true(a != b)
    let sa = poll_until_terminal(rt, a)
    let sb = poll_until_terminal(rt, b)
    assert_true(sa.output.contains("aaa"))
    assert_true(sb.output.contains("bbb"))
    assert_true(rt.list().length() == 2)
  })
}

///|
#cfg(not(platform="windows"))
async test "the watchdog kills a background job that floods past the hard cap" {
  @async.with_task_group(group => {
    let notices : Array[BgJobSnapshot] = []
    // Tiny hard cap so `yes` trips the watchdog immediately instead of running
    // to the 20M default.
    let rt = BgJobRuntime::new(AgentTaskScope(group), hard_output_cap=200, on_job_exit=snapshot => {
      notices.push(snapshot)
    })
    let id = rt.start(program="yes", args=[], command="yes")
    let snapshot = poll_until_terminal(rt, id)
    // Killed by the watchdog — not left running with its output dropped — and
    // reported as such, not as a requested stop.
    assert_true(snapshot.status is Stopped)
    assert_true(snapshot.killed_by_output_limit)
    assert_true(snapshot.output_truncated)
    // The kill is pushed like a natural exit: a silently dead job would look
    // like it just never finished.
    wait_for_first(notices)
    assert_true(notices.length() == 1)
    assert_true(notices[0].killed_by_output_limit)
  })
}

///|
#cfg(not(platform="windows"))
async test "the reaper kills a background job that outlives the time cap" {
  @async.with_task_group(group => {
    let notices : Array[BgJobSnapshot] = []
    let rt = BgJobRuntime::new(AgentTaskScope(group), hard_timeout_ms=80, on_job_exit=snapshot => {
      notices.push(snapshot)
    })
    let id = rt.start(program="sh", args=["-c", "sleep 5"], command="sleep 5")
    let snapshot = poll_until_terminal(rt, id)
    assert_true(snapshot.status is Stopped)
    assert_true(snapshot.killed_by_time_limit)
    assert_false(snapshot.killed_by_output_limit)
    // The kill is surfaced exactly once, like an output-cap kill.
    wait_for_first(notices)
    assert_true(notices.length() == 1)
    assert_true(notices[0].killed_by_time_limit)
  })
}

///|
#cfg(not(platform="windows"))
async test "an adopted job keeps its original wall-clock deadline" {
  @async.with_task_group(group => {
    let rt = BgJobRuntime::new(AgentTaskScope(group), hard_timeout_ms=150)
    // The execution starts OUTSIDE the registry (a foreground command) and
    // burns most of its lifetime before being adopted on detach.
    let exec = rt.spawn_foreground_retained("sh", ["-c", "sleep 5"], None, 200)
    @async.sleep(120)
    let _ = exec.background()
    let id = rt.adopt(exec, command="sleep 5", source_write_sandboxed=false, sandbox_denial_subjects=[])
    // Deadline measured from process start: ~30ms remain, not a fresh 150ms —
    // the poll budget below is far under 150ms of slack either way.
    let snapshot = poll_until_terminal(rt, id, ticks=40)
    assert_true(snapshot.killed_by_time_limit)
  })
}

///|
#cfg(not(platform="windows"))
async test "a requested stop is not blamed on the reaper" {
  @async.with_task_group(group => {
    let rt = BgJobRuntime::new(AgentTaskScope(group), hard_timeout_ms=60_000)
    let id = rt.start(program="sh", args=["-c", "sleep 5"], command="sleep 5")
    let _ = rt.stop(id)
    guard rt.snapshot(id) is Some(snapshot) else { fail("expected snapshot") }
    assert_false(snapshot.killed_by_time_limit)
    assert_false(snapshot.killed_by_output_limit)
  })
}
