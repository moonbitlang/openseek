///|
fn cli_command() -> @argparse.Command {
  Command(
    "openseek-tui",
    about="OpenSeek terminal UI.",
    options=[
      OptionArg(
        "api-key",
        long="api-key",
        env="DEEPSEEK",
        required=true,
        about="DeepSeek API key.",
      ),
      OptionArg(
        "model",
        long="model",
        env="DEEPSEEK_MODEL",
        default_values=[@deepseek.V4Pro.to_string()],
        about="DeepSeek model: deepseek-v4-flash or deepseek-v4-pro.",
      ),
      OptionArg(
        "max-steps",
        long="max-steps",
        env="OPENSEEK_MAX_STEPS",
        default_values=["1000"],
        about="Maximum number of agent loop steps before stopping.",
      ),
      OptionArg(
        "engine",
        long="engine",
        env="OPENSEEK_ENGINE",
        default_values=["openseek"],
        about="Agent engine binary to spawn; reads its JSONL event stream from stdout.",
      ),
      OptionArg(
        "session",
        long="session",
        env="OPENSEEK_SESSION",
        about="Create or resume this durable session id.",
      ),
      OptionArg(
        "session-root",
        long="session-root",
        env="OPENSEEK_SESSION_ROOT",
        default_values=[".openseek"],
        about="Directory containing durable OpenSeek sessions.",
      ),
    ],
    positionals=[
      PositionArg(
        "task",
        num_args=ValueRange(lower=0),
        allow_hyphen_values=true,
        about="Optional initial task description.",
      ),
    ],
  )
}

///|
fn value(matches : @argparse.Matches, name : String) -> String raise {
  match matches.values.get(name) {
    Some([value]) => value
    Some(values) if values.length() > 0 => values[0]
    _ => fail("missing parsed argument: \{name}")
  }
}

///|
fn values(matches : @argparse.Matches, name : String) -> Array[String] {
  match matches.values.get(name) {
    Some(values) => values
    None => []
  }
}

///|
fn parse_positive_int(input : String, label : String) -> Int raise {
  let parsed = @string.parse_int(input) catch {
    _ => fail("\{label} must be a positive integer, got: \{input}")
  }
  guard parsed > 0 else {
    fail("\{label} must be a positive integer, got: \{input}")
  }
  parsed
}

///|
fn session_id(matches : @argparse.Matches) -> @agent_session.SessionId? {
  let session = match values(matches, "session") {
    [session, ..] => session.trim().to_owned()
    [] => ""
  }
  if session.is_empty() {
    None
  } else {
    Some(SessionId(session))
  }
}

///|
fn session_root(matches : @argparse.Matches) -> String raise {
  let root = value(matches, "session-root").trim().to_owned()
  if root.is_empty() {
    fail("--session-root or OPENSEEK_SESSION_ROOT must not be empty")
  }
  root
}

///|
fn parse_config(matches : @argparse.Matches) -> AppConfig raise {
  let cwd = match @env.current_dir() {
    Some(cwd) => cwd
    None => "."
  }
  let session_id = session_id(matches)
  let session_root_value = if session_id is Some(_) {
    session_root(matches)
  } else {
    let root = value(matches, "session-root").trim().to_owned()
    if root.is_empty() {
      ".openseek"
    } else {
      root
    }
  }
  {
    api_key: value(matches, "api-key"),
    model: @deepseek.Model::parse(value(matches, "model")),
    cwd,
    max_steps: parse_positive_int(value(matches, "max-steps"), "--max-steps"),
    session_id,
    session_root: session_root_value,
    engine: value(matches, "engine"),
  }
}

///|
fn initial_task(matches : @argparse.Matches) -> String? {
  let task = values(matches, "task").join(" ").trim().to_owned()
  if task.is_empty() {
    None
  } else {
    Some(task)
  }
}

///|
async fn run_tui(config : AppConfig, initial : String?) -> Unit {
  @ui.with_ui(config=@ui.Config::new(composer_max_rows=4), ui => {
    run_app(config, initial, ui)
  })
}

///|
async fn run_app(config : AppConfig, initial : String?, ui : @ui.Ui) -> Unit {
  let state = State::new(config)
  let messages = @async.Queue(kind=Unbounded)
  append_session_history(state.config, ui)
  ui.append_item(Response("OpenSeek TUI ready"))
  refresh_ui(ui, state)
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true) <| () => { read_ui_events(ui, messages) }
    group.spawn_bg(no_wait=true) <| () => { tick_ui(messages) }
    match initial {
      Some(task) => messages.put(UiInput(Steer(Prompt(task))))
      None => ()
    }
    run_message_loop(state, ui, group, messages)
  })
}

