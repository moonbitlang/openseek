///|
/// After the direct child exits, how long to wait for the next output chunk.
/// Storing a chunk does not consume this idle budget: slow spill-file writes
/// must not cause unread pipe data to be discarded.
let reader_drain_grace_ms : Int32 = 200

///|
/// Why an execution was first asked to stop.
pub enum StopCause {
  /// A caller asked (`stop`, `request_stop`).
  Requested
  /// The output watchdog.
  OutputLimit
  /// The wall-clock reaper.
  TimeLimit
  /// The output could not be captured, with the reason.
  CaptureFailed(String)
}

///|
/// Terminal or live state of one execution.
///
/// - `Running`: the child is executing and a tool call is awaiting it.
/// - `Backgrounded`: the child is still executing but detached — no call is
///   awaiting it (set by detach-on-timeout; the process keeps running).
/// - `Exited(code)`: the child exited on its own with `code`.
/// - `Killed`: the child was cancelled (`stop`, a reader error, or session
///   teardown) before a natural exit — no exit code is available.
pub enum ExecStatus {
  Running
  Backgrounded
  Exited(Int32)
  Killed
} derive(Eq, Debug)

///|
/// Whether a status is terminal (the child is gone).
fn ExecStatus::is_terminal(self : ExecStatus) -> Bool {
  match self {
    Exited(_) | Killed => true
    Running | Backgrounded => false
  }
}

///|
/// One command execution: a process spawned on the session group, its
/// merged stdout+stderr owned by a single `ShellOutputSink`, and a status flag.
/// This is the shared object behind foreground `mbtx` runs and background jobs —
/// "foreground vs background" is only whether a tool call is currently awaiting
/// it, so detaching is a status flip (`background()`), not a re-route.
///
/// Cancellation reaches only the directly spawned process:
/// the process library exposes no process-group
/// kill, so a command that daemonizes its own children can leave descendants
/// running after the execution is terminal.
struct ShellExecution {
  sink : ShellOutputSink
  process : @process.Process
  mut status : ExecStatus
  // Set before the child is cancelled (by `stop`, or by the output-limit kill)
  // so the monitor reports `Killed` rather than the kill signal's exit code.
  mut cancel_requested : Bool
  // Why the first stop was requested, recorded when it was: later trouble
  // during the wind-down (a capture error, say) does not replace it.
  mut stop_cause : StopCause?
  // Set once the child is seen to exit on its own: a stop requested after
  // that (while its output drains) did not end it.
  mut exited_on_its_own : Bool
  mut ending : Bool
  mut on_ending : (() -> Unit)?
  // Foreground semantics: kill the child once the sink fills (output prefix hit
  // the hard cap or the kill threshold), so an un-timed runaway cannot hang the
  // tool call. Cleared by `background()` — a detached job keeps running.
  mut kill_when_full : Bool
  // Background watchdog: kill the child once full output hits the *hard* cap —
  // past it every further byte is dropped, so the job is a runaway producing
  // nothing anyone can read. Unlike `kill_when_full` this survives
  // `background()`: a detached job keeps running but not unboundedly.
  kill_at_hard_cap : Bool
  // Set when the child was cancelled by an output-limit watchdog (either flag
  // above), so a consumer can tell a watchdog kill from a requested stop and
  // surface it rather than letting the job die silently.
  mut killed_by_output_limit : Bool
  // Epoch start stamp, so a wall-clock reaper measures a job's lifetime
  // from process start — a detached (adopted) job keeps its original
  // deadline, not one restarted at adoption.
  started_at_ms : Int64
  cwd : String?
  mut finished_at_ms : Int64?
  // Set when the child was cancelled by the wall-clock reaper, so consumers
  // can tell a lifetime kill from a requested stop.
  mut killed_by_time_limit : Bool
}

