///|
/// Options shared by the UI and the headless engine (`--api-key`, `--model`, …).
/// `cmd/openseek` installs these on the root command with `global=true`, so they
/// read the same value in any position — bare `openseek`, `openseek --api-key k
/// tui`, `openseek tui --api-key k` — and the engine subcommands inherit them
/// rather than redeclaring (redeclaring a global is a build error). `--api-key`
/// is not argparse-`required`: argparse enforces a parent's required options for
/// *every* subcommand, which would wrongly block key-free subcommands like
/// `sessions list`; presence is enforced in `parse_config`. `global` is a
/// parameter so tests can build a standalone (non-global) `tui` command.
pub fn tui_shared_options(global? : Bool = false) -> Array[@argparse.OptionArg] {
  [
    OptionArg(
      "api-key",
      long="api-key",
      default_values=[""],
      global~,
      about="API key for the selected chat provider.",
    ),
    OptionArg(
      "deepseek-api-key",
      long="deepseek-api-key",
      env="DEEPSEEK",
      default_values=[""],
      global~,
      hidden=true,
    ),
    OptionArg(
      "kimi-api-key",
      long="kimi-api-key",
      env="KIMI",
      default_values=[""],
      global~,
      hidden=true,
    ),
    OptionArg(
      "glm-api-key",
      long="glm-api-key",
      env="GLM",
      default_values=[""],
      global~,
      hidden=true,
    ),
    OptionArg(
      "model",
      long="model",
      env="OPENSEEK_MODEL",
      default_values=[@deepseek.Deepseek(V4Flash).to_string()],
      global~,
      about="Chat model: deepseek-v4-flash, deepseek-v4-pro, kimi-k2.7-code, kimi-k2.7-code-highspeed, glm-5.3, or glm-5.3-flash.",
    ),
    OptionArg(
      "api-url",
      long="api-url",
      env="OPENSEEK_API_URL",
      default_values=[""],
      global~,
      about="OpenAI-compatible chat completions endpoint.",
    ),
    OptionArg(
      "max-steps",
      long="max-steps",
      env="OPENSEEK_MAX_STEPS",
      global~,
      about="Maximum agent steps per turn; omit to bound turns by the model's context window instead (a checkpoint summary carries each turn into the next).",
    ),
    OptionArg(
      "thinking",
      long="thinking",
      env="OPENSEEK_THINKING",
      default_values=["high"],
      global~,
      about="Model thinking mode: no, high, or max; GLM maps no to low effort.",
    ),
    OptionArg(
      "session",
      long="session",
      global~,
      about="Create or resume this durable session id.",
    ),
    OptionArg(
      "session-root",
      long="session-root",
      default_values=[".openseek"],
      global~,
      about="Directory containing durable OpenSeek sessions.",
    ),
  ]
}

///|
/// UI-only options — meaningless to the headless engine, so they live ONLY on
/// the `tui` subcommand (not the root, not global). This keeps them out of the
/// engine subcommands' help and, crucially, makes `openseek --prompt x run` a
/// clean error instead of a silent no-op. Bare `openseek` (which re-dispatches
/// through `tui`) still honors their env bindings; set them via `openseek tui …`.
pub fn tui_ui_options() -> Array[@argparse.OptionArg] {
  [
    OptionArg(
      "engine",
      long="engine",
      about="Agent engine to spawn (default: this openseek binary); reads its JSONL event stream from stdout.",
    ),
    OptionArg(
      "engine-mode",
      long="engine-mode",
      default_values=["serve"],
      about="Engine protocol: serve (one persistent, steerable process) or oneshot (spawn per prompt, for replay engines).",
    ),
    OptionArg(
      "prompt",
      long="prompt",
      about="Initial prompt to send once the UI opens.",
    ),
  ]
}

///|
/// The interactive UI's flags — UI-only, so not global (see `tui_ui_options`).
pub fn tui_ui_flags() -> Array[@argparse.FlagArg] {
  [
    FlagArg(
      "continue",
      long="continue",
      about="Resume the most recently active session in --session-root.",
    ),
  ]
}

