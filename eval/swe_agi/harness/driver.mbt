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
  goal_text~ : String,
) -> TrialController {
  { stdin, stdout, raw_log, state: GoalTrialState(goal_text) }
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
  for ;; {
    guard self.next_event() is Some(event) else { return StreamEnded }
    if self.state.observe(event) is Some(stop) {
      if stop.is_recoverable_transport_failure() &&
        self.state.transport_retries() < 10 {
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
  @async.sleep(5_000)
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
/// Close every parent-side descriptor. The methods are synchronous and
/// idempotent, so they are safe both on normal completion and error unwinding.
fn TrialController::close(self : TrialController) -> Unit {
  self.stdin.close()
  self.stdout.close()
  self.raw_log.close()
}

///|
/// Everything needed to launch one isolated goal-driven engine process.
priv struct EngineTrial {
  repo_root : String
  engine : String
  model : String
  max_steps : Int
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
/// Run `openseek serve`, keep stdin alive through automatic continuation, and
/// return a bounded outcome. A prebuilt `engine` is executed directly; an empty
/// path uses `moon run` from the OpenSeek checkout.
async fn EngineTrial::execute(self : EngineTrial) -> EngineOutcome {
  let started_ms = @env.now().reinterpret_as_int64()
  @async.with_task_group(group => {
    let (child_stdin, stdin_writer) = @process.write_to_process()
    let (stdout_reader, child_stdout) = @process.read_from_process()
    let raw_log = @fs.open(
      self.raw_log,
      mode=WriteOnly,
      create_mode=CreateOrTruncate,
    )
    let stderr_output = @process.redirect_to_file(
      self.stderr_log,
      create_mode=CreateOrTruncate,
    )
    let controller = TrialController(
      stdin=stdin_writer,
      stdout=stdout_reader,
      raw_log~,
      goal_text=self.goal_text,
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
    args.append([
      "--model",
      self.model,
      "--max-steps",
      self.max_steps.to_string(),
      "--dir",
      self.workspace,
      "--session",
      self.session_id,
    ])
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
    let run_result : Result[TrialStop?, Error] = Ok(
      @async.with_timeout_opt(self.timeout_ms, () => {
        controller.run(goal_text=self.goal_text, task_prompt=self.task_prompt)
      }),
    ) catch {
      error if @async.is_being_cancelled() ||
        @async.is_cancellation_error(error) => raise error
      error => Err(error)
    }
    let mut stop = match run_result {
      Ok(Some(stop)) => stop
      Ok(None) => TimedOut
      Err(error) => TurnFailed("benchmark driver failed: \{error}")
    }
    if stop is TimedOut {
      controller.send(Cancel) catch {
        error if @async.is_being_cancelled() ||
          @async.is_cancellation_error(error) => raise error
        error =>
          stop = TurnFailed("failed to cancel timed-out engine: \{error}")
      }
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
    {
      stop,
      exit_code,
      elapsed_ms: @env.now().reinterpret_as_int64() - started_ms,
      steps: controller.state.steps(),
      turns: controller.state.turns(),
      prompt_tokens: controller.state.prompt_tokens(),
      completion_tokens: controller.state.completion_tokens(),
      total_tokens: controller.state.total_tokens(),
      transport_retries: controller.state.transport_retries(),
    }
  })
}
