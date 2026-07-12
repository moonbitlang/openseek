///|
/// `/goal` — show, set, or clear the session's standing goal.
///
/// Bare `/goal` shows the mirrored state locally. `set <text>` and `clear`
/// go to the serve engine as a wire command; the transcript confirmation
/// arrives with the engine's `goal_updated` event, after the durable append,
/// so the TUI never claims a goal that was not persisted. The explicit `set`
/// keyword keeps a goal whose text starts with "clear" expressible.
fn handle_goal_command(
  state : State,
  arguments : String,
  cmds : Array[Cmd],
) -> Unit {
  let trimmed = arguments.trim().to_owned()
  if trimmed.is_empty() {
    let text = match state.goal {
      Some(goal) => "goal: \{goal}"
      None => "no standing goal — set one with /goal set <text>"
    }
    cmds.push(AppendItem(command_notice(text)))
    return
  }
  // The goal is durable session state on the persistent serve engine; a
  // oneshot engine is spawned per prompt and keeps no session to anchor it.
  if state.config.engine_mode is OneShot {
    cmds.push(
      AppendItem(
        Error("The goal command is not supported by a oneshot engine."),
      ),
    )
    return
  }
  if trimmed == "clear" {
    // Always send the clear: the mirror lags the engine by one ack, so a
    // clear typed while a set is still in flight must not be dropped on the
    // mirror's say-so. A tombstone on a goalless session is a harmless
    // no-op the engine still confirms.
    cmds.push(UpdateGoal(None))
    return
  }
  if trimmed == "set" || trimmed.has_prefix("set ") {
    let text = trimmed["set".length():].trim().to_owned()
    if text.is_empty() {
      cmds.push(AppendItem(Error("usage: /goal set <text>")))
    } else {
      cmds.push(UpdateGoal(Some(text)))
    }
    return
  }
  cmds.push(AppendItem(Error("usage: /goal | /goal set <text> | /goal clear")))
}

///|
/// Mirror an engine-confirmed goal update into local state and the
/// transcript. The engine's durable-append confirmation is the only writer
/// of the mirror — both the serve path (`EngineGoalUpdated`) and the
/// oneshot path (`GoalUpdated`) land here.
fn apply_goal_update(state : State, goal : String?, cmds : Array[Cmd]) -> Unit {
  state.goal = goal
  let title = match goal {
    Some(text) => "goal set: \{text}"
    None => "goal cleared"
  }
  cmds.push(AppendItem(Input(Notice(title))))
}

///|
fn goal_test_state() -> State {
  State::new({
    api_key: "k",
    api_url: Some("https://proxy.example/v1/chat/completions"),
    model: Deepseek(V4Pro),
    cwd: ".",
    max_steps: Some(10),
    thinking: Max,
    session_id: SessionId("goal-test"),
    session_root: ".openseek",
    engine: "openseek",
    engine_args_prefix: [],
    engine_mode: Serve,
  })
}

///|
fn update_goal_cmds(cmds : Array[Cmd]) -> Array[String?] {
  [
    for cmd in cmds if cmd is UpdateGoal(goal) => goal
  ]
}

///|
/// Local copies of the scheduler_wbtest counters: whitebox test files do not
/// reliably share definitions across files on release toolchains.
fn goal_notice_count(cmds : Array[Cmd]) -> Int {
  [ for cmd in cmds if cmd is AppendItem(Notice(_)) => cmd ].length()
}

///|
fn goal_error_count(cmds : Array[Cmd]) -> Int {
  [ for cmd in cmds if cmd is AppendItem(Error(_)) => cmd ].length()
}

///|
test "goal set and clear go to the engine; state stays untouched locally" {
  let state = goal_test_state()
  let set = update(
    state,
    UiInput(SlashCommand(name="goal", arguments="set ship the feature")),
  )
  assert_true(update_goal_cmds(set) is [Some("ship the feature")])
  assert_eq(goal_error_count(set), 0)
  // Only the engine's goal_updated confirmation mutates the mirror.
  assert_true(state.goal is None)
  state.goal = Some("ship the feature")
  let cleared = update(
    state,
    UiInput(SlashCommand(name="goal", arguments="clear")),
  )
  assert_true(update_goal_cmds(cleared) is [None])
  assert_eq(goal_error_count(cleared), 0)
}

