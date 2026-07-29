///|
/// A failure in the benchmark controller itself, distinct from a model or
/// grader verdict.
priv suberror DriverError {
  InvalidEngineLine(String)
  GoalNotAcknowledged
} derive(Debug)

///|
/// The accumulated engine-side outcome before the restored tests are graded.
priv struct EngineOutcome {
  stop : TrialStop
  exit_code : Int
  elapsed_ms : Int64
  steps : Int
  turns : Int
  prompt_tokens : Int
  completion_tokens : Int
  total_tokens : Int
  transport_retries : Int
  engine_restarts : Int
}

///|
/// Result of one serve-process attempt. The enclosing trial may start another
/// process against the same session after an unexpected stream end.
priv struct EngineAttempt {
  stop : TrialStop
  exit_code : Int
}

///|
/// A live `openseek serve` JSONL connection and its state machine.
priv struct TrialController {
  stdin : @process.WriteToProcess
  stdout : @process.ReadFromProcess
  raw_log : @fs.File
  state : GoalTrialState
}

///|
/// Own the parent ends of a serve process's pipes and the raw stdout log.
fn TrialController::TrialController(
  stdin~ : @process.WriteToProcess,
  stdout~ : @process.ReadFromProcess,
  raw_log~ : @fs.File,
  state~ : GoalTrialState,
) -> TrialController {
  { stdin, stdout, raw_log, state }
}

///|
/// Send one typed serve command.
async fn TrialController::send(
  self : TrialController,
  command : @protocol.Command,
) -> Unit {
  self.stdin.write(command.to_jsonl())
}

///|
/// Read, persist, and decode the next known OpenSeek event. Unknown JSON
/// events are retained in the log and skipped for forward compatibility.
async fn TrialController::next_event(
  self : TrialController,
) -> @protocol.Event? {
  for ;; {
    guard self.stdout.read_until("\n") is Some(line) else { return None }
    self.raw_log.write(line)
    if !line.has_suffix("\n") {
      self.raw_log.write("\n")
    }
    let json = @json.parse(line) catch {
      _ => raise DriverError::InvalidEngineLine(line)
    }
    if @protocol.parse(json) is Some(event) {
      return Some(event)
    }
  }
}

///|
/// Set and confirm the durable auto goal before any task prompt is submitted.
async fn TrialController::set_goal(
  self : TrialController,
  goal_text : String,
) -> TrialStop? {
  self.state.expect_goal_acknowledgement()
  self.send(GoalSet(text=goal_text, auto=true))
  while !self.state.acknowledged() {
    guard self.next_event() is Some(event) else { return Some(StreamEnded) }
    if self.state.observe(event) is Some(stop) {
      return Some(stop)
    }
  }
  None
}

///|
/// Submit the full task prompt, then observe automatic continuation until the
/// state machine reaches a goal terminal or the engine stream ends.
async fn TrialController::run(
  self : TrialController,
  goal_text~ : String,
  task_prompt~ : String,
) -> TrialStop {
  if self.set_goal(goal_text) is Some(stop) {
    return stop
  }
  guard self.state.acknowledged() else {
    raise DriverError::GoalNotAcknowledged
  }
  self.send(Prompt(text=task_prompt))
  self.observe_goal()
}

///|
/// Reconnect a replacement serve process to the durable session and continue
/// without repeating TASK.md. The workspace and conversation transcript are
/// already preserved by the session.
async fn TrialController::reconnect_goal(
  self : TrialController,
  goal_text~ : String,
) -> TrialStop {
  if self.set_goal(goal_text) is Some(stop) {
    return stop
  }
  guard self.state.acknowledged() else {
    raise DriverError::GoalNotAcknowledged
  }
  self.send(
    Prompt(
      text="The OpenSeek serve process restarted. Continue working toward the standing goal from the current session and workspace state.",
    ),
  )
  self.observe_goal()
}

///|
/// Observe automatic continuation until the goal reaches a terminal state or
/// the serve stdout stream ends.
async fn TrialController::observe_goal(self : TrialController) -> TrialStop {
  for ;; {
    guard self.next_event() is Some(event) else { return StreamEnded }
    if self.state.observe(event) is Some(stop) {
      if stop.is_recoverable_transport_failure() &&
        self.state.consecutive_transport_failures() < 10 {
        self.retry_transport()
      } else {
        return stop
      }
    }
  }
}