///|
/// Spawn `program args` on the session group with stdout+stderr merged into a
/// fresh sink, start a monitor task, and return the live execution. `spill_path`,
/// when set, is where the sink writes full output once it exceeds `inline_cap`.
///
/// `stdin` is the child's standard input. A child must never be left holding
/// the PARENT's fd 0 — under `openseek serve` that descriptor is the JSONL
/// command channel, and a child that reads stdin would consume the engine's own
/// commands. Omitting it therefore does not fall back to inheritance: the child
/// gets a pipe of its own whose write end is closed at once, so it reads EOF
/// immediately (on Windows too, where inheriting the engine's held-open pipe
/// hangs `git`). Pass a redirect when the program should actually read something.
///
/// `cancel_handler` is how the process is ended when the execution is stopped
/// or its group is cancelled; by default it is killed at once. A program that
/// winds down on its own signal (closing its stdin, say) passes a handler that
/// gives that signal and a grace before killing. With one, the execution's
/// output is drained until the process has exited even when the group is
/// being cancelled, so the handler must end the process.
pub async fn[X] ShellExecution::start(
  scope : @agent_runtime.AgentTaskScope[X],
  program~ : String,
  args~ : Array[String],
  cwd? : String,
  stdin? : &@process.ProcessInput,
  inline_cap~ : Int32 = default_inline_cap,
  hard_cap~ : Int32 = default_hard_cap,
  spill_path? : String,
  kill_when_full~ : Bool = false,
  kill_at_hard_cap~ : Bool = false,
  cancel_handler? : @process.CancellationHandler,
  extra_env? : Map[String, String],
) -> ShellExecution {
  let group = scope.group()
  let sink = ShellOutputSink::ShellOutputSink(
    inline_cap~,
    hard_cap~,
    spill_path?,
  )
  let (reader, writer) = @process.read_from_process()
  let child_stdin : &@process.ProcessInput = match stdin {
    Some(input) => input
    None => {
      let (stdin_reader, stdin_writer) = @process.write_to_process()
      stdin_writer.close()
      stdin_reader
    }
  }
  // The handler runs on every cancellation, a requested stop or the group's
  // teardown alike; teardown requests nothing, so it is recorded here, before
  // the handler's own effects, unless a cause is already known.
  let started : Ref[ShellExecution?] = Ref(None)
  let CancellationHandler(cancel) = cancel_handler.unwrap_or_else(() => {
    @process.hard_cancel()
  })
  let process = @process.spawn(
    group,
    program,
    args,
    stdin=child_stdin,
    stdout=writer,
    stderr=writer,
    cwd?=cwd.map(cwd => cwd.view()),
    extra_env?,
    cancel_handler=CancellationHandler(pid => {
      if started.val is Some(exec) {
        exec.note_stop()
      }
      cancel(pid)
    }),
    no_wait=true,
    no_console_window=true,
  )
  let exec = {
    sink,
    process,
    status: Running,
    cancel_requested: false,
    stop_cause: None,
    exited_on_its_own: false,
    ending: false,
    on_ending: None,
    kill_when_full,
    kill_at_hard_cap,
    killed_by_output_limit: false,
    started_at_ms: @env.now().reinterpret_as_int64(),
    cwd: match cwd {
      Some(_) => cwd
      None => @env.current_dir()
    },
    finished_at_ms: None,
    killed_by_time_limit: false,
  }
  started.val = Some(exec)
  group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
    // A process with its own cancel handler winds down over a grace when its
    // group is cancelled, and may write its last output then: keep draining
    // it until it has exited, or that write fails on a closed pipe. The
    // handler bounds the wait; the default handler kills at once.
    if cancel_handler is Some(_) {
      @async.protect_from_cancel(() => exec.monitor(reader, process))
    } else {
      exec.monitor(reader, process)
    }
  }
  exec
}

