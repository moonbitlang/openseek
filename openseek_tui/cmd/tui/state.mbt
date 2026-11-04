///|
priv struct AppConfig {
  api_key : String
  api_url : String?
  model : @deepseek.Model
  cwd : String
  max_steps : Int32?
  // Model-request retry overrides, forwarded to the engine. `None` leaves the
  // engine's own default (or an inherited `OPENSEEK_RETRY_*` value) in place.
  retry_attempts : Int32?
  retry_backoff_ms : Int32?
  thinking : @deepseek.ThinkingMode
  // The durable session every prompt of this TUI run converses in. The engine
  // process may exit between prompts (and is respawned on the next one), so
  // context only survives through the session store. `--session` picks (or
  // resumes) an id; otherwise one is generated per launch.
  session_id : @agent_session.SessionId
  session_root : String
  // Prompt files for the session this launch creates, forwarded to the engine
  // as `serve --system-prompt-file=…`. A prompt is written only when the engine
  // creates a session header, so an existing session keeps its stored prompt;
  // `reject_prompt_for_existing_session` refuses that combination instead of
  // letting these files be ignored.
  system_prompt_file : String?
  system_prompt_addendum_file : String?
  // The agent engine the TUI spawns and reads JSONL events from. Defaults to
  // `moonx` running the pinned `moonbitlang/openseek` release (see
  // `default_engine`); override (e.g. to a local build or a recorded-stream
  // replayer) with `--engine`.
  engine : String
  // Arguments inserted between the engine command and its subcommand: the
  // `moonbitlang/openseek@<version>` coordinate for the default `moonx` engine,
  // empty for an explicit `--engine`.
  engine_args_prefix : Array[String]
}

///|
/// The engine's `serve` argv, with the full placement: session, workspace, and
/// the prompt files of the session this launch creates. Every value is attached
/// so a leading `-` is data, not a second option.
fn AppConfig::engine_serve_args(self : AppConfig) -> Array[String] {
  let args = [
    ..self.engine_args_prefix,
    "serve",
    "--session=\{self.session_id.value()}",
    "--session-root=\{self.session_root}",
    "--dir=\{self.cwd}",
  ]
  // The files ride on the engine's own prompt options. Whether they apply is
  // the engine's call — it reads them only while creating a session — which is
  // why the launch refuses them for a session that already exists.
  if self.system_prompt_file is Some(path) {
    args.push("--system-prompt-file=\{path}")
  }
  if self.system_prompt_addendum_file is Some(path) {
    args.push("--system-prompt-addendum-file=\{path}")
  }
  args
}

///|
fn AppConfig::engine_display(self : AppConfig) -> String {
  if self.engine_args_prefix.length() == 0 {
    self.engine
  } else {
    let parts = [self.engine]
    parts.append(self.engine_args_prefix)
    parts.join(" ")
  }
}

///|
priv enum RunState {
  Idle
  Running(Int64)
  Interrupting(Int64)
}

///|
priv enum StreamingPreview {
  Reasoning(String)
  Response(String)
}

///|
/// A `!` shell command the TUI is running. It runs beside the conversation
/// rather than in its run slot: a prompt typed meanwhile starts its own turn.
priv struct ShellCommand {
  // Names the command to its task and to the result that task reports.
  id : Int32
  command : String
  started_ms : Int64
  // The command was taken from the input queue, which waits for its output
  // before the next queued input: Tab means "after this", and a prompt queued
  // behind a command is usually about what the command printed.
  holds_queue : Bool
  // Ctrl-C reached this command. Its task may still deliver a result that was
  // already on its way; that result is shown and not sent.
  mut interrupted : Bool
}

///|
/// The output of a finished `!` command, steered into the running turn and
/// not yet answered for: the engine reports every steer applied or dropped,
/// under the tag it was sent with.
priv struct SteeredOutput {
  // The tag, unique to this output. Receipts are matched by it and never by
  // text: the same command run twice sends the same envelope twice.
  submission_id : String
  command : String
  envelope : String
  // Carried over from the command (`ShellCommand::holds_queue`): the queue
  // goes on waiting until the output is known to have reached a turn.
  holds_queue : Bool
  // Ctrl-C came while the receipt was still out. If the output turns out to
  // have missed its turn, it is not sent again: the user asked for everything
  // to stop. The mark is the output's own, so it outlives whatever run starts
  // next.
  mut interrupted : Bool
}

///|
/// The output of a finished `!` command that is waiting for the conversation
/// to be idle, to start a turn of its own.
priv struct HeldOutput {
  command : String
  envelope : String
}