///|
/// Wait outside the short outage window before resubmitting a neutral prompt
/// in the same durable serve session. The enclosing trial deadline still
/// bounds every retry, so ten interruptions cannot extend the benchmark.
async fn TrialController::retry_transport(self : TrialController) -> Unit {
  self.state.record_transport_retry()
  @async.sleep(self.state.transport_retry_delay_ms())
  self.send(
    Prompt(
      text="The model response transport closed before the turn finished. Continue working toward the standing goal from the current workspace state.",
    ),
  )
}

///|
/// Drain remaining stdout after closing stdin so `serve` can finish its
/// shutdown without filling a pipe.
async fn TrialController::drain(self : TrialController) -> Unit {
  while self.stdout.read_until("\n") is Some(line) {
    self.raw_log.write(line)
    if !line.has_suffix("\n") {
      self.raw_log.write("\n")
    }
  }
}

///|
/// Close the parent-side process pipes. The raw log is owned by `EngineTrial`
/// because it remains open across serve-process restarts.
fn TrialController::close(self : TrialController) -> Unit {
  self.stdin.close()
  self.stdout.close()
}

///|
/// Everything needed to launch one isolated goal-driven engine process.
priv struct EngineTrial {
  repo_root : String
  engine : String
  model : String
  max_steps : Int?
  timeout_ms : Int
  workspace : String
  session_root : String
  session_id : String
  goal_text : String
  task_prompt : String
  raw_log : String
  stderr_log : String
}

///|
/// Read the durable session, rather than relying on stdout progress, to decide
/// whether a replacement serve process needs the initial TASK.md again.
///
/// `run_turn_in_scope` appends the user message before setup or the first
/// `AgentStep`, so a process may die after this append without emitting any
/// progress event. The typed store load is the authority here: finding the
/// exact user event proves the prompt made it into the append-only transcript.
async fn EngineTrial::task_prompt_is_durable(self : EngineTrial) -> Bool {
  let store = @store.SessionStore(self.session_root)
  let session_id = @agent_session.SessionId(self.session_id)
  if !store.exists(session_id) {
    return false
  }
  let session = store.load(session_id)
  for event in session.events() {
    if event.item() is User(message) && message.content() == self.task_prompt {
      return true
    }
  }
  false
}

///|
/// Remaining agent-work time against the one absolute trial start. Process
/// launch and restart preparation consume this budget; bounded cleanup after a
/// controller verdict does not change that verdict.
fn EngineTrial::remaining_work_ms(
  self : EngineTrial,
  started_ms : Int64,
) -> Int {
  self.timeout_ms - (@env.now().reinterpret_as_int64() - started_ms).to_int()
}

///|
/// Run one serve process within the remaining absolute agent-work budget.
/// Cleanup has short independent bounds so a dead child cannot hold the
/// benchmark indefinitely after that budget ends.
async fn[X] EngineTrial::execute_attempt(
  self : EngineTrial,
  group : @async.TaskGroup[X],
  raw_log : @fs.File,
  state : GoalTrialState,
  first_process : Bool,
  submit_task_prompt : Bool,
  started_ms : Int64,
) -> EngineAttempt {
  let (child_stdin, stdin_writer) = @process.write_to_process()
  let (stdout_reader, child_stdout) = @process.read_from_process()
  let stderr_output = @process.redirect_to_file(
    self.stderr_log,
    append=!first_process,
    create_mode=if first_process { CreateOrTruncate } else { OpenOrCreate },
  )
  let controller = TrialController(
    stdin=stdin_writer,
    stdout=stdout_reader,
    raw_log~,
    state~,
  )
  defer controller.close()
  let (program, args) = if self.engine == "" {
    (
      "moon",
      [
        "run",
        "--target",
        "native",
        "\{self.repo_root}/cmd/openseek",
        "--",
        "serve",
      ],
    )
  } else {
    (@fs.realpath(self.engine), ["serve"])
  }
  args.append(["--model", self.model, "--goal-auto-turns", "0"])
  if self.max_steps is Some(max_steps) {
    args.append(["--max-steps", max_steps.to_string()])
  }
  args.append(["--dir", self.workspace, "--session", self.session_id])
  let (program, args) = ProcessGroupCommand(program~, args~).wrapped()
  let process = @process.spawn(
    group,
    program,
    args,
    inherit_env=true,
    extra_env={
      "OPENSEEK_GLOBAL_SKILLS_DIR": "\{self.workspace}/.no-global-skills",
      "OPENSEEK_SESSION_ROOT": self.session_root,
    },
    stdin=child_stdin,
    stdout=child_stdout,
    stderr=stderr_output,
    cwd=self.repo_root,
    no_wait=true,
  )
  // Recompute after spawn: process creation is part of the agent-work budget.
  // Reusing the caller's pre-spawn remainder would grant launch latency to the
  // provider turn a second time.
  let remaining_ms = self.remaining_work_ms(started_ms)
  let run_result : Result[TrialStop?, Error] = if remaining_ms <= 0 {
    Ok(None)
  } else {
    Ok(
      @async.with_timeout_opt(remaining_ms, () => {
        if submit_task_prompt {
          controller.run(goal_text=self.goal_text, task_prompt=self.task_prompt)
        } else {
          controller.reconnect_goal(goal_text=self.goal_text)
        }
      }),
    ) catch {
      error if @async.is_being_cancelled() ||
        @async.is_cancellation_error(error) => raise error
      error => Err(error)
    }
  }
  let stop = match run_result {
    Ok(Some(stop)) => stop
    Ok(None) => TimedOut
    Err(error) => TurnFailed("benchmark driver failed: \{error}")
  }
  if stop is TimedOut {
    // This command is only a best-effort request after the agent-work deadline
    // has already decided the outcome. A closed stdin must not rewrite a
    // genuine timeout as a controller failure.
    ignore(
      @async.with_timeout_opt(1_000, () => controller.send(Cancel)) catch {
        error if @async.is_being_cancelled() ||
          @async.is_cancellation_error(error) => raise error
        _ => None
      },
    )
  }
  stdin_writer.close()
  if @async.with_timeout_opt(10_000, () => controller.drain()) is None {
    process.cancel()
  }
  let exit_code = if @async.with_timeout_opt(2_000, () => process.wait())
    is Some(code) {
    code
  } else {
    process.cancel()
    process.wait()
  }
  { stop, exit_code }
}