///|
/// A standalone `tui` command with every UI option declared directly
/// (non-global), for unit tests that parse the UI in isolation. Production wires
/// the shared options onto the root as globals and gives the `tui` subcommand only
/// the UI-only ones (see `cmd/openseek`).
fn cli_command() -> @argparse.Command {
  Command(
    "tui",
    about="OpenSeek terminal UI.",
    options=[..tui_shared_options(), ..tui_ui_options()],
    flags=tui_ui_flags(),
  )
}

///|
/// Whether `--continue` asked to resume the latest session. Rejects the
/// combination with an explicit `--session`: the flags give two different
/// answers to "which conversation", and silently preferring either would
/// surprise whoever typed the other.
fn continue_requested(matches : @argparse.Matches) -> Bool raise {
  let (continue_flag, session) = match matches {
    {
      flags: {
        "continue"? : Some(continue_flag)
        | (None with continue_flag = false),
        ..
      },
      values: {
        "session"? : Some([session, ..])
        | (Some([]) | None with session = ""),
        ..
      },
      ..
    } => (continue_flag, session.trim())
  }
  if continue_flag && !session.is_empty() {
    fail(
      "--continue resumes the latest session; it cannot be combined with --session",
    )
  }
  continue_flag
}

///|
/// Swap in the most recently active durable session for `--continue`. With an
/// empty store the generated fresh session stands: there is nothing to
/// continue, and starting a new conversation beats refusing to launch.
async fn with_latest_session(config : AppConfig) -> AppConfig {
  match @store.SessionStore(config.session_root).latest() {
    Some(id) => { ..config, session_id: id, }
    None => config
  }
}

///|
/// Session id for a TUI launch that did not pick one.
///
/// Conversation continuity is the TUI's default. The engine runs once per
/// prompt, so context only carries between prompts through the durable session
/// store — without a session, telling the assistant something and asking about
/// it in the next prompt would hit a fresh one-shot that never saw the first
/// message. The stamp format lives in `SessionId::generated`, shared with the
/// engine CLI's default recording.
fn generated_session_id(now_ms : Int64) -> @agent_session.SessionId {
  @agent_session.SessionId::generated(prefix="tui", now_ms~)
}

///|
fn parse_config(matches : @argparse.Matches) -> AppConfig raise {
  let (
    api_url_input,
    session_input,
    session_root_input,
    engine_input,
    engine_mode_input,
    model_input,
    thinking_input,
  ) = match matches {
    {
      values: {
        "api-url": [api_url, ..],
        "session"? : Some([session, ..])
        | (Some([]) | None with session = ""),
        "session-root": [session_root, ..],
        "engine"? : Some([engine, ..])
        | (Some([]) | None with engine = ""),
        "engine-mode"? : Some([engine_mode, ..])
        | (Some([]) | None with engine_mode = "serve"),
        "model": [model, ..],
        "thinking": [thinking, ..],
        ..
      },
      ..
    } => (api_url, session, session_root, engine, engine_mode, model, thinking)
    _ => fail("missing parsed TUI defaults")
  }
  let cwd = match @env.current_dir() {
    Some(cwd) => cwd
    None => "."
  }
  let explicit_session = match session_input.trim() {
    "" => None
    session => Some(@agent_session.SessionId("\{session}"))
  }
  let session_root_value = if explicit_session is Some(_) {
    let root = session_root_input.trim()
    guard !root.is_empty() else { fail("--session-root must not be empty") }
    "\{root}"
  } else {
    let root = session_root_input.trim().to_owned()
    if root.is_empty() {
      ".openseek"
    } else {
      root
    }
  }
  // An explicit --engine wins; otherwise re-launch this command as the engine
  // (see `default_engine`). Presence of a non-blank value, not a magic default
  // string, decides — which also gates oneshot below. A blank `--engine ""`
  // counts as unset rather than an empty command.
  let explicit_engine : String? = if engine_input.trim().is_empty() {
    None
  } else {
    Some(engine_input)
  }
  // `--engine-mode` is a UI-only option on the `tui` subcommand; a bare
  // `openseek` (no subcommand) never has it, so read it gracefully.
  let engine_mode = EngineMode::parse(engine_mode_input)
  // `oneshot` only makes sense for a custom/replay engine that cannot speak the
  // persistent `serve` protocol; re-launching ourselves in oneshot buys nothing
  // and loses steering/compaction, so require an explicit engine.
  if engine_mode is OneShot && explicit_engine is None {
    fail(
      "--engine-mode oneshot requires an explicit --engine (it is for replay/custom engines)",
    )
  }
  // Enforced here rather than via argparse `required`: see `tui_shared_options`.
  let model = @deepseek.Model::parse(model_input)
  guard model.api_key(matches.values) is Some(api_key) else {
    fail("an API key is required for \{model}: pass --api-key")
  }
  let (engine, engine_args_prefix) = match explicit_engine {
    Some(engine) => (engine, [])
    None => default_engine(@env.args())
  }
  {
    api_key,
    api_url: match api_url_input.trim() {
      "" => None
      url => Some("\{url}")
    },
    model,
    cwd,
    max_steps: match matches {
      { values: { "max-steps": [input, ..], .. }, .. } =>
        Some(@cli.parse_positive_int(input, "--max-steps"))
      _ => None
    },
    // Parsed eagerly so a typo fails at launch with a CLI error instead of
    // inside the first turn's engine run.
    thinking: @deepseek.ThinkingMode::parse(thinking_input),
    session_id: match explicit_session {
      Some(id) => id
      None => generated_session_id(@env.now().reinterpret_as_int64())
    },
    session_root: session_root_value,
    engine,
    engine_args_prefix,
    engine_mode,
  }
}