///|
/// Whether the engine is usable enough to launch. The agent engine is spawned
/// fresh per task (and only once the user submits one), so a missing, non-
/// executable, or non-`openseek`-like engine would otherwise surface deep inside
/// the running UI. We probe it once at startup with `<engine> --help`, which is
/// part of the engine contract: like `openseek`, any `--engine` replacement must
/// accept `--help` as a side-effect-free no-op that exits 0 — it makes no API
/// call, and its output is captured so it never reaches the terminal. The engine
/// is usable only if that probe spawns and exits 0; `ENOENT`/`EACCES` (not found
/// / not executable) or a non-zero exit both mean it is not. Any other failure
/// is unexpected and re-raised rather than mislabeled as a bad engine.
async fn engine_launchable(engine : String) -> Bool {
  try {
    let (code, _) = @process.collect_output_merged(
      engine,
      ["--help"],
      inherit_env=true,
    )
    code == 0
  } catch {
    @os_error.OSError(_) as err if err.is_ENOENT() || err.is_EACCES() => false
    err => raise err
  }
}

///|
async fn main {
  let matches = cli_command().parse(env=@env.get_env_vars())
  let config = parse_config(matches)
  // Fail before the terminal UI takes over the screen if the engine is unusable,
  // rather than dropping the user into a UI that dies on the first task.
  if !engine_launchable(config.engine) {
    println(
      "error: engine '\{config.engine}' is not usable: it must be on PATH, executable, and accept `--help` (exit 0) the way openseek does.",
    )
    println(
      "Pass --engine <path>, set OPENSEEK_ENGINE, or install the openseek binary.",
    )
    @sys.exit(1)
  }
  run_tui(config, initial_task(matches))
}

///|
test "cli accepts no initial task" {
  let parsed = cli_command().parse(argv=[], env={ "DEEPSEEK": "test-key" })
  assert_true(initial_task(parsed) is None)
  let config = parse_config(parsed)
  assert_eq(config.api_key, "test-key")
  assert_eq(config.max_steps, 1000)
  assert_eq(config.engine, "openseek")
  assert_true(config.session_id is None)
  assert_eq(config.session_root, ".openseek")
}

///|
test "cli accepts initial task and max steps" {
  let parsed = cli_command().parse(
    argv=["--max-steps", "5", "inspect", "project"],
    env={ "DEEPSEEK": "test-key" },
  )
  assert_true(initial_task(parsed) == Some("inspect project"))
  assert_eq(parse_config(parsed).max_steps, 5)
}

///|
test "cli accepts session configuration" {
  let parsed = cli_command().parse(
    argv=["--session", "demo", "--session-root", "/tmp/openseek-sessions"],
    env={ "DEEPSEEK": "test-key" },
  )
  let config = parse_config(parsed)
  guard config.session_id is Some(id) else { fail("expected session id") }
  assert_eq(id.value(), "demo")
  assert_eq(config.session_root, "/tmp/openseek-sessions")
}

///|
test "cli rejects empty session root when session is active" {
  let parsed = cli_command().parse(
    argv=["--session", "demo", "--session-root", ""],
    env={ "DEEPSEEK": "test-key" },
  )
  let _ = parse_config(parsed) catch {
    error => {
      assert_true("\{error}".contains("--session-root"))
      return
    }
  }
  fail("empty session root accepted")
}

///|
test "cli overrides the engine binary" {
  let parsed = cli_command().parse(argv=["--engine", "./fake-engine"], env={
    "DEEPSEEK": "test-key",
  })
  assert_eq(parse_config(parsed).engine, "./fake-engine")
}

///|
async test "engine_launchable rejects a binary that cannot be exec'd" {
  assert_false(engine_launchable("openseek-not-a-real-binary-xyz"))
}

///|
async test "engine_launchable accepts an engine whose --help exits 0" {
  // `moon` stands in for an engine that honors the `--help` no-op the probe
  // requires: `moon --help` exits 0 and, unlike `true`, `moon` is on PATH on
  // every platform the tests run on (including Windows native), so this stays
  // cross-platform.
  assert_true(engine_launchable("moon"))
}