///|
/// Supervise the execution: drain merged output while, *independently*, awaiting
/// the direct child's exit. Coupling the two (read to EOF, then `wait`) would
/// hang forever when the child exits but a descendant holds the pipe open — so a
/// concurrent reader drains bytes and `process.wait()` is the authoritative exit
/// signal that starts an idle timeout on subsequent pipe reads. The reader is
/// closed only after its task has finished, including cancellation cleanup.
async fn ShellExecution::monitor(
  self : ShellExecution,
  reader : @process.ReadFromProcess,
  process : @process.Process,
) -> Unit {
  defer self.sink.close()
  defer reader.close()
  errdefer self.set_terminal(Killed)
  @async.with_task_group(reads => {
    // Revoke dependents before this group joins the output reader, including
    // when cancellation bypasses the process wait's error handler.
    errdefer self.begin_ending()
    let exited = reads.spawn(() => {
      // A concurrent stop may make wait raise or return a kill signal's code.
      let terminal = try {
        let code = process.wait()
        if self.cancel_requested {
          Killed
        } else {
          self.exited_on_its_own = true
          Exited(code)
        }
      } catch {
        _ => Killed
      }
      self.begin_ending()
      terminal
    })
    let output = reads.spawn(allow_failure=true) <| () => {
      errdefer self.request_stop()
      for ;; {
        match
          (@async.any([
            () => reader.read_some(max_len=1024),
            () => {
              ignore(exited.wait())
              @async.sleep(reader_drain_grace_ms)
              None
            },
          ]) catch {
            error => {
              let message = "failed to read process output: \{error}"
              self.sink.failure = Some(message)
              fail(message)
            }
          }) {
          None => break
          Some(bytes) => {
            self.sink.append_chunk(bytes)
            // Output-limit watchdogs, two thresholds:
            // - Foreground (`kill_when_full`): stop the child as soon as output
            //   exceeds the inline cap (max_output_chars) — promptly, not only at
            //   a larger hard cap — so a chatty command is an immediate
            //   output-limit error rather than running to the timeout.
            //   `background()` clears this flag, so a job detached while still
            //   under the limit keeps growing afterward. `over_inline_cap` fires
            //   for a retained execution (inline < hard); `truncated` covers a
            //   memory-only one (inline == hard).
            // - Background (`kill_at_hard_cap`): stop the child once full output
            //   hits the hard cap — past it every byte is dropped, so a flooding
            //   job would burn CPU producing nothing readable. Survives detach.
            let over_foreground_limit = self.kill_when_full &&
              (self.sink.over_inline_cap() || self.sink.truncated())
            let over_hard_cap = self.kill_at_hard_cap && self.sink.truncated()
            if (over_foreground_limit || over_hard_cap) &&
              !self.cancel_requested {
              self.killed_by_output_limit = true
              self.request_stop()
            }
            // A descendant may keep writing after the direct child exits.
            // Explicit stop and output caps must still end that drain even
            // when the pipe never becomes idle. Before that exit, keep
            // reading: a cancel handler may let the child write its last
            // output while it winds down.
            if exited.try_wait() is Some(_) &&
              (self.cancel_requested || self.sink.truncated()) {
              break
            }
          }
        }
      }
    }
    let terminal = exited.wait()
    // Join the reader before flushing or publishing a terminal snapshot. The
    // per-read race cancels and joins a pending read on idle timeout; it never
    // closes a descriptor while another task is reading or storing its data.
    let output_ok = try {
      output.wait()
      true
    } catch {
      _ => false
    }
    // Surface leftover half-decoded bytes, then publish the terminal status — in
    // that order, so a poller can never observe a terminal execution missing the
    // job's final output.
    self.sink.finish() catch {
      error => {
        let message = "failed to finish output log: \{error}"
        self.sink.failure = Some(message)
        fail(message)
      }
    }
    self.set_terminal(
      if !output_ok || self.sink.failure is Some(_) {
        Killed
      } else {
        terminal
      },
    )
  })
}

///|
/// Move to a terminal status, unless already terminal (a `stop` that raced the
/// natural exit must not clobber the recorded outcome).
fn ShellExecution::set_terminal(
  self : ShellExecution,
  status : ExecStatus,
) -> Unit {
  self.begin_ending()
  guard !self.status.is_terminal() else { return }
  self.status = status
  self.finished_at_ms = Some(@env.now().reinterpret_as_int64())
}

///|
/// Stop the execution: cancel the child and return once it lands terminal.
/// Idempotent and safe under concurrent callers — each observes the status
/// transition rather than a one-shot signal. Returns `false` for an
/// already-terminal execution.
pub async fn ShellExecution::stop(self : ShellExecution) -> Bool {
  guard !self.status.is_terminal() else { return false }
  self.request_stop()
  self.wait()
  true
}

///|
/// Synchronously request cancellation of the child (mark it and fire the process
/// cancel) without awaiting the terminal transition. `Process::cancel` is sync,
/// so this is safe to call while a turn is being cancelled — where awaiting is
/// not — to stop a session-group execution before it can outlive the turn as an
/// orphan. The monitor (on the session group) then reaps it to `Killed`.
pub fn ShellExecution::request_stop(self : ShellExecution) -> Unit {
  self.begin_ending()
  self.note_stop()
  self.cancel_requested = true
  self.process.cancel()
}

///|
/// Record why the execution is being stopped, if this is the first time and
/// the child has not already exited on its own. Each watchdog marks its
/// reason before it asks, so the first request knows why it was made.
fn ShellExecution::note_stop(self : ShellExecution) -> Unit {
  guard self.stop_cause is None && !self.exited_on_its_own else { return }
  self.stop_cause = Some(
    if self.sink.failure is Some(reason) {
      CaptureFailed(reason)
    } else if self.killed_by_output_limit {
      OutputLimit
    } else if self.killed_by_time_limit {
      TimeLimit
    } else {
      Requested
    },
  )
}

