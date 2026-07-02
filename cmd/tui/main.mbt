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
      env="DEEPSEEK",
      default_values=[""],
      global~,
      about="DeepSeek API key.",
    ),
    OptionArg(
      "model",
      long="model",
      env="DEEPSEEK_MODEL",
      default_values=[@deepseek.V4Pro.to_string()],
      global~,
      about="DeepSeek model: deepseek-v4-flash or deepseek-v4-pro.",
    ),
    OptionArg(
      "api-url",
      long="api-url",
      env="OPENSEEK_API_URL",
      default_values=[""],
      global~,
      about="DeepSeek-compatible chat completions endpoint.",
    ),
    OptionArg(
      "max-steps",
      long="max-steps",
      env="OPENSEEK_MAX_STEPS",
      default_values=["1000"],
      global~,
      about="Maximum number of agent loop steps before stopping.",
    ),
    OptionArg(
      "thinking",
      long="thinking",
      env="OPENSEEK_THINKING",
      default_values=["max"],
      global~,
      about="DeepSeek thinking mode: no, high, or max.",
    ),
    OptionArg(
      "session",
      long="session",
      env="OPENSEEK_SESSION",
      global~,
      about="Create or resume this durable session id.",
    ),
    OptionArg(
      "session-root",
      long="session-root",
      env="OPENSEEK_SESSION_ROOT",
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
      env="OPENSEEK_ENGINE",
      about="Agent engine to spawn (default: this openseek binary); reads its JSONL event stream from stdout.",
    ),
    OptionArg(
      "engine-mode",
      long="engine-mode",
      env="OPENSEEK_ENGINE_MODE",
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
pub fn cli_command() -> @argparse.Command {
  Command(
    "tui",
    about="OpenSeek terminal UI.",
    options=[..tui_shared_options(), ..tui_ui_options()],
    flags=tui_ui_flags(),
  )
}

///|
fn flag(matches : @argparse.Matches, name : String) -> Bool {
  matches.flags.get(name) is Some(true)
}

///|
/// Whether `--continue` asked to resume the latest session. Rejects the
/// combination with an explicit `--session`: the flags give two different
/// answers to "which conversation", and silently preferring either would
/// surprise whoever typed the other.
fn continue_requested(matches : @argparse.Matches) -> Bool raise {
  let continue_flag = flag(matches, "continue")
  if continue_flag && session_id(matches) is Some(_) {
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
    Some(id) => { ..config, session_id: id }
    None => config
  }
}

///|
fn value(matches : @argparse.Matches, name : String) -> String raise {
  match matches.values.get(name) {
    Some([value, ..]) => value
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
fn api_url(matches : @argparse.Matches) -> String? raise {
  let url = value(matches, "api-url").trim().to_owned()
  if url.is_empty() {
    None
  } else {
    Some(url)
  }
}

///|
fn session_id(matches : @argparse.Matches) -> @agent_session.SessionId? {
  let session = match values(matches, "session") {
    [session, ..] => "\{session.trim()}"
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
  let cwd = match @env.current_dir() {
    Some(cwd) => cwd
    None => "."
  }
  let explicit_session = session_id(matches)
  let session_root_value = if explicit_session is Some(_) {
    session_root(matches)
  } else {
    let root = value(matches, "session-root").trim().to_owned()
    if root.is_empty() {
      ".openseek"
    } else {
      root
    }
  }
  // An explicit --engine / OPENSEEK_ENGINE wins; otherwise re-launch this binary
  // as the engine (see `default_engine`). Presence of a non-blank value, not a
  // magic default string, decides — which also gates oneshot below. A blank
  // `--engine ""` counts as unset rather than an empty command.
  let explicit_engine : String? = match values(matches, "engine") {
    [engine, ..] if !engine.trim().is_empty() => Some(engine)
    _ => None
  }
  // `--engine-mode` is a UI-only option on the `tui` subcommand; a bare
  // `openseek` (no subcommand) never has it, so read it gracefully.
  let engine_mode = EngineMode::parse(
    match values(matches, "engine-mode") {
      [mode, ..] => mode
      [] => "serve"
    },
  )
  // `oneshot` only makes sense for a custom/replay engine that cannot speak the
  // persistent `serve` protocol; re-launching ourselves in oneshot buys nothing
  // and loses steering/compaction, so require an explicit engine.
  if engine_mode is OneShot && explicit_engine is None {
    fail(
      "--engine-mode oneshot requires an explicit --engine / OPENSEEK_ENGINE (it is for replay/custom engines)",
    )
  }
  // Enforced here rather than via argparse `required`: see `tui_shared_options`.
  let api_key = value(matches, "api-key")
  if api_key.trim().is_empty() {
    fail("a DeepSeek API key is required: pass --api-key or set DEEPSEEK")
  }
  {
    api_key,
    api_url: api_url(matches),
    model: @deepseek.Model::parse(value(matches, "model")),
    cwd,
    max_steps: parse_positive_int(value(matches, "max-steps"), "--max-steps"),
    // Parsed eagerly so a typo fails at launch with a CLI error instead of
    // inside the first turn's engine run.
    thinking: @deepseek.ThinkingMode::parse(value(matches, "thinking")),
    session_id: match explicit_session {
      Some(id) => id
      None => generated_session_id(@env.now().reinterpret_as_int64())
    },
    session_root: session_root_value,
    engine: match explicit_engine {
      Some(engine) => engine
      None => default_engine(@sys.get_cli_args())
    },
    engine_mode,
  }
}

///|
/// The engine command when `--engine`/`OPENSEEK_ENGINE` is unset: re-launch *this*
/// executable so `openseek tui` never spawns a separately-installed, stale engine.
/// `args[0]` (argv0) with a path separator (`/` or, on Windows, `\`) is used
/// directly — spawn resolves it against the launch cwd (which the UI never
/// changes) — so `./openseek` or an absolute path re-execs the same file; a bare
/// name is left as `openseek` for a PATH lookup, which for a single binary is the
/// same file. Split out so it is unit-testable without a real argv0.
fn default_engine(args : ArrayView[String]) -> String {
  match args {
    [argv0, ..] if argv0.contains("/") || argv0.contains("\\") => argv0
    _ => "openseek"
  }
}

///|
/// The initial prompt to send when the UI opens, from `--prompt` (empty → none).
/// There is no free-form positional: a bare non-subcommand token is a typo the
/// top-level dispatcher rejects rather than silently treats as a prompt.
fn initial_task(matches : @argparse.Matches) -> String? {
  match values(matches, "prompt") {
    [prompt, ..] if !prompt.trim().is_empty() => Some(prompt.trim().to_owned())
    _ => None
  }
}

///|
async fn run_tui(config : AppConfig, initial : String?) -> Unit {
  // Commands only name and describe themselves.
  @ui.with_ui(
    config=@ui.Config::new(composer_max_rows=4, slash_commands=[
      @ui.SlashCommandSpec::new(name="exit", description="exit the TUI"),
      @ui.SlashCommandSpec::new(
        name="compact",
        description="summarize and compact the conversation",
      ),
      @ui.SlashCommandSpec::new(
        name="skills",
        description="list and insert a skill",
      ),
    ]),
    ui => run_app(config, initial, ui),
  )
}

///|
async fn run_app(config : AppConfig, initial : String?, ui : @ui.Ui) -> Unit {
  let state = State::new(config)
  let messages = @async.Queue(kind=Unbounded)
  append_session_history(state.config, ui)
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
  if !engine_launchable(config.engine) {
    println(
      "error: engine '\{config.engine}' is not usable: it must be on PATH, executable, and accept `--help` (exit 0) the way openseek does.",
    )
    println(
      "Pass --engine <path>, set OPENSEEK_ENGINE, or install the openseek binary.",
    )
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
  assert_eq(config.max_steps, 1000)
  // With no --engine, the engine falls through to re-launching this binary
  // (`default_engine` of the process args), not a hardcoded string.
  assert_eq(config.engine, default_engine(@sys.get_cli_args()))
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
  assert_eq(parse_config(parsed).max_steps, 5)
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
  assert_eq(
    default_engine(["/usr/local/bin/openseek"]),
    "/usr/local/bin/openseek",
  )
  assert_eq(default_engine(["./openseek"]), "./openseek")
  assert_eq(
    default_engine(["target/native/openseek"]),
    "target/native/openseek",
  )
  assert_eq(
    default_engine(["target\\native\\openseek.exe"]),
    "target\\native\\openseek.exe",
  )
  assert_eq(default_engine(["openseek"]), "openseek")
  assert_eq(default_engine([]), "openseek")
}

///|
async test "engine defaults to this binary; --engine/OPENSEEK_ENGINE override it" {
  // No --engine and no env: fall through to re-launching this binary.
  let default_cfg = parse_config(
    cli_command().parse(argv=[], env={ "DEEPSEEK": "k" }),
  )
  assert_eq(default_cfg.engine, default_engine(@sys.get_cli_args()))
  // OPENSEEK_ENGINE is treated as an explicit engine.
  let env_cfg = parse_config(
    cli_command().parse(argv=[], env={
      "DEEPSEEK": "k",
      "OPENSEEK_ENGINE": "./fake-engine",
    }),
  )
  assert_eq(env_cfg.engine, "./fake-engine")
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
async test "oneshot with an explicit engine (flag or env) is accepted" {
  let flag_cfg = parse_config(
    cli_command().parse(
      argv=["--engine-mode", "oneshot", "--engine", "./fake-engine"],
      env={ "DEEPSEEK": "k" },
    ),
  )
  assert_true(flag_cfg.engine_mode is OneShot)
  assert_eq(flag_cfg.engine, "./fake-engine")
  let env_cfg = parse_config(
    cli_command().parse(argv=[], env={
      "DEEPSEEK": "k",
      "OPENSEEK_ENGINE": "./fake-engine",
      "OPENSEEK_ENGINE_MODE": "oneshot",
    }),
  )
  assert_true(env_cfg.engine_mode is OneShot)
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
