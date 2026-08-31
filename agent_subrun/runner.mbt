///|
/// After the wall deadline closes the child's stdin (the graceful-cancel
/// signal), the child gets this long to flush and exit before the runner
/// terminates it. A well-behaved child cancels its turn on EOF and exits
/// quickly; the kill is the backstop.
let cancel_grace_ms : Int = 5_000

///|
/// How a sub-run ended. External cancellation of the CALLER is deliberately
/// not a terminal: it re-raises out of `run_subrun` (tearing the child down
/// on the way) so structured concurrency sees it, per the engine-wide rule
/// that cancellation is never folded into an ordinary failure.
pub enum SubrunTerminal {
  /// The child submitted a valid report before exiting.
  Captured
  /// The child exited cleanly without ever submitting a report.
  NoReport
  /// The child exhausted its step budget without a report.
  MaxSteps
  /// The child yielded at its context ceiling without a report.
  ContextYield
  /// The runner's wall deadline expired: stdin was closed (graceful cancel)
  /// and the child was terminated after the grace period. A report that
  /// arrived before the cut still reports `Captured`.
  TimedOut
  /// The child failed: spawn failure, a turn/setup failure it reported, a
  /// garbled report, or an exit with none of the above observed.
  Failed(String)
} derive(Debug, Eq)

///|
/// The outcome of one sub-run: the parsed report when there is one, plus the
/// cost the child actually spent — observed from the child's own event
/// stream (`usage` summed, `agent_step` maxed), so it is exact for the
/// requests the child made.
struct SubrunResult[T] {
  value : T?
  terminal : SubrunTerminal
  steps_used : Int
  prompt_tokens : Int
  completion_tokens : Int
  subrun_id : String
} derive(Debug)

///|
/// The parsed report, when the child submitted one.
pub fn[T] SubrunResult::value(self : SubrunResult[T]) -> T? {
  self.value
}

///|
/// How the sub-run ended.
pub fn[T] SubrunResult::terminal(self : SubrunResult[T]) -> SubrunTerminal {
  self.terminal
}

///|
/// Model requests the child actually made.
pub fn[T] SubrunResult::steps_used(self : SubrunResult[T]) -> Int {
  self.steps_used
}

///|
/// The runner-assigned sub-run id ("sr-N"): the same id the
/// SubrunStarted/SubrunFinished brackets carried, and — when the child was
/// launched with a `ChildSession` — the suffix of the child's durable
/// session id.
pub fn[T] SubrunResult::subrun_id(self : SubrunResult[T]) -> String {
  self.subrun_id
}

///|
/// What the runner accumulates while draining the child's stdout.
priv struct ChildObservations {
  mut steps : Int
  mut prompt_tokens : Int
  mut completion_tokens : Int
  mut max_steps_exhausted : Bool
  mut context_yield : Bool
  mut failure : String?
  mut report : Json?
  mut garbled_report : String?
}

///|
/// Classify one child stdout line. The child's stdout carries its xlog JSONL
/// event stream (each line an envelope whose event fields are hoisted to the
/// top level — `@protocol.parse` reads exactly that shape) and, last, the
/// distinguished `{"subrun_report": ...}` line. Non-JSON lines are skipped:
/// a tool subprocess that leaks to stdout must not poison the run.
fn ChildObservations::observe(self : ChildObservations, line : String) -> Unit {
  let trimmed = line.trim(chars="\r\n")
  if trimmed == "" {
    return
  }
  guard (Some(@json.parse(trimmed.to_owned())) catch { _ => None })
    is Some(json) else {
    return
  }
  if parse_report_line(json) is Some(report) {
    self.report = Some(report)
    return
  }
  match @protocol.parse(json) {
    Some(AgentStep(step~)) => self.steps = self.steps.max(step)
    Some(Usage(usage~)) => {
      self.prompt_tokens += usage.prompt_tokens
      self.completion_tokens += usage.completion_tokens
    }
    Some(MaxStepsExhausted) => self.max_steps_exhausted = true
    Some(ContextYield(..)) => self.context_yield = true
    Some(TurnFailed(error~))
    | Some(AgentSetupFailed(error~))
    | Some(CommandError(error~)) => self.failure = Some(error)
    Some(AgentAborted(reason~)) => self.failure = Some(reason)
    _ => ()
  }
}