///|
/// Why the execution was first asked to stop; `None` if it never was.
pub fn ShellExecution::stop_cause(self : ShellExecution) -> StopCause? {
  self.stop_cause
}

///|
/// Await the execution reaching a terminal status.
pub async fn ShellExecution::wait(self : ShellExecution) -> Unit {
  for ;; {
    if self.status.is_terminal() {
      return
    }
    @async.sleep(5)
  }
}

///|
/// Detach the execution: flip `Running → Backgrounded` so no call is awaiting it
/// while the process keeps running, and clear the foreground output-limit kill —
/// a detached job may keep producing output. The hard-cap watchdog
/// (`kill_at_hard_cap`) is deliberately NOT cleared: detached means unbounded in
/// time, not unbounded in output. No-op (`false`) once terminal or already
/// backgrounded.
pub fn ShellExecution::background(self : ShellExecution) -> Bool {
  guard self.status is Running else { return false }
  self.status = Backgrounded
  self.kill_when_full = false
  true
}

///|
/// The current live or terminal status.
pub fn ShellExecution::status(self : ShellExecution) -> ExecStatus {
  self.status
}

///|
/// The child's exit code, if it exited on its own.
pub fn ShellExecution::exit_code(self : ShellExecution) -> Int32? {
  match self.status {
    Exited(code) => Some(code)
    _ => None
  }
}

///|
/// The in-memory head — the first `inline_cap` characters, the full output when
/// it fits inline, otherwise a preview. Synchronous.
pub fn ShellExecution::head(self : ShellExecution) -> String {
  self.sink.head()
}

///|
/// The full retained output (reads the spill file when output spilled).
pub async fn ShellExecution::read_all(self : ShellExecution) -> String {
  self.sink.read_all()
}

///|
/// The last `n` characters of output — a bounded window onto recent output.
pub async fn ShellExecution::read_tail(
  self : ShellExecution,
  n : Int32,
) -> String {
  self.sink.read_tail(n)
}

///|
/// Whether output exceeded the inline cap (render a pointer; full output is in
/// the spill file).
pub fn ShellExecution::over_inline_cap(self : ShellExecution) -> Bool {
  self.sink.over_inline_cap()
}

///|
/// Where full output is retained on disk, or `None` for a memory-only
/// execution (one started without a `spill_path` — tests, and any runtime
/// whose session temp dir could not be created).
///
/// Public so a caller can scan the COMPLETE output without materializing it:
/// `read_all` pulls up to `hard_cap` (20MB) into memory, while a path lets the
/// caller stream its own bounded window — which is how a sandbox source-write
/// denial is found when it lands past the rendered head.
pub fn ShellExecution::spill_path(self : ShellExecution) -> String? {
  self.sink.spill_path()
}

///|
/// Whether full output was dropped at the hard cap.
pub fn ShellExecution::output_truncated(self : ShellExecution) -> Bool {
  self.sink.truncated()
}

///|
/// Whether any invalid (non-UTF-8 / binary) output was seen.
pub fn ShellExecution::had_invalid_utf8(self : ShellExecution) -> Bool {
  self.sink.had_invalid_utf8()
}

///|
/// Whether the child was cancelled by an output-limit watchdog (rather than a
/// requested stop) — so a consumer can surface the kill instead of letting a
/// runaway job die silently.
pub fn ShellExecution::killed_by_output_limit(self : ShellExecution) -> Bool {
  self.killed_by_output_limit
}

///|
/// Epoch timestamp (ms) when the child was spawned.
pub fn ShellExecution::started_at_ms(self : ShellExecution) -> Int64 {
  self.started_at_ms
}

///|
/// Whether the wall-clock reaper cancelled this execution.
pub fn ShellExecution::killed_by_time_limit(self : ShellExecution) -> Bool {
  self.killed_by_time_limit
}

///|
/// Cancel a still-live execution because its wall-clock lifetime expired.
/// Mirrors the output-limit trip: mark the reason before cancelling so the
/// monitor reports `Killed` and consumers can name the reaper rather than
/// reading it as a requested stop. No-op once terminal.
pub fn ShellExecution::kill_for_time_limit(self : ShellExecution) -> Unit {
  guard !self.status.is_terminal() else { return }
  self.killed_by_time_limit = true
  self.request_stop()
}