///|
/// The engine command when `--engine` is unset. A normal binary argv0 is
/// re-execed directly; a bare argv0 falls back to PATH lookup.
/// Moon's debug native `tcc -run` path is different: argv0 is the generated C
/// source and no sibling `.exe` is produced, so re-enter through the generated
/// TCC response file; it carries the include paths, defines, linked dylibs, and
/// `-run <source.c>`.
fn default_engine(args : ArrayView[String]) -> (String, Array[String]) {
  match args {
    [argv0, ..] if argv0.contains("/") || argv0.contains("\\") =>
      match moon_native_tcc_run_args(argv0) {
        Some(args_prefix) => ("tcc", args_prefix)
        None => (argv0, [])
      }
    _ => ("openseek", [])
  }
}

///|
fn moon_native_tcc_run_args(argv0 : String) -> Array[String]? {
  if argv0.strip_suffix(".c") is Some(stem) &&
    (argv0.contains("/_build/native/") || argv0.contains("\\_build\\native\\")) {
    Some(["@\{stem}.rspfile"])
  } else {
    None
  }
}

///|
/// The initial prompt to send when the UI opens, from `--prompt` (empty → none).
/// There is no free-form positional: a bare non-subcommand token is a typo the
/// top-level dispatcher rejects rather than silently treats as a prompt.
fn initial_task(matches : @argparse.Matches) -> String? {
  match matches {
    {
      values: {
        "prompt"? : Some([prompt, ..])
        | (Some([]) | None with prompt = ""),
        ..
      },
      ..
    } =>
      match prompt.trim() {
        "" => None
        prompt => Some("\{prompt}")
      }
  }
}

///|
async fn run_tui(config : AppConfig, initial : String?) -> Unit {
  // Commands only name and describe themselves.
  @ui.with_ui(
    config=Config(composer_max_rows=4, slash_commands=[
      SlashCommandSpec(name="exit", description="exit the TUI"),
      SlashCommandSpec(
        name="compact",
        description="summarize and compact the conversation",
      ),
      SlashCommandSpec(
        name="loop",
        description="recurring prompt: /loop [--max <n>] <interval> <prompt> | off | status | pause | resume",
      ),
      SlashCommandSpec(
        name="goal",
        description="standing goal: /goal | /goal set <text> | /goal clear",
      ),
    ]),
    ui => run_app(config, initial, ui),
  )
}

