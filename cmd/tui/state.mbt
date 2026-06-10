///|
priv struct AppConfig {
  api_key : String
  model : @deepseek.Model
  cwd : String
  max_steps : Int
  thinking : @deepseek.ThinkingMode
  reasoning_effort : @deepseek.ReasoningEffort
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
/// failed): no task running, no pending final or streaming response. Also clear
/// the watcher status: `run_agent_task` spawns a fresh engine per prompt and any
/// `moon_check --watch` process belongs to that engine's runtime, so it is gone
/// once the engine exits — leaving `watcher_status` set would keep a stale
/// `moon_check running` segment in the status bar while the TUI sits idle.
fn State::finish_run(self : State) -> Unit {
  self.run = Idle
  self.run_is_command = false
  self.step_response = None
  self.streaming_response = None
  self.streaming_reasoning = None
  self.watcher_status = ""
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
  // A `!` shell command the TUI ran locally finished; carries the run id and the
  // transcript item to append. Commands run in the TUI and never reach the agent
  // engine.
  CommandResult(run_id~ : Int, @ui.TranscriptItem)
  // A steer had no live turn to land in (the engine died an instant before
  // Enter): surface the lost text so the user can resubmit it.
  SteerDropped(String)
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
    CommandResult(run_id~, _) => Some(run_id)
    UiInput(_) | SteerDropped(_) | Tick => None
  }
}

///|
priv enum Cmd {
  AppendItem(@ui.TranscriptItem)
  // Start the agent / a local command for a run; carries the run id to tag that
  // task's messages with.
  StartAgent(run_id~ : Int, String)
  RunCommand(run_id~ : Int, String)
  // Redirect the running turn: the text rides the engine's steer command and
  // lands at the turn's next step boundary.
  SteerAgent(String)
  CancelAgent
  // Second Ctrl-C while already interrupting: the cancel command was not
  // enough, so kill the engine process outright.
  KillEngine
  Quit
}
