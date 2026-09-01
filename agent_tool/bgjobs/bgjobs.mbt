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
pub enum BgJobStatus {
  Running
  Exited(Int)
  Stopped
} derive(Eq)

///|
/// Default wall-clock lifetime for a background job (thirty minutes): long
/// enough for real builds and suites, short enough that a runaway spinner —
/// issue #419 saw one burn 131 minutes unnoticed — is reaped and surfaced.
let default_hard_timeout_ms : Int = 1_800_000

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
/// (`run_in_background`), `shell_output`, and `shell_stop` tools. the constructor captures
/// the session group in a spawn closure, so the runtime is not generic and can be
/// an optional tool argument.
pub struct BgJobRuntime {
  // Spawn a `ShellExecution` on the captured session group: (program, args, cwd,
  // inline-preview budget, spill path) -> execution. Captured so the runtime type
  // is not generic.
  priv spawn_exec : async (
    String,
    Array[String],
    String?,
    Int,
    String?,
    &@process.ProcessInput?,
  ) -> @shell_exec.ShellExecution
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
    &@process.ProcessInput?,
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
  // The opaque prepared command is carried from launch so a reader can apply
  // the same source-write-denial detection the foreground path does.
  sandboxed_command : @sandbox.SandboxedCommand?
  // Preserve the shell policy context that decides whether a standalone
  // trusted writer is a valid recovery from a sandbox denial.
  read_only_review : Bool
  // Display-only rewrites carried by the launching tool (for example, mapping
  // a throwaway compiler path back to the submitted source name).
  output_rewrites : Array[(String, String)]
  // True only when the launching tool enabled moonrun's policy, so ordinary
  // job output resembling a refusal cannot be misclassified as one.
  moonrun_policy_active : Bool
  // Optional launcher-owned resources to reclaim once the process is terminal.
  // Cleared before invocation so cleanup is exactly once even if more terminal
  // observers are added later.
  mut on_terminal : (async () -> Unit)?
  // Optional launcher-supplied classification of a terminal exit (mbtx uses it
  // to separate "the snippet never built" from "the program ran and failed").
  // Called with the exit code (`None` for a killed job) once the process is
  // terminal — BEFORE `on_terminal`, because the classifier's evidence is
  // often exactly what that cleanup deletes. It must settle promptly: a
  // waiter (the exit watcher included, so cleanup too) blocks on an in-flight
  // computation.
  exit_note_fn : (async (Int?) -> String?)?
  mut exit_note_state : ExitNoteState
  // A terminal denial scan may read a large retained log. Cache its
  // classification so repeated job_output calls do not repeat that allocation.
  mut denial_scanned : Bool
  mut denial_feedback : String?
}

///|
/// Lifecycle of a job's launcher-supplied exit classification. Single-flight
/// on purpose: exactly one task may run the classifier, because a second
/// computation could start before the terminal cleanup deletes the
/// classifier's evidence, finish after it, and overwrite a correct cached
/// answer with one read from the emptied directory.
priv enum ExitNoteState {
  NotComputed
  Computing
  Cached(String?)
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
  sandboxed_command : @sandbox.SandboxedCommand?
  read_only_review : Bool
  output_rewrites : Array[(String, String)]
  moonrun_policy_active : Bool
  // The job was killed by the output-limit watchdog (flooded past the hard cap),
  // not stopped on request — surfaced so the kill is never silent.
  killed_by_output_limit : Bool
  // The job was killed by the wall-clock reaper (outlived hard_timeout_ms),
  // not stopped on request — surfaced for the same reason.
  killed_by_time_limit : Bool
  // The launcher's cached classification of a terminal exit, `None` until the
  // exit watcher computes it (or when there is nothing to say). Readers that
  // must not race that computation use `BgJobRuntime::exit_note` instead.
  exit_note : String?
}

