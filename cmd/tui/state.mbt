///|
priv struct AppConfig {
  api_key : String
  api_url : String?
  model : @deepseek.Model
  cwd : String
  max_steps : Int
  thinking : @deepseek.ThinkingMode
  // The durable session every prompt of this TUI run converses in. The engine
  // is spawned fresh per prompt, so context only carries between prompts
  // through the session store: without one, each prompt would be an amnesiac
  // one-shot. `--session` picks (or resumes) an id; otherwise one is generated
  // per launch.
  session_id : @agent_session.SessionId
  session_root : String
  // The agent engine the TUI spawns and reads JSONL events from. Defaults to
  // the `openseek` binary on `PATH`; override (e.g. to a recorded-stream
  // replayer) with `--engine` or `OPENSEEK_ENGINE`.
  engine : String
  engine_mode : EngineMode
}

///|
/// How the TUI talks to its engine. `Serve` (the default) keeps one
/// persistent `--serve` process per session — warm watchers, steering,
/// polite cancel. `OneShot` spawns the engine once per prompt with the task
/// as an argument: the escape hatch for replay or custom engines that only
/// speak the original protocol; steering is unavailable there.
priv enum EngineMode {
  Serve
  OneShot
}

///|
fn EngineMode::parse(input : String) -> EngineMode raise {
  match input {
    "serve" => Serve
    "oneshot" => OneShot
    other => fail("unknown engine mode: \{other} (use serve or oneshot)")
  }
}

///|
priv enum RunState {
  Idle
  Running(Int64)
  Interrupting(Int64)
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
  mut run_id : Int
  // Whether the active run is a local `!` shell command rather than an
  // engine turn. Steering and interrupt escalation must not touch the
  // persistent engine while the work in flight is a local task.
  mut run_is_command : Bool
  // Final assistant text for the current step, used to avoid appending the same
  // answer again when `AgentFinished` follows `AssistantMessage`.
  mut step_response : String?
  // Incremental assistant text currently arriving from `assistant_delta`
  // events. Cleared once the final assistant message is committed.
  mut streaming_response : String?
  // Incremental thinking-mode text arriving from `reasoning_delta` events.
  // Shown only until the first content delta arrives, so the activity line
  // moves during the (often long) reasoning phase instead of sitting on
  // "Working (Ns)".
  mut streaming_reasoning : String?
  // Steering input sent to the engine but not yet confirmed (no
  // steer_applied/steer_dropped back). Shown on the activity line so the
  // moment of pressing Enter is acknowledged immediately — the transcript
  // echo only comes at the step boundary where the model actually sees it,
  // which during a long tool call can be many seconds later, and a silent
  // gap reads as "my keystroke was eaten".
  pending_steers : Array[String]
  mut usage : @event.UsageInfo?
  // Latest background `moon_check` watcher status ("running"/"stopped"), lifted
  // from the most recent `runtime_update` for the status bar. Empty until the
  // first watcher update arrives.
  mut watcher_status : String
}

///|
fn State::new(config : AppConfig) -> State {
  {
    config,
    queued: [],
    run: Idle,
    run_id: 0,
    run_is_command: false,
    pending_steers: [],
    step_response: None,
    streaming_response: None,
    streaming_reasoning: None,
    usage: None,
    watcher_status: "",
  }
}

///|
/// Begin tracking a freshly dispatched run: allocate the next run id and mark the
/// agent running. Returns the new run id so the caller can tag the spawned task's
/// messages with it.
fn State::start_run(self : State, started_ms : Int64) -> Int {
  self.run_id = self.run_id + 1
  self.run = Running(started_ms)
  self.step_response = None
  self.streaming_response = None
  self.streaming_reasoning = None
  self.run_id
}

///|
/// Whether `id` identifies the run currently in flight. False once that run has
/// ended (back to `Idle`) or been replaced by a newer one, so a late or stale
/// message from a superseded task is recognizable and can be ignored.
fn State::owns_run(self : State, id : Int) -> Bool {
  !(self.run is Idle) && id == self.run_id
}

