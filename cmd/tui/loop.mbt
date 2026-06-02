///|
async fn read_ui_events(ui : @ui.Ui, messages : @async.Queue[Msg]) -> Unit {
  for ;; {
    let event = ui.read_event()
    messages.put(UiInput(event))
    if event is Quit {
      break
    }
  }
}

///|
async fn tick_ui(messages : @async.Queue[Msg]) -> Unit {
  for ;; {
    @async.sleep(1000)
    messages.put(Tick)
  }
}

///|
async fn run_agent_task(
  config : AppConfig,
  input : @ui.Input,
  messages : @async.Queue[Msg],
) -> Unit {
  @agent.run(
    config.api_key,
    config.model,
    task_text(input),
    on_event=event => messages.put(AgentProgress(event)),
    max_steps=config.max_steps,
  ) catch {
    error if @async.is_being_cancelled() || @async.is_cancellation_error(error) =>
      messages.put(AgentCancelled)
    error => messages.put(AgentFailed(error))
  }
}

///|
fn message_finishes_agent(message : Msg) -> Bool {
  match message {
    AgentProgress(Finished(_) | Aborted(_) | MaxStepsExhausted | AgentError(_))
    | AgentCancelled
    | AgentFailed(_) => true
    _ => false
  }
}

///|
/// Apply one agent progress event to `state`, queueing any transcript updates in
/// `cmds`. Terminal events call `finish_run`, leaving the agent idle so the
/// queue drain at the end of `update` can start the next input.
fn handle_agent_event(
  state : State,
  event : @agent.AgentEvent,
  cmds : Array[Cmd],
) -> Unit {
  match event {
    StepStarted(_) => {
      state.current_tool = None
      state.step_response = None
    }
    ReasoningMessage(_) => ()
    AssistantMessage(text) => {
      state.step_response = Some(text)
      if !text.trim().is_empty() {
        cmds.push(AppendItem(Response(text)))
      }
    }
    Usage(usage) => state.usage = Some(usage)
    ToolCallStarted(call) => state.current_tool = Some(call.name)
    ToolCallFinished(result) => {
      state.current_tool = None
      cmds.push(AppendItem(tool_item(result)))
    }
    Finished(answer) => {
      let already_appended = match state.step_response {
        Some(response) => response == answer
        None => false
      }
      // `Finished` follows `AssistantMessage` for normal chat responses, but
      // tool-controlled finish results may arrive without one.
      if !already_appended && !answer.trim().is_empty() {
        cmds.push(AppendItem(Response(answer)))
      }
      state.finish_run()
    }
    Aborted(reason) => {
      cmds.push(AppendItem(Error("aborted: " + reason)))
      state.finish_run()
    }
    MaxStepsExhausted => {
      cmds.push(AppendItem(Error("max steps exhausted")))
      state.finish_run()
    }
    AgentError(message) => {
      cmds.push(AppendItem(Error(message)))
      state.finish_run()
    }
  }
}

///|
fn update(state : State, message : Msg) -> Array[Cmd] {
  let cmds : Array[Cmd] = []
  match message {
    UiInput(event) =>
      match event {
        // Steering (redirecting a task mid-run) is not implementable with the
        // current agent API. Steer only submits when idle; while a task runs it
        // reports an error instead of silently queuing. Queue always queues.
        Steer(input) =>
          if state.run is Idle {
            state.queued.push(input)
          } else {
            cmds.push(
              AppendItem(
                Error(
                  "Steering is not supported while a task is running. Press Tab to queue this input.",
                ),
              ),
            )
          }
        Queue(input) => state.queued.push(input)
        Interrupt =>
          match state.run {
            Idle =>
              cmds.push(AppendItem(Error("No running task to interrupt.")))
            Running(started_ms) => {
              state.run = Interrupting(started_ms)
              cmds.push(CancelAgent)
            }
            Interrupting(_) => cmds.push(CancelAgent)
          }
        Quit => cmds.push(Quit)
      }
    AgentProgress(event) => handle_agent_event(state, event, cmds)
    AgentCancelled => {
      cmds.push(AppendItem(Error("interrupted")))
      state.finish_run()
    }
    AgentFailed(error) => {
      cmds.push(AppendItem(Error("agent failed: \{error}")))
      state.finish_run()
    }
    // No state change: Tick is a 1s heartbeat that just keeps the message loop
    // turning so the trailing refresh_ui re-runs and the elapsed-time activity
    // line ("Working (12s)") keeps advancing during quiet stretches.
    Tick => ()
  }
  // The agent runs one input at a time: whenever it is idle and inputs are
  // waiting, start the next one. Only submissions and run-ending events can
  // reach "idle with a non-empty queue", so this never fires spuriously.
  if state.run is Idle && state.queued.length() > 0 {
    let input = state.queued.remove(0)
    cmds.push(AppendItem(Input(input)))
    state.run = Running(@async.now())
    state.current_tool = None
    state.step_response = None
    cmds.push(StartAgent(input))
  }
  cmds
}

///|
async fn[G] run_message_loop(
  state : State,
  ui : @ui.Ui,
  group : @async.TaskGroup[G],
  messages : @async.Queue[Msg],
) -> Unit {
  let mut running_task : @async.Task[Unit]? = None
  outer~: for ;; {
    let message = messages.get()
    if message_finishes_agent(message) {
      running_task = None
    }
    for cmd in update(state, message) {
      match cmd {
        AppendItem(item) => ui.append_item(item)
        StartAgent(input) =>
          running_task = Some(
            group.spawn(no_wait=true) <| () => {
              run_agent_task(state.config, input, messages)
            },
          )
        CancelAgent => if running_task is Some(task) { task.cancel() }
        Quit => break outer~
      }
    }
    refresh_ui(ui, state)
  }
}