///|
priv struct State {
  config : AppConfig
  queued : Array[@ui.Input]
  mut run : RunState
  // Monotonic id of the most recently started run, bumped each time an input is
  // dispatched. Task-originated messages carry the id of the run that produced
  // them; a message whose id is not the active run's is stale (it came from a
  // task that has since been superseded) and is dropped. See `State::owns_run`.
  mut run_id : Int32
  // Whether the active run is a conversation compaction rather than an engine
  // turn. Compaction is a non-steerable model call (the serve engine drops
  // steers during it), so a prompt typed mid-compaction is rejected locally with
  // a queue hint rather than steered into the void.
  mut run_is_compaction : Bool
  // Final assistant text for the current step, used to avoid appending the same
  // answer again when `AgentFinished` follows `AssistantMessage`.
  mut step_response : String?
  // The newest tail of the current provider stream. Reasoning begins dimmed;
  // the first answer delta replaces it with the response preview because the
  // TUI has one live activity row. Completed content is appended separately.
  mut streaming_preview : StreamingPreview?
  // Steering input sent to the engine but not yet confirmed (no
  // steer_applied/steer_dropped back). Shown on the activity line so the
  // moment of pressing Enter is acknowledged immediately — the transcript
  // echo only comes at the step boundary where the model actually sees it,
  // which during a long tool call can be many seconds later, and a silent
  // gap reads as "my keystroke was eaten".
  pending_steers : Array[String]
  mut usage : @event.UsageInfo?
  // The `/loop` schedule, when one is armed. Bookkeeping (countdown, re-arm,
  // pause) lives in `update`; dispatch happens only at the post-update choke
  // point `scheduler_maybe_fire`, which also needs the composer state that
  // `update` cannot see.
  mut schedule : Schedule?
  /// The standing goal mirrored from the engine: seeded from the loaded
  /// session at startup and updated only by `goal_updated` events, so it
  /// only ever reflects durably persisted state.
  mut goal : String?
  // The `!` commands in flight. Their output is sent into the conversation
  // when they finish, so a scheduled fire waits for them: the output would
  // otherwise land in the scheduled turn instead of the exchange it belongs to.
  commands : Array[ShellCommand]
  // The id the next `!` command takes.
  mut next_command_id : Int32
  // Outputs steered into a turn whose receipt has not come back yet.
  steered_outputs : Array[SteeredOutput]
  // Outputs of finished `!` commands that could not be sent when they were
  // ready (a compaction or an interrupt was in the way, or the turn they were
  // steered into ended first). Each starts a turn once the conversation is
  // idle, ahead of queued input.
  held_outputs : Array[HeldOutput]
}

///|
fn State::State(config : AppConfig) -> State {
  {
    config,
    queued: [],
    run: Idle,
    run_id: 0,
    run_is_compaction: false,
    pending_steers: [],
    step_response: None,
    streaming_preview: None,
    usage: None,
    schedule: None,
    goal: None,
    commands: [],
    next_command_id: 0,
    steered_outputs: [],
    held_outputs: [],
  }
}

///|
/// Begin tracking a freshly dispatched run: allocate the next run id and mark the
/// agent running. Returns the new run id so the caller can tag the spawned task's
/// messages with it.
fn State::start_run(self : State, started_ms : Int64) -> Int32 {
  self.run_id += 1
  self.run = Running(started_ms)
  self.step_response = None
  self.streaming_preview = None
  self.run_id
}

///|
/// Whether `id` identifies the run currently in flight. False once that run has
/// ended (back to `Idle`) or been replaced by a newer one, so a late or stale
/// message from a superseded task is recognizable and can be ignored.
fn State::owns_run(self : State, id : Int32) -> Bool {
  !(self.run is Idle) && id == self.run_id
}

///|
/// Reset run tracking after the agent stops (finished, aborted, cancelled, or
/// failed): no task running, no pending final or streaming response.
fn State::finish_run(self : State) -> Unit {
  self.run = Idle
  self.run_is_compaction = false
  // Anything still unconfirmed died with the turn; the engine sweeps its
  // queue at turn end and reports each leftover as steer_dropped, which
  // arrives untagged and renders its own resubmit notice.
  self.pending_steers.clear()
  self.step_response = None
  self.streaming_preview = None
}

