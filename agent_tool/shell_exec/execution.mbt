///|
/// After the direct child exits, how long to let the reader keep draining the
/// pipe before force-closing it. In the normal case the reader hits EOF almost
/// immediately (the child closed its write end); this grace only elapses when a
/// descendant inherited and is holding the pipe open, in which case there is no
/// more of the job's own output to wait for.
let reader_drain_grace_ms : Int = 200

///|
/// Terminal or live state of one execution.
///
/// - `Running`: the child is executing and a tool call is awaiting it.
/// - `Backgrounded`: the child is still executing but detached — no call is
///   awaiting it (set by detach-on-timeout; the process keeps running).
/// - `Exited(code)`: the child exited on its own with `code`.
/// - `Killed`: the child was cancelled (`stop`, a reader error, or session
///   teardown) before a natural exit — no exit code is available.
pub(all) enum ExecStatus {
  Running
  Backgrounded
  Exited(Int)
  Killed
} derive(Eq, Debug)

///|
/// Whether a status is terminal (the child is gone).
pub fn ExecStatus::is_terminal(self : ExecStatus) -> Bool {
  match self {
    Exited(_) | Killed => true
    Running | Backgrounded => false
  }
}

///|
/// One shell command execution: a process spawned on the session group, its
/// merged stdout+stderr owned by a single `ShellOutputSink`, and a status flag.
/// This is the shared object behind both foreground `shell` and background jobs —
/// "foreground vs background" is only whether a tool call is currently awaiting
/// it, so detaching is a status flip (`background()`), not a re-route.
///
/// Cancellation reaches only the directly spawned process (like the foreground
/// `shell` tool and `moon_check`): the process library exposes no process-group
/// kill, so a command that daemonizes its own children can leave descendants
/// running after the execution is terminal.
pub struct ShellExecution {
  priv sink : ShellOutputSink
  priv process : @process.Process
  priv mut status : ExecStatus
  // Set before the child is cancelled (by `stop`, or by the output-limit kill)
  // so the monitor reports `Killed` rather than the kill signal's exit code.
  priv mut cancel_requested : Bool
  // Foreground semantics: kill the child once the sink fills (output prefix hit
  // the hard cap or the kill threshold), so an un-timed runaway cannot hang the
  // tool call. Cleared by `background()` — a detached job keeps running.
  priv mut kill_when_full : Bool
  // Background watchdog: kill the child once full output hits the *hard* cap —
  // past it every further byte is dropped, so the job is a runaway producing
  // nothing anyone can read. Unlike `kill_when_full` this survives
  // `background()`: a detached job keeps running but not unboundedly.
  priv kill_at_hard_cap : Bool
  // Set when the child was cancelled by an output-limit watchdog (either flag
  // above), so a consumer can tell a watchdog kill from a requested stop and
  // surface it rather than letting the job die silently.
  priv mut killed_by_output_limit : Bool
  // Monotonic start stamp, so a wall-clock reaper measures a job's lifetime
  // from process start — a detached (adopted) job keeps its original
  // deadline, not one restarted at adoption.
  priv started_at_ms : Int64
  // Set when the child was cancelled by the wall-clock reaper, so consumers
  // can tell a lifetime kill from a requested stop.
  priv mut killed_by_time_limit : Bool
}

///|
/// Spawn `program args` on the session group with stdout+stderr merged into a
/// fresh sink, start a monitor task, and return the live execution. `spill_path`,
/// when set, is where the sink writes full output once it exceeds `inline_cap`.
pub async fn[X] ShellExecution::start(
  scope : @agent_runtime.AgentTaskScope[X],
  program~ : String,
  args~ : Array[String],
  cwd? : String,
  inline_cap? : Int = default_inline_cap,
  hard_cap? : Int = default_hard_cap,
  spill_path? : String,
  kill_when_full? : Bool = false,
  kill_at_hard_cap? : Bool = false,
) -> ShellExecution {
  let group = scope.group()
  let sink = ShellOutputSink::new(inline_cap~, hard_cap~, spill_path?)
  let (reader, writer) = @process.read_from_process()
  let process = @process.spawn(
    group,
    program,
    args,
    stdout=writer,
    stderr=writer,
    cwd?=cwd.map(cwd => cwd.view()),
    cancel_handler=@process.hard_cancel(),
    no_wait=true,
  )
  let exec = {
    sink,
    process,
    status: Running,
    cancel_requested: false,
    kill_when_full,
    kill_at_hard_cap,
    killed_by_output_limit: false,
    started_at_ms: @env.now().reinterpret_as_int64(),
    killed_by_time_limit: false,
  }
  group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
    exec.monitor(reader, process)
  }
  exec
}

