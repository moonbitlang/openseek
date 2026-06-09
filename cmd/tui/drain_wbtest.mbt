///|
fn drain_test_state() -> State {
  State::new({
    api_key: "k",
    model: V4Pro,
    cwd: ".",
    max_steps: 10,
    session_id: Some(SessionId("test")),
    session_root: ".openseek",
    engine: "openseek",
  })
}

///|
fn ephemeral_drain_test_state() -> State {
  State::new({
    api_key: "k",
    model: V4Pro,
    cwd: ".",
    max_steps: 10,
    session_id: None,
    session_root: ".openseek",
    engine: "openseek",
  })
}

///|
fn start_agent_count(cmds : Array[Cmd]) -> Int {
  let mut count = 0
  for cmd in cmds {
    if cmd is StartAgent(_, ..) {
      count = count + 1
    }
  }
  count
}

///|
fn error_item_count(cmds : Array[Cmd]) -> Int {
  let mut count = 0
  for cmd in cmds {
    if cmd is AppendItem(Error(_)) {
      count = count + 1
    }
  }
  count
}

///|
fn run_command_count(cmds : Array[Cmd]) -> Int {
  let mut count = 0
  for cmd in cmds {
    if cmd is RunCommand(_, ..) {
      count = count + 1
    }
  }
  count
}

///|
test "agent engine argv stays replay-compatible while session config uses env" {
  let config = drain_test_state().config
  let args = engine_args("--literal task")
  assert_eq(args.length(), 2)
  assert_eq(args[0], "--")
  assert_eq(args[1], "--literal task")
  let env = engine_extra_env(config)
  guard env.get("OPENSEEK_SESSION") is Some(session_id) else {
    fail("missing session id env")
  }
  guard env.get("OPENSEEK_SESSION_ROOT") is Some(session_root) else {
    fail("missing session root env")
  }
  assert_eq(session_id, "test")
  assert_eq(session_root, ".openseek")
}

///|
test "agent engine env omits session config for fresh runs" {
  let env = engine_env(ephemeral_drain_test_state().config, {})
  assert_true(env.get("OPENSEEK_SESSION") is None)
  assert_true(env.get("OPENSEEK_SESSION_ROOT") is None)
}

///|
test "agent engine env overrides inherited session config" {
  let inherited = {
    "OPENSEEK_SESSION": "parent",
    "OPENSEEK_SESSION_ROOT": "/tmp/parent",
    "PATH": "/bin",
  }
  let env = engine_env(drain_test_state().config, inherited)
  assert_true(env.get("PATH") == Some("/bin"))
  assert_true(env.get("OPENSEEK_SESSION") == Some("test"))
  assert_true(env.get("OPENSEEK_SESSION_ROOT") == Some(".openseek"))
  assert_true(inherited.get("OPENSEEK_SESSION") == Some("parent"))
}

///|
test "agent engine env clears inherited session config for fresh runs" {
  let env = engine_env(ephemeral_drain_test_state().config, {
    "OPENSEEK_SESSION": "parent",
    "OPENSEEK_SESSION_ROOT": "/tmp/parent",
    "PATH": "/bin",
  })
  assert_true(env.get("PATH") == Some("/bin"))
  assert_true(env.get("OPENSEEK_SESSION") is None)
  assert_true(env.get("OPENSEEK_SESSION_ROOT") is None)
}

///|
test "a submitted shell command runs locally, not via the agent" {
  let state = drain_test_state()
  // A `!` command submitted while idle drains to a local RunCommand, never to
  // the agent engine.
  let cmds = update(state, UiInput(Steer(Command("ls"))))
  assert_true(state.run is Running(_))
  assert_eq(run_command_count(cmds), 1)
  assert_eq(start_agent_count(cmds), 0)
}

