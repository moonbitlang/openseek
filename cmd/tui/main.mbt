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
fn parse_config(matches : @argparse.Matches) -> AppConfig raise {
  let cwd = match @env.current_dir() {
    Some(cwd) => cwd
    None => "."
  }
  {
    api_key: value(matches, "api-key"),
    model: @deepseek.Model::parse(value(matches, "model")),
    cwd,
    max_steps: parse_positive_int(value(matches, "max-steps"), "--max-steps"),
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
async fn main {
  let matches = cli_command().parse(env=@env.get_env_vars())
  run_tui(parse_config(matches), initial_task(matches))
}

///|
test "cli accepts no initial task" {
  let parsed = cli_command().parse(argv=[], env={ "DEEPSEEK": "test-key" })
  assert_true(initial_task(parsed) is None)
  let config = parse_config(parsed)
  assert_eq(config.api_key, "test-key")
  assert_eq(config.max_steps, 1000)
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