///|
/// Messages feeding the update loop. Task-originated variants carry the `run_id`
/// of the run that produced them (see `State::run_id`) so the loop can drop the
/// ones from a superseded run; `UiInput` and `Tick` are loop-intrinsic and
/// untagged.
priv enum Msg {
  UiInput(@ui.Event)
  AgentProgress(run_id~ : Int32, @event.AgentEvent)
  AgentCancelled(run_id~ : Int32)
  AgentFailed(run_id~ : Int32, Error)
  // A `!` shell command the TUI ran locally finished; carries the original
  // command and raw result so the loop can render the transcript and produce the
  // shell-style text sent into the conversation. `id` is the command's own
  // (`ShellCommand::id`), not a run's: a command belongs to no run.
  CommandResult(
    command~ : String,
    id~ : Int32,
    Result[@command_context.ShellOutput, Error]
  )
  // A `!` command cancelled by Ctrl-C before it produced a result. It has no
  // output to render or send, but the command line must still survive in the
  // transcript (it has no input echo), as a "(cancelled)" command card.
  CommandCancelled(command~ : String, id~ : Int32)
  // A steer the client could not deliver (no live engine/turn): show the
  // resubmit notice and settle its acknowledgment — the entry was created an
  // instant ago and cannot have been swept. Carries the tag the steer was
  // sent with, as the engine's own drop does.
  SteerDropped(String, submission_id~ : String?)
  // A steer the engine rejected on the wire. Its turn's terminal event
  // always precedes it in the stream, so by the time this is processed the
  // acknowledgment it belonged to is already swept: notice only, settling
  // nothing — a fresh identical-text steer of the next turn keeps its own
  // acknowledgment.
  EngineSteerDropped(String, submission_id~ : String?)
  // The engine exited without answering for the steer tagged `submission_id`,
  // a `!` command's output written to that very process. Reported per steer
  // rather than inferred from `EngineExited`: an exit says nothing about an
  // output the loop has recorded but not yet sent, or one sent to the engine
  // spawned since.
  EngineSteerLost(submission_id~ : String)
  // Session errors are not tied to a model turn, so they are reported without a
  // run id and never affect run lifecycle.
  EngineSessionError(String)
  // A background job finished while the engine was idle. Reported without a run
  // id (like a session error) so it is never swept by the stale-run guard, and
  // rendered as a notice line in the transcript.
  EngineBackgroundNotice(String)
  // The engine durably recorded a goal update. Untagged like a background
  // notice, so an idle confirmation is never swept by the stale-run guard.
  EngineGoalUpdated(String?)
  // The persistent engine process exited (for any reason): its background
  // watchers died with it, so the loop can observe the engine boundary.
  EngineExited
  // `/inspect` finished starting (or finding) the session viewer: the link to
  // this session, or why there is none. Untagged: it belongs to no run.
  ViewerOpened(Result[String, String])
  // What `/inspect` then did about opening that link in a browser.
  BrowserOpened(@open_in_browser.Outcome)
  Tick
}

///|
/// The run id carried by a task-originated message, or `None` for the
/// loop-intrinsic `UiInput`/`Tick` messages that belong to no particular run.
fn Msg::run_id(self : Msg) -> Int32? {
  match self {
    AgentProgress(run_id~, _)
    | AgentCancelled(run_id~)
    | AgentFailed(run_id~, _) => Some(run_id)
    UiInput(_)
    | CommandResult(_, ..)
    | CommandCancelled(..)
    | SteerDropped(_, ..)
    | EngineGoalUpdated(_)
    | EngineSteerDropped(_, ..)
    | EngineSteerLost(..)
    | EngineSessionError(_)
    | EngineBackgroundNotice(_)
    | EngineExited
    | ViewerOpened(_)
    | BrowserOpened(_)
    | Tick => None
  }
}

///|
priv enum Cmd {
  AppendItem(@ui.TranscriptItem)
  // Start the agent for a run; carries the run id to tag that turn's messages
  // with.
  StartAgent(run_id~ : Int32, String)
  // Run a `!` shell command under `id` (`ShellCommand::id`), beside whatever
  // the conversation is doing.
  RunCommand(id~ : Int32, String)
  // Stop the `!` command `id`. Its task answers with `CommandCancelled`.
  CancelCommand(id~ : Int32)
  // Steer the running turn with text the user typed. It lands at the turn's
  // next step boundary. Untagged: its receipt is matched by text, against the
  // acknowledgment shown for it (`pending_steers`).
  SteerAgent(String)
  // Steer the running turn with a `!` command's output, tagged so its receipt
  // can be told from typed text's and from another output's
  // (`SteeredOutput::submission_id`).
  SteerOutput(submission_id~ : String, String)
  // Ask the serve engine to summarize and compact the conversation; carries the
  // run id so the compaction's wire events are tagged to the run that requested
  // it, exactly like a prompt.
  CompactSession(run_id~ : Int32)
  // Set (Some) or clear (None) the standing goal on the serve engine. The
  // engine's goal_updated event — not this command — mutates local state.
  UpdateGoal(String?)
  // `/inspect`: start or reuse the session viewer in the background and report
  // the link as a `ViewerOpened` message.
  OpenViewer
  CancelAgent
  // Second Ctrl-C while already interrupting: the cancel command was not
  // enough, so kill the engine process outright.
  KillEngine
  Quit
}

///|
/// Begin tracking a `!` command about to run, and return the id its task
/// reports under.
fn State::start_command(
  self : State,
  command : String,
  started_ms : Int64,
  holds_queue~ : Bool,
) -> Int32 {
  let id = self.next_command_id
  self.next_command_id += 1
  self.commands.push({
    id,
    command,
    started_ms,
    holds_queue,
    interrupted: false,
  })
  id
}

///|
/// The steered output a receipt tagged `submission_id` answers for, no longer
/// awaited. `None` for an untagged receipt — typed text — and for a tag
/// nothing is waiting on.
fn State::settle_output(
  self : State,
  submission_id : String?,
) -> SteeredOutput? {
  guard submission_id is Some(id) &&
    self.steered_outputs.search_by(output => output.submission_id == id)
    is Some(index) else {
    return None
  }
  Some(self.steered_outputs.remove(index))
}

///|
/// Stop tracking the `!` command `id`, whose task has reported. `None` when
/// nothing is tracked under that id.
fn State::finish_command(self : State, id : Int32) -> ShellCommand? {
  guard self.commands.search_by(command => command.id == id) is Some(index) else {
    return None
  }
  Some(self.commands.remove(index))
}