///|
test "queued input drains exactly when the agent is idle" {
  let state = drain_test_state()

  // Submit while idle: starts immediately, nothing left queued.
  let cmds = update(state, UiInput(Steer(Prompt("a"))))
  assert_true(state.run is Running(_))
  assert_eq(state.queued.length(), 0)
  assert_eq(start_agent_count(cmds), 1)

  // Submit while running: queues, no new agent started.
  let cmds = update(state, UiInput(Queue(Prompt("b"))))
  assert_true(state.run is Running(_))
  assert_eq(state.queued.length(), 1)
  assert_eq(start_agent_count(cmds), 0)

  // A non-terminal progress event must not drain the queue.
  let cmds = update(
    state,
    AgentProgress(run_id=state.run_id, AssistantMessage("thinking")),
  )
  assert_true(state.run is Running(_))
  assert_eq(state.queued.length(), 1)
  assert_eq(start_agent_count(cmds), 0)

  // Agent finishes with one queued: drains "b" and starts it.
  let cmds = update(
    state,
    AgentProgress(run_id=state.run_id, AgentFinished("done-a")),
  )
  assert_true(state.run is Running(_))
  assert_eq(state.queued.length(), 0)
  assert_eq(start_agent_count(cmds), 1)

  // Agent finishes with empty queue: stays idle, nothing started.
  let cmds = update(
    state,
    AgentProgress(run_id=state.run_id, AgentFinished("done-b")),
  )
  assert_true(state.run is Idle)
  assert_eq(state.queued.length(), 0)
  assert_eq(start_agent_count(cmds), 0)
}

///|
test "a stale terminal event from a superseded run is ignored" {
  let state = drain_test_state()

  // Run A starts, and a second input B is queued behind it.
  let _ = update(state, UiInput(Steer(Prompt("a"))))
  let run_a = state.run_id
  let _ = update(state, UiInput(Queue(Prompt("b"))))

  // A finishes: the queue drains and B starts as a new run with a fresh id.
  let _ = update(state, AgentProgress(run_id=run_a, AgentFinished("done-a")))
  assert_true(state.run is Running(_))
  let run_b = state.run_id
  assert_true(run_b != run_a)

  // A late terminal from the already-superseded run A (e.g. an `AgentCancelled`
  // that races a natural finish) must be dropped: it neither finishes B nor
  // drains the queue again.
  let cmds = update(state, AgentCancelled(run_id=run_a))
  assert_eq(cmds.length(), 0)
  assert_true(state.run is Running(_))
  assert_eq(state.run_id, run_b)
}

///|
fn quit_count(cmds : Array[Cmd]) -> Int {
  let mut count = 0
  for cmd in cmds {
    if cmd is Quit {
      count = count + 1
    }
  }
  count
}

///|
test "Ctrl+C quits when idle and interrupts when a task is running" {
  let state = drain_test_state()

  // Idle: an interrupt quits the TUI rather than reporting a dead end.
  let cmds = update(state, UiInput(Interrupt))
  assert_eq(quit_count(cmds), 1)
  assert_eq(error_item_count(cmds), 0)
  assert_true(state.run is Idle)

  // Running: the same interrupt cancels the task instead of quitting.
  let _ = update(state, UiInput(Steer(Prompt("a"))))
  assert_true(state.run is Running(_))
  let cmds = update(state, UiInput(Interrupt))
  assert_eq(quit_count(cmds), 0)
  assert_true(cmds.iter().any(cmd => cmd is CancelAgent))
  assert_true(state.run is Interrupting(_))
}

///|
test "a tick while idle never starts an agent" {
  let state = drain_test_state()
  let cmds = update(state, Tick)
  assert_true(state.run is Idle)
  assert_eq(start_agent_count(cmds), 0)
}

///|
test "steering a running agent reports an error and does not queue" {
  let state = drain_test_state()

  // Idle Steer submits and starts a task.
  let _ = update(state, UiInput(Steer(Prompt("a"))))
  assert_true(state.run is Running(_))
  assert_eq(state.queued.length(), 0)

  // Steer while running: error, nothing queued, nothing started.
  let cmds = update(state, UiInput(Steer(Prompt("b"))))
  assert_eq(state.queued.length(), 0)
  assert_eq(start_agent_count(cmds), 0)
  assert_eq(error_item_count(cmds), 1)

  // Queue while running still queues without error.
  let cmds = update(state, UiInput(Queue(Prompt("c"))))
  assert_eq(state.queued.length(), 1)
  assert_eq(error_item_count(cmds), 0)
}

///|
test "compact_lines strips CRLF so tool output has no stray carriage returns" {
  inspect(compact_lines("a\r\nb\r\nc", 6).join("|"), content="a|b|c")
  // Truncation still works and the kept lines carry no `\r`.
  inspect(
    compact_lines("a\r\nb\r\nc\r\nd\r\ne", 3).join("|"),
    content="a|... +3 lines|e",
  )
}