///|
/// Delete the spill file — for a retained execution that finished in the
/// foreground and is not adopted as a background job, so its temp file does not
/// leak. The in-memory head remains readable.
pub async fn ShellExecution::discard(self : ShellExecution) -> Unit {
  self.sink.discard()
}

///|
/// Full-output length in characters.
pub fn ShellExecution::size(self : ShellExecution) -> Int32 {
  self.sink.size()
}

///|
/// Output version, bumped whenever retained output grows.
pub fn ShellExecution::seq(self : ShellExecution) -> Int32 {
  self.sink.seq()
}

///|
#cfg(not(platform="windows"))
async test "stop and request_stop terminate a running execution" {
  @async.with_task_group(group => {
    let exec = ShellExecution::start(AgentTaskScope(group), program="sleep", args=[
      "30",
    ])
    @async.sleep(50)
    assert_true(exec.status() is Running)
    assert_true(exec.stop())
    assert_true(exec.status() is Killed)
    assert_false(exec.stop())
  })
}

///|
#cfg(not(platform="windows"))
async test "background flips to Backgrounded and keeps running" {
  @async.with_task_group(group => {
    let exec = ShellExecution::start(AgentTaskScope(group), program="sleep", args=[
      "30",
    ])
    @async.sleep(50)
    assert_true(exec.background())
    assert_true(exec.status() is Backgrounded)
    assert_true(exec.stop())
    assert_true(exec.status() is Killed)
  })
}

///|
/// Windows twin of the stdin regression: `ShellExecution::start` must hand the
/// child its own immediately-closed stdin pipe, so the child sees EOF at once
/// instead of inheriting the engine's host-held stdin pipe (which hangs git).
#cfg(platform="windows")
async test "execution child sees an immediately-closed stdin pipe on Windows" {
  @async.with_task_group(group => {
    let exec = ShellExecution::start(
      AgentTaskScope(group),
      program="powershell.exe",
      args=[
        "-NoProfile", "-NonInteractive", "-Command", "if ([Console]::IsInputRedirected) { [Console]::In.ReadToEnd().Length } else { 'NOT-REDIRECTED' }",
      ],
    )
    let outcome = @async.with_timeout_opt(15000, () => {
      while !exec.status().is_terminal() {
        @async.sleep(25)
      }
    })
    assert_true(
      outcome is Some(_),
      msg="execution did not reach a terminal state in time",
    )
    assert_true(exec.status() is Exited(0))
    assert_true(exec.head().contains("0"))
    assert_false(exec.head().contains("NOT-REDIRECTED"))
  })
}

///|
#doc(hidden)
#deprecated
pub extend ExecStatus with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend ExecStatus with Eq::{equal, not_equal}

///|
/// Ensure a configured output file exists before announcing background adoption.
/// Existing spill files are reused, including terminal executions adopted in a race.
pub async fn ShellExecution::materialize_output(self : ShellExecution) -> Unit {
  self.sink.materialize()
  if self.status.is_terminal() {
    self.sink.close()
  }
}

///|
/// A capture/write failure, distinct from a program's exit status.
pub fn ShellExecution::output_error(self : ShellExecution) -> String? {
  self.sink.failure
}

///|
/// The effective working directory, when available.
pub fn ShellExecution::cwd(self : ShellExecution) -> String? {
  self.cwd
}

///|
/// Epoch milliseconds when the direct execution became terminal.
pub fn ShellExecution::finished_at_ms(self : ShellExecution) -> Int64? {
  self.finished_at_ms
}

///|
/// Epoch milliseconds of the last captured output, if any.
pub fn ShellExecution::last_output_at_ms(self : ShellExecution) -> Int64? {
  self.sink.last_output_at_ms
}

///|
/// The number of committed UTF-8 output bytes.
pub fn ShellExecution::output_bytes(self : ShellExecution) -> Int64 {
  if self.sink.file_created {
    self.sink.file_bytes
  } else {
    @utf8.encode(self.head()).length().to_int64()
  }
}

///|
/// Observe stop initiation or the direct child's exit, before output draining.
/// Registration is synchronous; a late observer is called immediately. The
/// callback must only revoke resources, never wait for their cleanup.
pub fn ShellExecution::on_ending(
  self : ShellExecution,
  callback : () -> Unit,
) -> Unit {
  if self.ending {
    callback()
  } else {
    self.on_ending = Some(callback)
  }
}

///|
fn ShellExecution::begin_ending(self : ShellExecution) -> Unit {
  self.ending = true
  if self.on_ending is Some(callback) {
    self.on_ending = None
    callback()
  }
}