///|
/// Create an empty runtime whose jobs are owned by `scope.group()`. Jobs spill
/// full output into `spill_dir` (per-job files); omit it for memory-only jobs.
/// `hard_output_cap` bounds any single job's *full* retained output (characters);
/// the watchdog kills a job that floods past it — production uses the default,
/// tests shrink it to exercise the watchdog cheaply.
pub fn[X] BgJobRuntime::BgJobRuntime(
  scope : @agent_runtime.AgentTaskScope[X],
  spill_dir? : String,
  hard_output_cap? : Int = @shell_exec.default_hard_cap,
  hard_timeout_ms? : Int = default_hard_timeout_ms,
  on_job_exit? : (BgJobSnapshot) -> Unit,
) -> BgJobRuntime {
  let group = scope.group()
  {
    spawn_exec: (program, args, cwd, max_output_chars, spill_path, stdin) => {
      // Background retention: inline preview up to the budget, full output to
      // the spill file, and the hard-cap watchdog so a flooding job is killed
      // (and surfaced) rather than left burning CPU with its output dropped.
      @shell_exec.ShellExecution::start(
        scope,
        program~,
        args~,
        cwd?,
        stdin?,
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
      stdin,
    ) => {
      // kill_at_hard_cap so that once detached (kill_when_full cleared by
      // `background()`), the job is still bounded in output like any other.
      @shell_exec.ShellExecution::start(
        scope,
        program~,
        args~,
        cwd?,
        stdin?,
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
  stdin? : &@process.ProcessInput,
) -> @shell_exec.ShellExecution {
  let spill_path = self.spill_dir.map(dir => {
    let index = self.fg_index
    self.fg_index += 1
    "\{dir}/fg-\{index}.out"
  })
  (self.spawn_foreground_retained_exec)(
    program, args, cwd, max_output_chars, spill_path, stdin,
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
  sandboxed_command? : @sandbox.SandboxedCommand,
  read_only_review? : Bool = false,
  output_rewrites? : Array[(String, String)] = [],
  moonrun_policy_active? : Bool = false,
  stdin? : &@process.ProcessInput,
) -> String {
  // Reserve one id and use it for both the spill file and the registry entry, so
  // the job id and its `<id>.out` file never diverge.
  let id = self.next_id()
  let spill_path = self.spill_dir.map(dir => "\{dir}/\{id}.out")
  let exec = (self.spawn_exec)(
    program, args, cwd, max_output_chars, spill_path, stdin,
  )
  self.register(
    id,
    exec,
    command~,
    cwd?,
    sandboxed_command?,
    read_only_review~,
    output_rewrites~,
    moonrun_policy_active~,
    on_terminal=None,
    exit_note_fn=None,
  )
  id
}

///|
/// Register an already-running `ShellExecution` as a background job and return
/// its id. Used by detach-on-timeout: a foreground command that outlived its
/// timeout is `background()`-ed and adopted here, so `shell_output`/`shell_stop`
/// and the completion notice see it like any explicit background job.
///
/// `exit_note` lets the launcher classify the exit for readers of the finished
/// job (the completion notice, `job_output`): it is called with the exit code
/// (`None` for a killed job) once the process is terminal, before `on_terminal`
/// reclaims launcher resources — so it may still read evidence that cleanup is
/// about to delete — and its answer is cached on the job.
pub fn BgJobRuntime::adopt(
  self : BgJobRuntime,
  exec : @shell_exec.ShellExecution,
  command~ : String,
  cwd? : String,
  sandboxed_command? : @sandbox.SandboxedCommand,
  read_only_review? : Bool = false,
  output_rewrites? : Array[(String, String)] = [],
  moonrun_policy_active? : Bool = false,
  on_terminal? : async () -> Unit,
  exit_note? : async (Int?) -> String?,
) -> String {
  let id = self.next_id()
  self.register(
    id,
    exec,
    command~,
    cwd?,
    sandboxed_command?,
    read_only_review~,
    output_rewrites~,
    moonrun_policy_active~,
    on_terminal~,
    exit_note_fn=exit_note,
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
  sandboxed_command? : @sandbox.SandboxedCommand,
  read_only_review~ : Bool,
  output_rewrites~ : Array[(String, String)],
  moonrun_policy_active~ : Bool,
  on_terminal~ : (async () -> Unit)?,
  exit_note_fn~ : (async (Int?) -> String?)?,
) -> Unit {
  self.jobs[id] = {
    id,
    command,
    cwd,
    exec,
    sandboxed_command,
    read_only_review,
    output_rewrites: output_rewrites.copy(),
    moonrun_policy_active,
    on_terminal,
    exit_note_fn,
    exit_note_state: NotComputed,
    denial_scanned: false,
    denial_feedback: None,
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
    // Compute (and cache) the launcher's exit note FIRST: its evidence — an
    // mbtx build artifact, say — is often exactly what the terminal cleanup
    // below deletes. Advisory, so a failed or cancelled classification must
    // not skip that cleanup.
    let _ = self.exit_note(id) catch { _ => None }

    // The output spill belongs to the runtime, but a launcher may also have
    // handed the job a separate build directory. Reclaim that directory for
    // natural exit, watchdog kills, and requested stops alike.
    if self.jobs.get(id) is Some(job) && job.on_terminal is Some(cleanup) {
      job.on_terminal = None
      cleanup()
    }
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
    sandboxed_command: self.sandboxed_command,
    read_only_review: self.read_only_review,
    output_rewrites: self.output_rewrites.copy(),
    moonrun_policy_active: self.moonrun_policy_active,
    killed_by_output_limit: self.exec.killed_by_output_limit(),
    killed_by_time_limit: self.exec.killed_by_time_limit(),
    exit_note: match self.exit_note_state {
      Cached(note) => note
      NotComputed | Computing => None
    },
  }
}

///|
/// The launcher's classification of a terminal job's exit — `None` while the
/// job still runs, when the launcher supplied no classifier, or when it had
/// nothing to say. Computed exactly once (single-flight) and cached: the exit
/// watcher calls this before `on_terminal`, so the classifier reads launcher
/// resources that cleanup is about to reclaim, and every other caller —
/// including one racing that first computation — waits for its answer rather
/// than recomputing. Recomputing was a live bug: a reader that entered before
/// the watcher's answer landed could finish AFTER cleanup emptied the
/// evidence directory and overwrite the correct note with a wrong one.
pub async fn BgJobRuntime::exit_note(
  self : BgJobRuntime,
  id : String,
) -> String? {
  guard self.jobs.get(id) is Some(job) else { return None }
  guard !(bg_status(job.exec.status()) is Running) else { return None }
  for ;; {
    match job.exit_note_state {
      Cached(note) => return note
      // Another task holds the flight; await its answer. (The single-threaded
      // scheduler makes the NotComputed→Computing transition below atomic, so
      // two tasks can never both claim it.)
      Computing => @async.sleep(5)
      NotComputed => {
        guard job.exit_note_fn is Some(classify) else {
          job.exit_note_state = Cached(None)
          return None
        }
        job.exit_note_state = Computing
        let note = classify(job.exec.exit_code()) catch {
          error if @async.is_being_cancelled() => {
            // A cancelled computation decided nothing: release the flight so
            // the next caller (usually the exit watcher) computes, instead of
            // caching a guess or wedging every waiter.
            job.exit_note_state = NotComputed
            raise error
          }
          // A real classifier failure is an answer of its own — caching it as
          // "nothing to say" would silently erase the failure stage from the
          // notice and job_output.
          error => Some("exit-stage classification failed (\{error}).")
        }
        job.exit_note_state = Cached(note)
        return note
      }
    }
  }
}

///|
/// Classify a terminal job's complete retained output once. Running jobs return
/// `None`; their recent tail can still be checked cheaply by the caller. The
/// cached result avoids decoding a log of up to the hard cap on every later
/// `job_output` call.
pub async fn BgJobRuntime::terminal_denial_feedback(
  self : BgJobRuntime,
  id : String,
) -> String? {
  guard self.jobs.get(id) is Some(job) else { return None }
  guard !(bg_status(job.exec.status()) is Running) else { return None }
  if job.denial_scanned {
    return job.denial_feedback
  }
  // Most non-wasm and escalated jobs have no active denial classifier. Do not
  // materialize their complete retained log merely to prove there is nothing
  // to classify; a handed-off job may hold up to the 20MB hard cap while
  // job_output itself renders only a bounded tail.
  if !job.moonrun_policy_active && job.sandboxed_command is None {
    job.denial_scanned = true
    return None
  }
  let output = job.exec.read_all()
  let feedback = if job.moonrun_policy_active &&
    @sandbox.output_reports_policy_refusal(output) {
    Some(@sandbox.policy_refusal_feedback)
  } else if job.sandboxed_command is Some(command) &&
    command.output_reports_denial(output) {
    Some(command.denial_feedback())
  } else {
    None
  }
  job.denial_feedback = feedback
  job.denial_scanned = true
  feedback
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
    let rt = BgJobRuntime::BgJobRuntime(AgentTaskScope(group))
    let id = rt.start(
      program="sh",
      args=["-c", "printf hello"],
      command="printf hello",
      read_only_review=true,
    )
    let snap = poll_until_terminal(rt, id)
    assert_true(snap.status is Exited(0))
    assert_true(snap.output.contains("hello"))
    assert_true(snap.exit_code is Some(0))
    assert_true(snap.read_only_review)
  })
}

///|
#cfg(not(platform="windows"))
async test "bg job records a non-zero exit code" {
  @async.with_task_group(group => {
    let rt = BgJobRuntime::BgJobRuntime(AgentTaskScope(group))
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
    let rt = BgJobRuntime::BgJobRuntime(AgentTaskScope(group))
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
    let rt = BgJobRuntime::BgJobRuntime(AgentTaskScope(group), spill_dir="/tmp")
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
    let rt = BgJobRuntime::BgJobRuntime(scope)
    let exec = @shell_exec.ShellExecution::start(scope, program="sleep", args=[
      "30",
    ])
    let id = rt.adopt(exec, command="sleep 30", read_only_review=true)
    @async.sleep(50)
    assert_true(rt.snapshot(id).unwrap().status is Running)
    assert_true(rt.snapshot(id).unwrap().read_only_review)
    assert_true(rt.stop(id))
    assert_true(rt.snapshot(id).unwrap().status is Stopped)
  })
}

///|
/// The exit note must be computed while the launcher's evidence still exists:
/// the classifier here observes the cleanup flag that `on_terminal` flips, and
/// a note computed after cleanup would misclassify every launcher whose
/// evidence lives in the directory that cleanup reclaims (mbtx's build
/// artifact probe is exactly that).
#cfg(not(platform="windows"))
async test "the exit note is computed before terminal cleanup" {
  @async.with_task_group(group => {
    let scope : @agent_runtime.AgentTaskScope[Unit] = AgentTaskScope(group)
    let rt = BgJobRuntime::BgJobRuntime(scope)
    let exec = @shell_exec.ShellExecution::start(scope, program="sh", args=[
      "-c", "exit 3",
    ])
    let received : Array[Int?] = []
    let mut cleaned = false
    let id = rt.adopt(
      exec,
      command="exit 3",
      exit_note=code => {
        received.push(code)
        Some("cleaned=\{cleaned}")
      },
      on_terminal=() => cleaned = true,
    )
    for _ in 0..<200 {
      if cleaned {
        break
      }
      @async.sleep(5)
    }
    assert_true(cleaned)
    assert_true(rt.exit_note(id) is Some("cleaned=false"))
    // The classifier saw the real exit code, exactly once.
    assert_true(received is [Some(3)])
    // The cached note is also on the snapshot for sync readers (the notice).
    assert_true(rt.snapshot(id).unwrap().exit_note is Some("cleaned=false"))
  })
}

///|
/// Regression (review finding): a reader that entered classification while
/// the watcher's flight was still running used to RECOMPUTE — finishing after
/// terminal cleanup had emptied the evidence directory and overwriting the
/// correct cached note with one read from the emptied state. Single-flight
/// means the late reader waits for the flight's answer and the classifier
/// runs exactly once, strictly before cleanup.
#cfg(not(platform="windows"))
async test "a reader racing the exit watcher joins its flight, never recomputes" {
  @async.with_task_group(group => {
    let scope : @agent_runtime.AgentTaskScope[Unit] = AgentTaskScope(group)
    let rt = BgJobRuntime::BgJobRuntime(scope)
    let exec = @shell_exec.ShellExecution::start(scope, program="sh", args=[
      "-c", "exit 3",
    ])
    let mut calls = 0
    let mut cleaned = false
    let id = rt.adopt(
      exec,
      command="exit 3",
      exit_note=_ => {
        calls += 1
        // Hold the flight open long enough for the reader below to land in it.
        @async.sleep(100)
        Some(if cleaned { "missing" } else { "present" })
      },
      on_terminal=() => cleaned = true,
    )
    // Enter the accessor while the watcher's classification is in flight.
    for _ in 0..<200 {
      if calls == 1 {
        break
      }
      @async.sleep(5)
    }
    assert_true(rt.exit_note(id) is Some("present"))
    assert_true(rt.snapshot(id).unwrap().exit_note is Some("present"))
    assert_eq(calls, 1)
  })
}

///|
/// A classifier failure is an answer of its own: folding it into "nothing to
/// say" would silently erase the failure stage from the completion notice and
/// job_output.
#cfg(not(platform="windows"))
async test "a failing classifier is reported, not silently dropped" {
  @async.with_task_group(group => {
    let scope : @agent_runtime.AgentTaskScope[Unit] = AgentTaskScope(group)
    let rt = BgJobRuntime::BgJobRuntime(scope)
    let exec = @shell_exec.ShellExecution::start(scope, program="sh", args=[
      "-c", "exit 3",
    ])
    let id = rt.adopt(exec, command="exit 3", exit_note=_ => {
      fail("probe exploded")
    })
    let _ = rt.wait_exit(id, 30_000)
    guard rt.exit_note(id) is Some(note) else {
      fail("expected a tagged failure note")
    }
    assert_true(note.contains("classification failed"))
    assert_true(note.contains("probe exploded"))
  })
}

///|
#cfg(not(platform="windows"))
async test "exit_note is None while running and a kill carries no exit code" {
  @async.with_task_group(group => {
    let scope : @agent_runtime.AgentTaskScope[Unit] = AgentTaskScope(group)
    let rt = BgJobRuntime::BgJobRuntime(scope)
    let exec = @shell_exec.ShellExecution::start(scope, program="sleep", args=[
      "30",
    ])
    let id = rt.adopt(exec, command="sleep 30", exit_note=code => {
      Some("code=\{Repr(code)}")
    })
    @async.sleep(50)
    // No classification before the job is terminal.
    assert_true(rt.exit_note(id) is None)
    assert_true(rt.stop(id))
    // A killed job has no exit code of its own to classify.
    assert_true(rt.exit_note(id) is Some("code=None"))
    // A job whose launcher supplied no classifier stays unclassified.
    let plain = rt.start(program="sh", args=["-c", "exit 2"], command="exit 2")
    let _ = poll_until_terminal(rt, plain)
    assert_true(rt.exit_note(plain) is None)
    assert_true(rt.exit_note("nope") is None)
  })
}

///|
#cfg(not(platform="windows"))
async test "an adopted job runs terminal cleanup once when stopped" {
  @async.with_task_group(group => {
    let scope : @agent_runtime.AgentTaskScope[Unit] = AgentTaskScope(group)
    let rt = BgJobRuntime::BgJobRuntime(scope)
    let exec = @shell_exec.ShellExecution::start(scope, program="sleep", args=[
      "30",
    ])
    let mut cleanups = 0
    let id = rt.adopt(exec, command="sleep 30", on_terminal=() => cleanups += 1)
    assert_true(rt.stop(id))
    for _ in 0..<200 {
      if cleanups == 1 {
        break
      }
      @async.sleep(5)
    }
    assert_eq(cleanups, 1)
  })
}

///|
#cfg(not(platform="windows"))
async test "job snapshots do not alias launcher rewrite arrays" {
  @async.with_task_group(group => {
    let rt = BgJobRuntime::BgJobRuntime(AgentTaskScope(group))
    let rewrites = [("temporary", "source")]
    let id = rt.start(
      program="sh",
      args=["-c", "printf done"],
      command="printf done",
      output_rewrites=rewrites,
    )
    rewrites.push(("later", "mutation"))
    let first = rt.snapshot(id).unwrap()
    assert_eq(first.output_rewrites, [("temporary", "source")])
    first.output_rewrites.push(("snapshot", "mutation"))
    let second = rt.snapshot(id).unwrap()
    assert_eq(second.output_rewrites, [("temporary", "source")])
  })
}

///|
#cfg(not(platform="windows"))
async test "on_job_exit fires once on a natural exit, never on stop" {
  @async.with_task_group(group => {
    let seen : Array[BgJobSnapshot] = []
    let rt = BgJobRuntime::BgJobRuntime(AgentTaskScope(group), on_job_exit=snapshot => {
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
    let rt = BgJobRuntime::BgJobRuntime(AgentTaskScope(group))
    assert_true(rt.snapshot("nope") is None)
    assert_true(rt.read_output("nope") is None)
    assert_false(rt.stop("nope"))
  })
}

///|
#cfg(not(platform="windows"))
async test "start allocates one id per job (id matches its spill file)" {
  @async.with_task_group(group => {
    let rt = BgJobRuntime::BgJobRuntime(AgentTaskScope(group), spill_dir="/tmp")
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
    let rt = BgJobRuntime::BgJobRuntime(AgentTaskScope(group))
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
    let rt = BgJobRuntime::BgJobRuntime(
      AgentTaskScope(group),
      hard_output_cap=200,
      on_job_exit=snapshot => notices.push(snapshot),
    )
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
    let rt = BgJobRuntime::BgJobRuntime(
      AgentTaskScope(group),
      hard_timeout_ms=80,
      on_job_exit=snapshot => notices.push(snapshot),
    )
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
    let rt = BgJobRuntime::BgJobRuntime(
      AgentTaskScope(group),
      hard_timeout_ms=150,
    )
    // The execution starts OUTSIDE the registry (a foreground command) and
    // burns most of its lifetime before being adopted on detach.
    let exec = rt.spawn_foreground_retained("sh", ["-c", "sleep 5"], None, 200)
    @async.sleep(120)
    let _ = exec.background()
    let id = rt.adopt(exec, command="sleep 5")
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
    let rt = BgJobRuntime::BgJobRuntime(
      AgentTaskScope(group),
      hard_timeout_ms=60_000,
    )
    let id = rt.start(program="sh", args=["-c", "sleep 5"], command="sleep 5")
    let _ = rt.stop(id)
    guard rt.snapshot(id) is Some(snapshot) else { fail("expected snapshot") }
    assert_false(snapshot.killed_by_time_limit)
    assert_false(snapshot.killed_by_output_limit)
  })
}

///|
pub extend BgJobStatus with Eq::{equal, not_equal}