///|
async fn run_app(config : AppConfig, initial : String?, ui : @ui.Ui) -> Unit {
  let state = State::State(config)
  let messages = @async.Queue(kind=Unbounded)
  append_session_history(state, ui)
  // Name the session so the conversation is resumable later with
  // `--session <id>` — for generated ids this line is the only place the user
  // ever sees one.
  ui.append_item(
    Response("OpenSeek TUI ready · session \{config.session_id.value()}"),
  )
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
/// the running UI. We probe it once at startup with the configured engine command
/// plus `--help`, which is part of the engine contract: like `openseek`, any
/// `--engine` replacement must accept `--help` as a side-effect-free no-op that
/// exits 0 — it makes no API call, and its output is captured so it never reaches
/// the terminal. The engine is usable only if that probe spawns and exits 0;
/// `ENOENT`/`EACCES` (not found / not executable) or a non-zero exit both mean it
/// is not. Any other failure is unexpected and re-raised rather than mislabeled
/// as a bad engine.
async fn engine_command_launchable(
  engine : String,
  args_prefix : Array[String],
) -> Bool {
  try {
    let args = args_prefix.copy()
    args.push("--help")
    let (code, _) = @process.collect_output_merged(
      engine,
      args,
      inherit_env=true,
    )
    code == 0
  } catch {
    @os_error.OSError(_) as err if err.is_ENOENT() || err.is_EACCES() => false
    err => raise err
  }
}

///|
/// Run the interactive UI from already-parsed argparse `matches` — the top-level
/// `openseek` command (in `cmd/openseek`) owns parsing and dispatches here for
/// both the default (no subcommand) and the explicit `tui` subcommand.
pub async fn run(matches : @argparse.Matches) -> Unit {
  let mut config = parse_config(matches)
  if continue_requested(matches) {
    config = with_latest_session(config)
  }
  // Fail before the terminal UI takes over the screen if the engine is unusable,
  // rather than dropping the user into a UI that dies on the first task.
  if !engine_command_launchable(config.engine, config.engine_args_prefix) {
    println(
      "error: engine '\{config.engine_display()}' is not usable: it must be on PATH, executable, and accept `--help` (exit 0) the way openseek does.",
    )
    println("Pass --engine <path> or install the openseek binary.")
    @sys.exit(1)
  }
  // The UI takes over the terminal, so refuse when stdin/stdout is not a TTY (a
  // pipe, CI log, or cron) — otherwise it would garble a non-interactive stream.
  // Checked after parsing and the engine probe so `--help`, argument errors, and
  // the engine-usability error still surface when piped.
  guard is_tty(@stdio.stdin) && is_tty(@stdio.stdout) else {
    // To stderr: this guard exists precisely to keep a piped/redirected stdout
    // clean, so the diagnostic must not land on it.
    @stdio.stderr.write(
      "error: the interactive UI needs a terminal; run a headless task with `openseek run \"…\"` (or `openseek serve` for the JSONL protocol).\n",
    ) catch {
      _ => ()
    }
    @sys.exit(1)
  }
  run_tui(config, initial_task(matches))
}

///|
/// Whether `fd` is an interactive terminal; a probe error counts as "not a TTY"
/// so a missing capability degrades to the headless guidance rather than crashes.
fn[T : @tty.Fd] is_tty(fd : T) -> Bool {
  @tty.isatty(fd) catch {
    _ => false
  }
}

///|
test "cli accepts no initial task" {
  let parsed = cli_command().parse(argv=[], env={ "DEEPSEEK": "test-key" })
  assert_true(initial_task(parsed) is None)
  let config = parse_config(parsed)
  assert_eq(config.api_key, "test-key")
  assert_true(config.api_url is None)
  assert_true(config.max_steps is None)
  // With no --engine, the engine falls through to re-launching this command
  // (`default_engine` of the process args), not a hardcoded string.
  let (expected_engine, expected_prefix) = default_engine(@env.args())
  assert_eq(config.engine, expected_engine)
  @debug.assert_eq(config.engine_args_prefix, expected_prefix)
  // No --session still converses in a session: a generated per-launch id, so
  // consecutive prompts share context instead of running amnesiac one-shots.
  assert_true(config.session_id.value().has_prefix("tui-"))
  assert_eq(config.session_root, ".openseek")
}

///|
test "cli parses api url" {
  let parsed = cli_command().parse(argv=[], env={
    "DEEPSEEK": "test-key",
    "OPENSEEK_API_URL": " https://proxy.example/v1/chat/completions ",
  })
  guard parse_config(parsed).api_url is Some(url) else {
    fail("expected api url")
  }
  assert_eq(url, "https://proxy.example/v1/chat/completions")
}

///|
test "cli uses provider API keys only for their models" {
  let kimi = cli_command().parse(argv=[], env={
    "KIMI": "kimi-key",
    "OPENSEEK_MODEL": "kimi-k2.7-code-highspeed",
  })
  let kimi_config = parse_config(kimi)
  assert_eq(kimi_config.api_key, "kimi-key")
  assert_true(kimi_config.model is Kimi(K27CodeHighSpeed))
  let glm = cli_command().parse(argv=[], env={
    "GLM": "glm-key",
    "OPENSEEK_MODEL": "glm-5.3",
  })
  let glm_config = parse_config(glm)
  assert_eq(glm_config.api_key, "glm-key")
  assert_true(glm_config.model is Glm(G53))
  // Provider keys do not fall back across models: `Model::api_key` returns
  // `None` and this main is the one that turns that into a failure.
  let deepseek = cli_command().parse(argv=[], env={
    "KIMI": "kimi-key",
    "GLM": "glm-key",
  })
  let _ = parse_config(deepseek) catch {
    error => {
      assert_true("\{error}".contains("an API key is required"))
      return
    }
  }
  fail("a non-DeepSeek key was accepted for a DeepSeek model")
}

///|
test "generated session ids are timestamped and directory-safe" {
  assert_eq(generated_session_id(0).value(), "tui-19700101-000000-000")
  assert_eq(generated_session_id(86_399_999).value(), "tui-19700101-235959-999")
  // 2026-06-10T03:14:07.089Z
  assert_eq(
    generated_session_id(1_781_061_247_089).value(),
    "tui-20260610-031407-089",
  )
}

///|
test "cli parses and validates thinking controls" {
  let parsed = cli_command().parse(argv=["--thinking", "high"], env={
    "DEEPSEEK": "test-key",
  })
  let config = parse_config(parsed)
  assert_true(config.thinking is High)
  let bad = cli_command().parse(argv=["--thinking", "sometimes"], env={
    "DEEPSEEK": "test-key",
  })
  let _ = parse_config(bad) catch {
    error => {
      assert_true("\{error}".contains("unknown thinking mode"))
      return
    }
  }
  fail("invalid thinking mode accepted")
}

///|
test "cli accepts an initial prompt and max steps" {
  let parsed = cli_command().parse(
    argv=["--max-steps", "5", "--prompt", "inspect project"],
    env={ "DEEPSEEK": "test-key" },
  )
  assert_true(initial_task(parsed) == Some("inspect project"))
  assert_true(parse_config(parsed).max_steps is Some(5))
}

///|
test "cli rejects unknown option before initial task" {
  let _ = cli_command().parse(argv=["--xxy", "he"], env={
    "DEEPSEEK": "test-key",
  }) catch {
    error => {
      assert_true("\{error}".contains("unexpected argument '--xxy' found"))
      return
    }
  }
  fail("unknown option accepted as initial task")
}

///|
test "no --prompt means no initial task" {
  let parsed = cli_command().parse(argv=[], env={ "DEEPSEEK": "test-key" })
  assert_true(initial_task(parsed) is None)
}

///|
test "cli accepts session configuration" {
  let parsed = cli_command().parse(
    argv=["--session", "demo", "--session-root", "/tmp/openseek-sessions"],
    env={ "DEEPSEEK": "test-key" },
  )
  let config = parse_config(parsed)
  assert_eq(config.session_id.value(), "demo")
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
test "cli accepts --continue and rejects combining it with --session" {
  let parsed = cli_command().parse(argv=["--continue"], env={
    "DEEPSEEK": "test-key",
  })
  assert_true(continue_requested(parsed))
  let conflicted = cli_command().parse(
    argv=["--continue", "--session", "demo"],
    env={ "DEEPSEEK": "test-key" },
  )
  let _ = continue_requested(conflicted) catch {
    error => {
      assert_true("\{error}".contains("cannot be combined with --session"))
      return
    }
  }
  fail("--continue with --session accepted")
}

///|
test "default_engine re-launches a path argv0 and falls back to PATH otherwise" {
  @debug.assert_eq(
    default_engine(["/usr/local/bin/openseek"]),
    ("/usr/local/bin/openseek", []),
  )
  @debug.assert_eq(default_engine(["./openseek"]), ("./openseek", []))
  @debug.assert_eq(default_engine(["src/openseek.c"]), ("src/openseek.c", []))
  @debug.assert_eq(
    default_engine(["target/native/openseek"]),
    ("target/native/openseek", []),
  )
  @debug.assert_eq(
    default_engine(["target\\native\\openseek.exe"]),
    ("target\\native\\openseek.exe", []),
  )
  @debug.assert_eq(
    default_engine([
      "/repo/_build/native/debug/build/bobzhang/openseek/cmd/openseek/openseek.c",
    ]),
    (
      "tcc",
      [
        "@/repo/_build/native/debug/build/bobzhang/openseek/cmd/openseek/openseek.rspfile",
      ],
    ),
  )
  @debug.assert_eq(
    default_engine([
      "C:\\repo\\_build\\native\\debug\\build\\bobzhang\\openseek\\cmd\\openseek\\openseek.c",
    ]),
    (
      "tcc",
      [
        "@C:\\repo\\_build\\native\\debug\\build\\bobzhang\\openseek\\cmd\\openseek\\openseek.rspfile",
      ],
    ),
  )
  @debug.assert_eq(default_engine(["openseek"]), ("openseek", []))
  @debug.assert_eq(default_engine([]), ("openseek", []))
}

///|
async test "engine defaults to this binary; --engine overrides it" {
  // No --engine: fall through to re-launching this binary.
  let default_cfg = parse_config(
    cli_command().parse(argv=[], env={ "DEEPSEEK": "k" }),
  )
  let (expected_engine, expected_prefix) = default_engine(@env.args())
  assert_eq(default_cfg.engine, expected_engine)
  @debug.assert_eq(default_cfg.engine_args_prefix, expected_prefix)
}

///|
async test "oneshot engine mode requires an explicit engine" {
  let _ = parse_config(
    cli_command().parse(argv=["--engine-mode", "oneshot"], env={
      "DEEPSEEK": "k",
    }),
  ) catch {
    error => {
      assert_true("\{error}".contains("oneshot requires an explicit"))
      return
    }
  }
  fail("oneshot without an explicit engine was accepted")
}

///|
async test "oneshot with an explicit engine is accepted" {
  let flag_cfg = parse_config(
    cli_command().parse(
      argv=["--engine-mode", "oneshot", "--engine", "./fake-engine"],
      env={ "DEEPSEEK": "k" },
    ),
  )
  assert_true(flag_cfg.engine_mode is OneShot)
  assert_eq(flag_cfg.engine, "./fake-engine")
  @debug.assert_eq(flag_cfg.engine_args_prefix, [])
}

///|
test "cli overrides the engine binary" {
  let parsed = cli_command().parse(argv=["--engine", "./fake-engine"], env={
    "DEEPSEEK": "test-key",
  })
  let config = parse_config(parsed)
  assert_eq(config.engine, "./fake-engine")
  @debug.assert_eq(config.engine_args_prefix, [])
}

///|
async test "engine_launchable rejects a binary that cannot be exec'd" {
  assert_false(engine_command_launchable("openseek-not-a-real-binary-xyz", []))
}

///|
async test "engine_launchable accepts an engine whose --help exits 0" {
  // `moon` stands in for an engine that honors the `--help` no-op the probe
  // requires: `moon --help` exits 0 and, unlike `true`, `moon` is on PATH on
  // every platform the tests run on (including Windows native), so this stays
  // cross-platform.
  assert_true(engine_command_launchable("moon", []))
}