///|
/// Supervise the execution: drain merged output while, *independently*, awaiting
/// the direct child's exit. Coupling the two (read to EOF, then `wait`) would
/// hang forever when the child exits but a descendant holds the pipe open — so a
/// concurrent reader drains bytes and `process.wait()` is the authoritative exit
/// signal that then closes the reader to unblock it.
async fn ShellExecution::monitor(
  self : ShellExecution,
  reader : @process.ReadFromProcess,
  process : @process.Process,
) -> Unit {
  let reader_done : @async.Queue[Unit] = Queue(kind=Unbounded)
  @async.with_task_group(reads => {
    reads.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      defer ignore(reader_done.try_put(()) catch { _ => false })
      for ;; {
        match (reader.read_some(max_len=1024) catch { _ => None }) {
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
              self.cancel_requested = true
              self.process.cancel()
            }
          }
        }
      }
    }
    // The direct child's exit is authoritative, independent of the pipe. A
    // concurrent `stop` cancels the process, so `wait` may raise or return a
    // kill signal's code — every path lands on a terminal status.
    let terminal = try {
      let code = process.wait()
      if self.cancel_requested {
        Killed
      } else {
        Exited(code)
      }
    } catch {
      error => {
        if @async.is_being_cancelled() {
          reader.close()
          raise error
        }
        Killed
      }
    }
    // The child is gone, but the pipe may still hold output it wrote before
    // exiting. Let the reader drain to EOF; only if it is still blocked after a
    // short grace — a descendant is holding the pipe open — force it closed.
    match
      @async.with_timeout_opt(reader_drain_grace_ms, () => reader_done.get()) {
      Some(_) => ()
      None => reader.close()
    }
    // Surface leftover half-decoded bytes, then publish the terminal status — in
    // that order, so a poller can never observe a terminal execution missing the
    // job's final output.
    self.sink.finish()
    self.set_terminal(terminal)
  })
}

///|
/// Move to a terminal status, unless already terminal (a `stop` that raced the
/// natural exit must not clobber the recorded outcome).
fn ShellExecution::set_terminal(
  self : ShellExecution,
  status : ExecStatus,
) -> Unit {
  guard !self.status.is_terminal() else { return }
  self.status = status
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
  self.cancel_requested = true
  self.process.cancel()
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
/// Await terminal *or* the first invalid (binary / non-UTF-8) output, whichever
/// comes first — so a foreground command that emits binary bytes and then keeps
/// running fails immediately, matching the strict per-call path, instead of
/// blocking until exit.
pub async fn ShellExecution::wait_or_invalid(self : ShellExecution) -> Unit {
  for ;; {
    if self.status.is_terminal() || self.sink.had_invalid_utf8() {
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
pub fn ShellExecution::exit_code(self : ShellExecution) -> Int? {
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
  n : Int,
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
/// The spill file's path, if output spilled to disk.
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
/// Monotonic timestamp (ms) when the child was spawned.
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
  if self.status.is_terminal() {
    return
  }
  self.killed_by_time_limit = true
  self.cancel_requested = true
  self.process.cancel()
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
pub fn ShellExecution::size(self : ShellExecution) -> Int {
  self.sink.size()
}

///|
/// Output version, bumped whenever retained output grows.
pub fn ShellExecution::seq(self : ShellExecution) -> Int {
  self.sink.seq()
}