///|
/// Run one sub-run in a DEDICATED CHILD PROCESS and report what happened and
/// what it cost.
///
/// `command`/`args` name the child — in production the parent's own
/// executable with `["subrun", <kind>, ...]` (same binary, so the report's
/// derived JSON codecs cannot drift), in tests any script that speaks the
/// contract. The runner writes `input` as one JSON line on the child's
/// stdin and HOLDS THE PIPE OPEN: closing it is the graceful-cancel signal.
/// It drains the child's stdout, summing `usage` and `agent_step` events
/// for cost and capturing the final `{"subrun_report": ...}` line, which
/// `parse_report` turns into the typed value (rejects become `Failed`).
///
/// Deadline: after `wall_deadline_ms` the runner closes stdin and gives the
/// child `cancel_grace_ms` to flush and exit — a report that lands during
/// the grace still counts — then terminates it. External cancellation of
/// the caller re-raises after teardown; it is never folded into a terminal.
///
/// Lifecycle brackets: the runner emits `SubrunStarted{id, kind, label}`
/// before anything else and a PAIRED `SubrunFinished{id, status, costs}` on
/// every exit — success, failure, and cancellation (emitted before the
/// re-raise) — so a reader never shows a sub-run as running forever. Both
/// land during the parent's tool call, well before the parent turn's own
/// terminal event, which the TUI's stale-run guard requires. `label` is
/// display-bounded here defensively; `emit_event` is a test seam that
/// defaults to the process log.
pub async fn[T] run_subrun(
  command~ : String,
  args~ : Array[String],
  input~ : Json,
  parse_report~ : (Json) -> Result[T, String],
  wall_deadline_ms~ : Int,
  kind~ : String,
  label~ : String,
  cwd? : String,
  child_session? : ChildSession,
  emit_event? : (@protocol.Event) -> Unit = event => @emit.emit(event),
) -> SubrunResult[T] {
  // Bump the process counter past any child ordinal an earlier engine
  // process already persisted for this parent — monotonic, so it can only
  // skip ids, never reuse one.
  if child_session is Some(spec) && subrun_ids.val < spec.first_free - 1 {
    subrun_ids.val = spec.first_free - 1
  }
  let id = next_subrun_id()
  // The child persists its own transcript under `<parent>-<id>` when the
  // parent is durable: the id exists only after allocation, so the session
  // argv is the runner's to append, not the caller's.
  let args = match child_session {
    Some(spec) =>
      [..args, "--session", "\{spec.parent}-\{id}", "--session-root", spec.root]
    None => args
  }
  emit_event(
    SubrunStarted(id~, kind~, label=@agent_tool.brief_line(label, limit=72)),
  )
  fn finished(status : String, observations : ChildObservations) -> Unit {
    emit_event(
      SubrunFinished(
        id~,
        status~,
        steps=observations.steps,
        prompt_tokens=observations.prompt_tokens,
        completion_tokens=observations.completion_tokens,
      ),
    )
  }
  let observations = ChildObservations::{
    steps: 0,
    prompt_tokens: 0,
    completion_tokens: 0,
    max_steps_exhausted: false,
    context_yield: false,
    failure: None,
    report: None,
    garbled_report: None,
  }
  let mut timed_out = false
  // The group call is itself fold-guarded: a spawn failure can surface
  // ASYNCHRONOUSLY (the spawn's internal reaper task raising at group
  // exit, e.g. EAGAIN under fork pressure), bypassing the per-call
  // catches inside. Cancellation still re-raises; anything else becomes
  // a Failed terminal — a loaded machine must degrade the sub-run, never
  // crash the parent's turn.
  try
    @async.with_task_group() <| group => {
      let (child_stdin, stdin_writer) = @process.write_to_process() catch {
        error if @async.is_being_cancelled() => raise error
        error => {
          observations.failure = Some("subrun pipes unavailable: \{error}")
          return
        }
      }
      let (stdout_reader, child_stdout) = @process.read_from_process() catch {
        error if @async.is_being_cancelled() => {
          stdin_writer.close()
          raise error
        }
        error => {
          stdin_writer.close()
          observations.failure = Some("subrun pipes unavailable: \{error}")
          return
        }
      }
      // `no_wait`: the group terminates the child at teardown rather than
      // waiting for an exit that may only come once its stdin is closed.
      let process = @process.spawn(
        group,
        command,
        args,
        inherit_env=true,
        stdin=child_stdin,
        stdout=child_stdout,
        cwd?=cwd.map(dir => dir.view()),
        no_wait=true,
      ) catch {
        error if @async.is_being_cancelled() => {
          stdout_reader.close()
          stdin_writer.close()
          raise error
        }
        error => {
          stdout_reader.close()
          stdin_writer.close()
          observations.failure = Some("subrun spawn failed: \{error}")
          return
        }
      }
      async fn drain() -> Unit {
        while stdout_reader.read_until("\n") is Some(line) {
          observations.observe(line)
        }
      }
      async fn feed_and_drain() -> Unit {
        // One input line; the pipe stays open — EOF is the cancel signal, not
        // the end of input. The write sits INSIDE the deadline scope: an input
        // larger than the pipe capacity against a child that never reads must
        // hit the wall deadline, not block forever (review finding).
        stdin_writer.write("\{input.stringify()}\n")
        drain()
      }
      try {
        match @async.with_timeout_opt(wall_deadline_ms, feed_and_drain) {
          Some(_) =>
            // Clean EOF: the child closed stdout. Read its exit status — a
            // crash-class failure (panic, signal, nonzero exit) emits no
            // failure event, and without this the runner is structurally
            // blind to it and would misclassify the run as NoReport. Bounded:
            // a child that closed stdout but lingers falls through to the
            // cancel below.
            match @async.with_timeout_opt(2_000, () => process.wait()) {
              Some(code) if code != 0 &&
                observations.report is None &&
                observations.failure is None =>
                observations.failure = Some("subrun exited \{code}")
              _ => ()
            }
          None => {
            // Deadline: graceful cancel first — close stdin, let the child
            // flush; a report arriving in the grace window still counts.
            timed_out = true
            stdin_writer.close()
            let _ = @async.with_timeout_opt(cancel_grace_ms, drain)
          }
        }
      } catch {
        error => {
          // External cancellation (or a pipe failure): tear the child down and
          // re-raise cancellation; fold anything else into the terminal.
          @async.protect_from_cancel(() => {
            stdout_reader.close()
            stdin_writer.close()
            process.cancel()
          })
          if @async.is_being_cancelled() {
            raise error
          }
          if observations.failure is None {
            observations.failure = Some("subrun stream failed: \{error}")
          }
          return
        }
      }
      stdout_reader.close()
      stdin_writer.close()
      process.cancel()
    }
  catch {
    error if @async.is_being_cancelled() || @async.is_cancellation_error(error) => {
      // The balanced finish bracket on the cancellation path: emitted
      // BEFORE the re-raise, with whatever costs were observed.
      finished("cancelled", observations)
      raise error
    }
    error =>
      if observations.failure is None {
        observations.failure = Some("subrun runner failed: \{error}")
      }
  }
  let value : T? = match observations.report {
    Some(report) =>
      match parse_report(report) {
        Ok(value) => Some(value)
        Err(problem) => {
          observations.garbled_report = Some(problem)
          None
        }
      }
    None => None
  }
  let terminal = match (value, observations.garbled_report) {
    (Some(_), _) => Captured
    (None, Some(problem)) => Failed("subrun report rejected: \{problem}")
    (None, None) =>
      match observations.failure {
        Some(error) => Failed(error)
        None if timed_out => TimedOut
        None if observations.max_steps_exhausted => MaxSteps
        None if observations.context_yield => ContextYield
        None => NoReport
      }
  }
  finished(status_of(terminal), observations)
  {
    value,
    terminal,
    steps_used: observations.steps,
    prompt_tokens: observations.prompt_tokens,
    completion_tokens: observations.completion_tokens,
    subrun_id: id,
  }
}