///|
/// Reset run tracking after the agent stops (finished, aborted, cancelled, or
/// failed): no task running, no pending final or streaming response. In serve
/// mode the watcher status survives a turn ending — the persistent engine
/// keeps its `moon_check --watch` processes alive between prompts, so the
/// segment only clears when the engine itself exits (`EngineExited`) or a
/// runtime update reports the watcher stopped. A oneshot engine dies with its
/// turn, and its watchers with it, so there the status clears here as before.
fn State::finish_run(self : State) -> Unit {
  self.run = Idle
  self.run_is_command = false
  // Anything still unconfirmed died with the turn; the engine sweeps its
  // queue at turn end and reports each leftover as steer_dropped, which
  // arrives untagged and renders its own resubmit notice.
  self.pending_steers.clear()
  self.step_response = None
  self.streaming_response = None
  self.streaming_reasoning = None
  if self.config.engine_mode is OneShot {
    self.watcher_status = ""
  }
}

///|
/// Messages feeding the update loop. Task-originated variants carry the `run_id`
/// of the run that produced them (see `State::run_id`) so the loop can drop the
/// ones from a superseded run; `UiInput` and `Tick` are loop-intrinsic and
/// untagged.
priv enum Msg {
  UiInput(@ui.Event)
  AgentProgress(run_id~ : Int, @event.AgentEvent)
  AgentCancelled(run_id~ : Int)
  AgentFailed(run_id~ : Int, Error)
  // A `!` shell command the TUI ran locally finished; carries the original
  // command and raw result so the loop can render the transcript and produce the
  // shell-style text handed back to the engine. `run_id` is present when the
  // command owned the run slot (launched while idle) and absent when it ran in
  // the background alongside a live agent turn — the foreground case settles the
  // run, the background case must not.
  CommandResult(
    command~ : String,
    run_id~ : Int?,
    Result[@shell.ShellOutput, Error]
  )
  // A foreground `!` command cancelled by Ctrl-C before it produced a result.
  // It has no output to render or hand to the model, but the command line must
  // still survive in the transcript (the live input echo was dropped), so it
  // settles the run with a "(cancelled)" command card. Only a foreground
  // command reaches here, so `run_id` is always present.
  CommandCancelled(command~ : String, run_id~ : Int)
  // A steer the client could not deliver (no live engine/turn): show the
  // resubmit notice and settle its acknowledgment — the entry was created an
  // instant ago and cannot have been swept.
  SteerDropped(String)
  // A steer the engine rejected on the wire. Its turn's terminal event
  // always precedes it in the stream, so by the time this is processed the
  // acknowledgment it belonged to is already swept: notice only, settling
  // nothing — a fresh identical-text steer of the next turn keeps its own
  // acknowledgment.
  EngineSteerDropped(String)
  // Session errors are not tied to a model turn, so they are reported without a
  // run id and never affect run lifecycle.
  EngineSessionError(String)
  // The persistent engine process exited (for any reason): its background
  // watchers died with it, so engine-scoped status must reset.
  EngineExited
  Tick
}

///|
/// The run id carried by a task-originated message, or `None` for the
/// loop-intrinsic `UiInput`/`Tick` messages that belong to no particular run.
fn Msg::run_id(self : Msg) -> Int? {
  match self {
    AgentProgress(run_id~, _)
    | AgentCancelled(run_id~)
    | AgentFailed(run_id~, _) => Some(run_id)
    CommandResult(run_id~, _, ..) => run_id
    CommandCancelled(run_id~, ..) => Some(run_id)
    UiInput(_)
    | SteerDropped(_)
    | EngineSteerDropped(_)
    | EngineSessionError(_)
    | EngineExited
    | Tick => None
  }
}

///|
priv enum Cmd {
  AppendItem(@ui.TranscriptItem)
  // Start the agent / a local command for a run; carries the run id to tag that
  // task's messages with.
  StartAgent(run_id~ : Int, String)
  // Run a `!` shell command. `run_id` is present for a foreground command
  // launched while idle — it owns the cancellable run slot — and absent for a
  // background command running alongside a live agent turn, which is dispatched
  // fire-and-forget and must not become the cancel target.
  RunCommand(run_id~ : Int?, String)
  // Send typed model-visible input into the persistent serve engine. Prompt
  // steering lands at the running turn's next step boundary; command context
  // may also append into an idle engine session without starting a turn.
  SteerAgent(@agent_runtime.SteerInput)
  CancelAgent
  // Second Ctrl-C while already interrupting: the cancel command was not
  // enough, so kill the engine process outright.
  KillEngine
  Quit
}
