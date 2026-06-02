///|
priv struct AppConfig {
  api_key : String
  model : @deepseek.Model
  cwd : String
  max_steps : Int
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
  mut current_tool : String?
  mut step_response : String?
  mut usage : @deepseek.Usage?
}

///|
fn State::new(config : AppConfig) -> State {
  {
    config,
    queued: [],
    run: Idle,
    current_tool: None,
    step_response: None,
    usage: None,
  }
}

///|
/// Reset run tracking after the agent stops (finished, aborted, cancelled, or
/// failed): no task running, no active tool, no pending step response.
fn State::finish_run(self : State) -> Unit {
  self.run = Idle
  self.current_tool = None
  self.step_response = None
}

///|
priv enum Msg {
  UiInput(@ui.Event)
  AgentProgress(@agent.AgentEvent)
  AgentCancelled
  AgentFailed(Error)
  Tick
}

///|
priv enum Cmd {
  AppendItem(@ui.TranscriptItem)
  StartAgent(@ui.Input)
  CancelAgent
  Quit
}

///|
fn task_text(input : @ui.Input) -> String {
  match input {
    Prompt(text) => text
    Command(command) =>
      "Run this shell command and report the result:\n" + command
  }
}

///|
test "command input becomes an agent task" {
  assert_eq(
    task_text(Command("moon test")),
    "Run this shell command and report the result:\nmoon test",
  )
}