///|
test "bare goal shows the mirrored state" {
  let state = goal_test_state()
  let empty = update(state, UiInput(SlashCommand(name="goal", arguments="")))
  assert_eq(goal_notice_count(empty), 1)
  assert_eq(update_goal_cmds(empty).length(), 0)
  state.goal = Some("ship the feature")
  let shown = update(state, UiInput(SlashCommand(name="goal", arguments="")))
  assert_eq(goal_notice_count(shown), 1)
  assert_eq(update_goal_cmds(shown).length(), 0)
}

///|
test "goal grammar rejects blanks, bare set, and unknown subcommands" {
  let state = goal_test_state()
  let bare_set = update(
    state,
    UiInput(SlashCommand(name="goal", arguments="set")),
  )
  assert_eq(goal_error_count(bare_set), 1)
  assert_eq(update_goal_cmds(bare_set).length(), 0)
  let padded_set = update(
    state,
    UiInput(SlashCommand(name="goal", arguments="set    ")),
  )
  assert_eq(goal_error_count(padded_set), 1)
  // No implicit set: a goal must be introduced by the keyword, so a goal
  // literally starting with "clear" stays expressible via `set clear ...`.
  let implicit = update(
    state,
    UiInput(SlashCommand(name="goal", arguments="just do it")),
  )
  assert_eq(goal_error_count(implicit), 1)
  assert_eq(update_goal_cmds(implicit).length(), 0)
  let keyword_goal = update(
    state,
    UiInput(SlashCommand(name="goal", arguments="set clear the backlog")),
  )
  assert_true(update_goal_cmds(keyword_goal) is [Some("clear the backlog")])
}

///|
test "clearing without a mirrored goal still goes to the engine" {
  // The mirror lags the engine by one ack: a clear typed while a set is
  // still in flight must reach the engine, not be dropped locally.
  let state = goal_test_state()
  let cmds = update(
    state,
    UiInput(SlashCommand(name="goal", arguments="clear")),
  )
  assert_true(update_goal_cmds(cmds) is [None])
  assert_eq(goal_error_count(cmds), 0)
}

///|
test "goal set is rejected on a oneshot engine" {
  let state = State::new({
    api_key: "k",
    api_url: None,
    model: Deepseek(V4Pro),
    cwd: ".",
    max_steps: Some(10),
    thinking: Max,
    session_id: SessionId("goal-oneshot"),
    session_root: ".openseek",
    engine: "replay-engine",
    engine_args_prefix: [],
    engine_mode: OneShot,
  })
  let cmds = update(
    state,
    UiInput(SlashCommand(name="goal", arguments="set ship it")),
  )
  assert_eq(goal_error_count(cmds), 1)
  assert_eq(update_goal_cmds(cmds).length(), 0)
  // Show still works locally.
  let shown = update(state, UiInput(SlashCommand(name="goal", arguments="")))
  assert_eq(goal_notice_count(shown), 1)
}

///|
test "goal_updated events write the mirror and confirm in the transcript" {
  let state = goal_test_state()
  let set = update(state, EngineGoalUpdated(Some("ship the feature")))
  assert_true(state.goal is Some("ship the feature"))
  assert_eq(goal_notice_count(set) + goal_input_notice_count(set), 1)
  let cleared = update(state, EngineGoalUpdated(None))
  assert_true(state.goal is None)
  assert_eq(goal_notice_count(cleared) + goal_input_notice_count(cleared), 1)
}

///|
fn goal_input_notice_count(cmds : Array[Cmd]) -> Int {
  [ for cmd in cmds if cmd is AppendItem(Input(Notice(_))) => cmd ].length()
}