///|
/// Run `openseek serve`, keep stdin alive through automatic continuation, and
/// enforce one absolute agent-work deadline. Bounded pipe/process cleanup
/// follows a terminal verdict without rewriting it. Unexpected serve exits may
/// restart the process up to three consecutive times in the same durable
/// session. A prebuilt `engine` is executed directly; an empty path uses the
/// OpenSeek checkout through `moon run`.
async fn EngineTrial::execute(self : EngineTrial) -> EngineOutcome {
  let started_ms = @env.now().reinterpret_as_int64()
  @async.with_task_group(group => {
    let raw_log = @fs.open(
      self.raw_log,
      mode=WriteOnly,
      create_mode=CreateOrTruncate,
    )
    defer raw_log.close()
    let state = GoalTrialState(self.goal_text)
    let mut first_process = true
    let mut submit_task_prompt = true
    let mut stop = StreamEnded
    let mut exit_code = -1
    for ;; {
      if self.remaining_work_ms(started_ms) <= 0 {
        stop = TimedOut
        break
      }
      let attempt = self.execute_attempt(
        group, raw_log, state, first_process, submit_task_prompt, started_ms,
      )
      stop = attempt.stop
      exit_code = attempt.exit_code
      let process_failed = match stop {
        StreamEnded => true
        TurnFailed(error) => error.has_prefix("benchmark driver failed:")
        _ => false
      }
      if process_failed {
        // A recoverable process failure becomes a timeout only when its bounded
        // cleanup leaves no agent-work budget for a replacement. A terminal
        // model/controller verdict received in time is final even if its
        // cleanup crosses the same timestamp.
        if self.remaining_work_ms(started_ms) <= 0 {
          stop = TimedOut
          break
        }
        if state.consecutive_engine_restarts() < 3 {
          // A User event is appended durably before setup and before AgentStep.
          // Read the typed session log after the dead process is reaped: stdout
          // progress cannot distinguish "not accepted" from "persisted, then
          // crashed before the first step".
          submit_task_prompt = !self.task_prompt_is_durable()
          if self.remaining_work_ms(started_ms) <= 0 {
            stop = TimedOut
            break
          }
          state.record_engine_restart()
          first_process = false
          continue
        }
      }
      break
    }
    let elapsed_ms = @env.now().reinterpret_as_int64() - started_ms
    {
      stop,
      exit_code,
      elapsed_ms,
      steps: state.steps(),
      turns: state.turns(),
      prompt_tokens: state.prompt_tokens(),
      completion_tokens: state.completion_tokens(),
      total_tokens: state.total_tokens(),
      transport_retries: state.transport_retries(),
      engine_restarts: state.engine_restarts(),
    }
  })
}