///|
/// Where a child persists its own transcript: the parent's session root
/// plus the parent's session id. The runner derives the child's session id
/// as `<parent>-<subrun id>` — a sibling of the parent's session in the
/// same root, so session tooling (the viewer, `openseek sessions`)
/// discovers child transcripts with no extra plumbing.
///
/// `first_free` is the lowest child ordinal no earlier engine process has
/// persisted for this parent (the CLI scans the store at startup). The
/// sub-run counter is per-process, so without this floor a RESUMED durable
/// session would reuse `sr-1` — and the fresh child session would die on
/// its first append against the old child's file (stale-snapshot check).
pub struct ChildSession {
  priv root : String
  parent : String
  priv first_free : Int
}

///|
/// See `ChildSession`.
pub fn ChildSession::ChildSession(
  root~ : String,
  parent~ : String,
  first_free? : Int = 1,
) -> ChildSession {
  { root, parent, first_free, }
}

///|
/// Per-process monotonic sub-run ids: unique within one engine's stream,
/// which is all the pairing contract needs.
let subrun_ids : Ref[Int] = { val: 0, }

///|
fn next_subrun_id() -> String {
  subrun_ids.val += 1
  "sr-\{subrun_ids.val}"
}

///|
/// The wire status vocabulary for a terminal (the "cancelled" status has no
/// terminal — cancellation re-raises — and is emitted at its catch site).
fn status_of(terminal : SubrunTerminal) -> String {
  match terminal {
    Captured => "captured"
    NoReport => "no_report"
    MaxSteps => "max_steps"
    ContextYield => "context_yield"
    TimedOut => "timed_out"
    Failed(_) => "failed"
  }
}

///|
pub extend SubrunResult with Debug::{to_repr}

///|
pub extend SubrunTerminal with Debug::{to_repr}

///|
pub extend SubrunTerminal with Eq::{equal, not_equal}
