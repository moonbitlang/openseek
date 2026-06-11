///|
async fn main {
  run_cli() catch {
    error => {
      @stdio.stderr.write("error: \{failure_message("\{error}")}\n") catch {
        _ => ()
      }
      @sys.exit(1)
    }
  }
}

///|
async fn run_cli() -> Unit {
  let stdout_log = configure_logging()
  @async.with_task_group(group => {
    // The drain owns all stdout JSONL writes for the run. It is spawned
    // without `no_wait`, so the group only completes once the queue — closed
    // by the `defer` when this body exits, on success and error alike — has
    // been written out in full; the terminal event is never lost to an early
    // process exit.
    group.spawn_bg() <| () => { stdout_log.drain() }
    defer stdout_log.close()
    let matches = cli_command().parse(env=@env.get_env_vars())
    if handle_session_command(matches) {
      return
    }
    if flag(matches, "serve") {
      if values(matches, "task").length() > 0 {
        fail("--serve reads commands from stdin; it does not take a task")
      }
      run_serve(matches)
      return
    }
    let api_key = api_key(matches)
    let api_url = api_url(matches)
    let model = @deepseek.Model::parse(value(matches, "model"))
    let max_steps = max_steps(matches)
    let thinking = @deepseek.ThinkingMode::parse(value(matches, "thinking"))
    let reasoning_effort = @deepseek.ReasoningEffort::parse(
      value(matches, "reasoning-effort"),
    )
    let task = task_text(matches)
    match session_id(matches) {
      None => {
        let system_prompt_text = configured_system_prompt(matches, model)
        @agent.run(
          api_key,
          model,
          task,
          max_steps~,
          system_prompt_text~,
          thinking~,
          reasoning_effort~,
          api_url?,
        )
      }
      Some(id) => {
        let store = @store.SessionStore(session_root(matches))
        let session = load_or_new_session(store, id, matches, model)
        ignore(
          @agent.run_turn_with_append(
            api_key,
            model,
            session,
            task,
            append_item=(session, item) => store.append(session, item),
            max_steps~,
            thinking~,
            reasoning_effort~,
            api_url?,
          ),
        )
      }
    }
  })
}

///|
fn failure_message(error_text : String) -> String {
  let marker = " FAILED: "
  let pieces : Array[String] = error_text
    .split(marker)
    .map(piece => piece.to_owned())
    .collect()
  if pieces.length() < 2 {
    return error_text
  }
  let message = pieces[pieces.length() - 1]
  if message.has_suffix(")") {
    message[:message.length() - 1].to_owned()
  } else {
    message
  }
}

///|
fn cli_command() -> @argparse.Command {
  Command(
    "openseek",
    about="DeepSeek-backed MoonBit coding agent.",
    options=[
      OptionArg(
        "api-key",
        long="api-key",
        env="DEEPSEEK",
        default_values=[""],
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
        "api-url",
        long="api-url",
        env="OPENSEEK_API_URL",
        default_values=[""],
        about="DeepSeek-compatible chat completions endpoint.",
      ),
      OptionArg(
        "max-steps",
        long="max-steps",
        env="OPENSEEK_MAX_STEPS",
        default_values=["1000"],
        about="Maximum number of agent loop steps before stopping.",
      ),
      OptionArg(
        "thinking",
        long="thinking",
        env="OPENSEEK_THINKING",
        default_values=["enabled"],
        about="DeepSeek thinking mode: enabled or disabled.",
      ),
      OptionArg(
        "reasoning-effort",
        long="reasoning-effort",
        env="OPENSEEK_REASONING_EFFORT",
        default_values=["max"],
        about="DeepSeek reasoning effort in thinking mode: high or max.",
      ),
      OptionArg(
        "system-prompt-file",
        long="system-prompt-file",
        env="OPENSEEK_SYSTEM_PROMPT_FILE",
        default_values=[""],
        about="Read the complete system prompt from this file instead of the built-in prompt.",
      ),
      OptionArg(
        "system-prompt-addendum-file",
        long="system-prompt-addendum-file",
        env="OPENSEEK_SYSTEM_PROMPT_ADDENDUM_FILE",
        default_values=[""],
        about="Append this file to the selected system prompt for prompt experiments.",
      ),
      OptionArg(
        "session",
        long="session",
        env="OPENSEEK_SESSION",
        default_values=[""],
        about="Create or resume this durable session id.",
      ),
      OptionArg(
        "session-root",
        long="session-root",
        env="OPENSEEK_SESSION_ROOT",
        default_values=[".openseek"],
        about="Directory containing durable OpenSeek sessions.",
      ),
      OptionArg(
        "session-compact-file",
        long="session-compact-file",
        default_values=[""],
        about="Read summary text from this file, append it to --session, and exit.",
      ),
      OptionArg(
        "session-compact-from",
        long="session-compact-from",
        default_values=[""],
        about="First event sequence covered by --session-compact-file.",
      ),
      OptionArg(
        "session-compact-to",
        long="session-compact-to",
        default_values=[""],
        about="Last event sequence covered by --session-compact-file.",
      ),
    ],
    flags=[
      FlagArg(
        "serve",
        long="serve",
        about="Run as a session server: read JSONL commands (prompt/steer/cancel) from stdin.",
      ),
      FlagArg(
        "session-list",
        long="session-list",
        about="List durable session ids and exit.",
      ),
      FlagArg(
        "session-show",
        long="session-show",
        about="Print the durable session JSON for --session and exit.",
      ),
    ],
    positionals=[
      PositionArg(
        "task",
        num_args=ValueRange(lower=0),
        allow_hyphen_values=true,
        about="Task description.",
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
fn flag(matches : @argparse.Matches, name : String) -> Bool {
  match matches.flags.get(name) {
    Some(value) => value
    None => false
  }
}

///|
fn api_key(matches : @argparse.Matches) -> String raise {
  let key = value(matches, "api-key").trim().to_owned()
  if key.is_empty() {
    fail("--api-key or DEEPSEEK is required for agent runs")
  }
  key
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
fn max_steps(matches : @argparse.Matches) -> Int raise {
  parse_positive_int(value(matches, "max-steps"), "--max-steps")
}

///|
fn task_text(matches : @argparse.Matches) -> String raise {
  let task = values(matches, "task").join(" ").trim().to_owned()
  if task.is_empty() {
    fail("task description is required for agent runs")
  }
  task
}

///|
fn session_id(matches : @argparse.Matches) -> @agent_session.SessionId? raise {
  let id = value(matches, "session").trim().to_owned()
  if id.is_empty() {
    None
  } else {
    Some(SessionId(id))
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
/// Longest first-prompt label a `--session-list` row carries; enough to
/// recognize a conversation without wrapping a normal terminal row.
const PromptLabelMaxChars : Int = 60

///|
/// Collapse a prompt to a single-line label: whitespace runs become one
/// space, remaining control characters are dropped — a stored prompt must
/// not be able to inject terminal escape sequences into the listing — and
/// anything beyond `PromptLabelMaxChars` is elided with `…`. A session
/// without a recorded prompt shows `-` so the column never vanishes.
fn compact_prompt_label(prompt : String) -> String {
  let out = StringBuilder::new()
  let mut last_was_space = false
  let mut count = 0
  for ch in prompt.trim() {
    if count >= PromptLabelMaxChars {
      out.write_char('…')
      break
    }
    if ch is (' ' | '\t' | '\n' | '\r') {
      if !last_was_space {
        out.write_char(' ')
        count += 1
      }
      last_was_space = true
    } else if ch.to_int() < 0x20 ||
      ch.to_int() == 0x7F ||
      (ch.to_int() >= 0x80 && ch.to_int() <= 0x9F) {
      // C0/C1 controls and DEL: ESC, CSI, OSC and friends render as terminal
      // commands, not text.
      continue
    } else {
      out.write_char(ch)
      count += 1
      last_was_space = false
    }
  }
  let label = out.to_string()
  if label.is_empty() {
    "-"
  } else {
    label
  }
}

///|
fn format_utc_minute(seconds : Int64) -> String {
  fn pad2(value : Int) -> String {
    if value < 10 {
      "0\{value}"
    } else {
      "\{value}"
    }
  }

  let time = @time.unix(seconds) catch { _ => return "-" }
  "\{time.year()}-\{pad2(time.month())}-\{pad2(time.day())} \{pad2(time.hour())}:\{pad2(time.minute())}"
}

///|
/// One `--session-list` row: tab-separated id, last-activity stamp (UTC,
/// minute precision; `-` for an unreadable session), and the first user
/// prompt as a one-line label. Tab separation keeps the listing scriptable —
/// `--session-list | cut -f1` recovers the bare ids the old format printed.
fn format_session_listing(listing : @store.SessionListing) -> String {
  let when = match listing.last_active_unix_seconds() {
    Some(seconds) => format_utc_minute(seconds)
    None => "-"
  }
  "\{listing.id().value()}\t\{when}\t\{compact_prompt_label(listing.first_prompt())}"
}

///|
async fn handle_session_command(matches : @argparse.Matches) -> Bool {
  let list_sessions = flag(matches, "session-list")
  let show_session = flag(matches, "session-show")
  let compact_file = value(matches, "session-compact-file").trim().to_owned()
  let compact_from = value(matches, "session-compact-from").trim().to_owned()
  let compact_to = value(matches, "session-compact-to").trim().to_owned()
  let compact_session = !compact_file.is_empty() ||
    !compact_from.is_empty() ||
    !compact_to.is_empty()
  let command_count = (if list_sessions { 1 } else { 0 }) +
    (if show_session { 1 } else { 0 }) +
    (if compact_session { 1 } else { 0 })
  if command_count == 0 {
    return false
  }
  if command_count > 1 {
    fail(
      "choose only one of --session-list, --session-show, or --session-compact-file",
    )
  }
  let store = @store.SessionStore(session_root(matches))
  if list_sessions {
    for listing in store.listings() {
      println(format_session_listing(listing))
    }
    return true
  }
  let id = required_session_id(matches)
  if show_session {
    println(store.load(id).to_json().stringify())
    return true
  }
  if compact_file.is_empty() {
    fail("--session-compact-file is required for session compaction")
  }
  let from_sequence = required_positive_int(
    compact_from, "--session-compact-from",
  )
  let to_sequence = required_positive_int(compact_to, "--session-compact-to")
  let summary = @fs.read_file(compact_file).text()
  let compacted = store.compact(
    store.load(id),
    content=summary,
    from_sequence~,
    to_sequence~,
  )
  println(
    "compacted session \{id.value()} events \{from_sequence}..\{to_sequence}; last_sequence=\{compacted.last_sequence()}",
  )
  true
}

///|
fn required_session_id(
  matches : @argparse.Matches,
) -> @agent_session.SessionId raise {
  match session_id(matches) {
    Some(id) => id
    None => fail("--session is required for this session management command")
  }
}

///|
async fn load_or_new_session(
  store : @store.SessionStore,
  id : @agent_session.SessionId,
  matches : @argparse.Matches,
  model : @deepseek.Model,
) -> @agent_session.Session {
  if store.exists(id) {
    store.load(id) catch {
      @os_error.OSError(_) as error if error.is_ENOENT() =>
        Session(id, system_prompt=configured_system_prompt(matches, model))
      error => raise error
    }
  } else {
    Session(id, system_prompt=configured_system_prompt(matches, model))
  }
}

///|
async fn configured_system_prompt(
  matches : @argparse.Matches,
  model : @deepseek.Model,
) -> String {
  let base_path = value(matches, "system-prompt-file")
  let addendum_path = value(matches, "system-prompt-addendum-file")
  let base = if base_path == "" {
    @prompt.system_prompt_for_model(model)
  } else {
    @fs.read_file(base_path).text()
  }
  // The environment section goes LAST: DeepSeek's context cache matches on
  // request prefixes, and the cwd is the only per-project variable in the
  // prompt. Base and addendum are byte-identical across projects (and across
  // an eval harness's N concurrent trial workspaces testing one addendum),
  // so ordering them first keeps the whole shared text cache-hittable; the
  // end position also gives the grounding instruction recency weight.
  let with_addendum = if addendum_path == "" {
    base
  } else {
    let addendum = @fs.read_file(addendum_path).text()
    (
      $|\{base}
      $|
      $|\{addendum}
    )
  }
  (
    $|\{with_addendum}
    $|
    $|\{environment_prompt_section()}
  )
}

///|
/// The runtime environment block appended to every system prompt — including
/// a `--system-prompt-file` override, since grounding describes the process,
/// not the prompt content. Without it the model has no idea where it is and
/// guesses: in a five-run benchmark batch one agent passed
/// `cwd="/workspace"` on its very first call, then explored the parent
/// directory, found a concurrent sibling run's files, and adopted that
/// workspace wholesale. A durable session stores the prompt at creation, so
/// the recorded directory is where the session was started — resume it from
/// the same project root.
async fn environment_prompt_section() -> String {
  let cwd = @fs.realpath(".") catch { _ => "." }
  (
    $|## Environment
    $|
    $|Working directory: \{cwd}
    $|Relative paths resolve against it; treat it as the workspace root and stay inside it. Parent and sibling directories belong to other projects. Never pass a cwd you have not verified exists.
  )
}

///|
async test "environment section names the real working directory" {
  let section = environment_prompt_section()
  let cwd = @fs.realpath(".")
  assert_true(section.contains("Working directory: \{cwd}"))
  assert_true(section.contains("stay inside it"))
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
fn required_positive_int(input : String, label : String) -> Int raise {
  let trimmed = input.trim().to_owned()
  if trimmed.is_empty() {
    fail("\{label} is required")
  }
  parse_positive_int(trimmed, label)
}

///|
test "session listing rows are tab-separated and survive odd prompts" {
  assert_eq(
    compact_prompt_label("  fix the \n\t streaming   bug  "),
    "fix the streaming bug",
  )
  assert_eq(compact_prompt_label(""), "-")
  // Control characters cannot smuggle escape sequences into the listing:
  // ESC, BEL, and the C1 CSI all vanish while printable text survives.
  assert_eq(
    compact_prompt_label("\u{1b}[31mred\u{1b}]0;title\u{7}\u{9b}31m text"),
    "[31mred]0;title31m text",
  )
  let long = String::make(100, 'x')
  let label = compact_prompt_label(long)
  assert_true(label.has_suffix("…"))
  // 2026-06-10T03:14:07Z renders at minute precision.
  assert_eq(format_utc_minute(1_781_061_247), "2026-06-10 03:14")
}

///|
test "cli parses env backed options and task" {
  let parsed = cli_command().parse(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
    "DEEPSEEK_MODEL": "deepseek-v4-pro",
    "OPENSEEK_API_URL": "https://proxy.example/v1/chat/completions",
    "OPENSEEK_MAX_STEPS": "120",
    "OPENSEEK_SYSTEM_PROMPT_FILE": "/tmp/prompt-a.md",
    "OPENSEEK_SYSTEM_PROMPT_ADDENDUM_FILE": "/tmp/prompt-b.md",
    "OPENSEEK_SESSION": "demo",
    "OPENSEEK_SESSION_ROOT": "/tmp/openseek-sessions",
  })
  assert_eq(api_key(parsed), "test-key")
  assert_eq(value(parsed, "model"), "deepseek-v4-pro")
  guard api_url(parsed) is Some(url) else { fail("expected api url") }
  assert_eq(url, "https://proxy.example/v1/chat/completions")
  assert_eq(max_steps(parsed), 120)
  assert_eq(value(parsed, "system-prompt-file"), "/tmp/prompt-a.md")
  assert_eq(value(parsed, "system-prompt-addendum-file"), "/tmp/prompt-b.md")
  guard session_id(parsed) is Some(id) else { fail("expected session id") }
  assert_eq(id.value(), "demo")
  assert_eq(session_root(parsed), "/tmp/openseek-sessions")
  assert_eq(task_text(parsed), "write MoonBit")
}

///|
test "cli defaults model and max steps" {
  let parsed = cli_command().parse(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  assert_eq(api_key(parsed), "test-key")
  assert_eq(value(parsed, "model"), "deepseek-v4-pro")
  assert_true(api_url(parsed) is None)
  assert_eq(max_steps(parsed), 1000)
  assert_true(session_id(parsed) is None)
  assert_eq(session_root(parsed), ".openseek")
}

///|
test "cli allows session management without api key or task" {
  let parsed = cli_command().parse(argv=["--session-list"], env={})
  assert_true(flag(parsed, "session-list"))
  assert_eq(value(parsed, "api-key"), "")
  assert_eq(values(parsed, "task").length(), 0)
}

///|
async test "session commands reject empty session root" {
  let parsed = cli_command().parse(
    argv=["--session-root", "", "--session-list"],
    env={},
  )
  let _ = handle_session_command(parsed) catch {
    error => {
      assert_true("\{error}".contains("--session-root"))
      return
    }
  }
  fail("empty session root accepted")
}

///|
test "agent runs require api key" {
  let parsed = cli_command().parse(argv=["write", "MoonBit"], env={})
  let _ = api_key(parsed) catch {
    error => {
      assert_true("\{error}".contains("--api-key or DEEPSEEK is required"))
      return
    }
  }
  fail("missing api key accepted")
}

///|
test "agent runs require task text" {
  let parsed = cli_command().parse(argv=[], env={ "DEEPSEEK": "test-key" })
  let _ = task_text(parsed) catch {
    error => {
      assert_true("\{error}".contains("task description is required"))
      return
    }
  }
  fail("missing task accepted")
}

///|
test "cli parses max steps option" {
  let parsed = cli_command().parse(
    argv=["--max-steps", "25", "write", "MoonBit"],
    env={ "DEEPSEEK": "test-key" },
  )
  assert_eq(max_steps(parsed), 25)
}

///|
async test "configured system prompt can replace and append files" {
  let dir = @fs.tmpdir(prefix="openseek-prompt-config-")
  let prompt_path = dir + "/prompt.md"
  let addendum_path = dir + "/addendum.md"
  @fs.write_file(prompt_path, "base prompt\n", create_mode=CreateOrTruncate)
  @fs.write_file(addendum_path, "addendum\n", create_mode=CreateOrTruncate)
  let parsed = cli_command().parse(
    argv=[
      "--system-prompt-file", prompt_path, "--system-prompt-addendum-file", addendum_path,
      "write", "MoonBit",
    ],
    env={ "DEEPSEEK": "test-key" },
  )
  // Environment last: base and addendum form the cache-shared prefix; the
  // per-project cwd is the only divergence point.
  assert_eq(
    configured_system_prompt(parsed, V4Flash),
    "base prompt\n\n\naddendum\n\n\n\{environment_prompt_section()}",
  )
  @fs.rmdir(dir, recursive=true)
}

///|
async test "configured system prompt defaults by model" {
  let parsed = cli_command().parse(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  assert_true(
    configured_system_prompt(parsed, V4Flash).contains("DeepSeek V4 Flash"),
  )
  assert_false(
    configured_system_prompt(parsed, V4Pro).contains("DeepSeek V4 Flash"),
  )
}

///|
async test "load_or_new_session defers first durable write until append" {
  let root = @fs.tmpdir(prefix="openseek-cli-session-")
  let store = @store.SessionStore(root)
  let id : @agent_session.SessionId = SessionId("cli-test")
  let prompt_path = root + "/prompt.md"
  @fs.write_file(prompt_path, "system", create_mode=CreateOrTruncate)
  let parsed = cli_command().parse(
    argv=[
      "--session-root", root, "--session", "cli-test", "--system-prompt-file", prompt_path,
      "write", "MoonBit",
    ],
    env={ "DEEPSEEK": "test-key" },
  )
  let created = load_or_new_session(store, id, parsed, V4Pro)
  let grounded_prompt = "system\n\n\{environment_prompt_section()}"
  assert_eq(created.system_prompt(), grounded_prompt)
  assert_eq(created.events().length(), 0)
  assert_false(store.exists(id))
  let with_event = store.append(created, User(UserMessage("hello")))
  assert_eq(with_event.events().length(), 1)
  @fs.remove(prompt_path)
  let loaded = load_or_new_session(store, id, parsed, V4Pro)
  assert_eq(loaded.system_prompt(), grounded_prompt)
  assert_eq(loaded.events().length(), 1)
  @fs.rmdir(root, recursive=true)
}

///|
async test "load_or_new_session recovers empty interrupted session directory" {
  let root = @fs.tmpdir(prefix="openseek-cli-session-empty-dir-")
  let id : @agent_session.SessionId = SessionId("cli-test")
  @fs.mkdir(root + "/sessions/" + id.value(), recursive=true)
  let prompt_path = root + "/prompt.md"
  @fs.write_file(prompt_path, "system", create_mode=CreateOrTruncate)
  let parsed = cli_command().parse(
    argv=[
      "--session-root",
      root,
      "--session",
      id.value(),
      "--system-prompt-file",
      prompt_path,
      "write",
      "MoonBit",
    ],
    env={ "DEEPSEEK": "test-key" },
  )
  let store = @store.SessionStore(root)
  let session = load_or_new_session(store, id, parsed, V4Pro)
  assert_eq(
    session.system_prompt(),
    "system\n\n\{environment_prompt_section()}",
  )
  assert_eq(session.events().length(), 0)
  let with_event = store.append(session, User(UserMessage("hello")))
  assert_eq(with_event.events().length(), 1)
  @fs.rmdir(root, recursive=true)
}

///|
async test "session list command does not require deepseek setup" {
  let root = @fs.tmpdir(prefix="openseek-cli-session-list-")
  let store = @store.SessionStore(root)
  store.create(Session(SessionId("b"), system_prompt="system"))
  store.create(Session(SessionId("a"), system_prompt="system"))
  let parsed = cli_command().parse(
    argv=["--session-root", root, "--session-list"],
    env={},
  )
  assert_true(handle_session_command(parsed))
  @fs.rmdir(root, recursive=true)
}

///|
async test "session compact command appends summary without api key" {
  let root = @fs.tmpdir(prefix="openseek-cli-session-compact-")
  let store = @store.SessionStore(root)
  let session = @agent_session.Session(
      SessionId("cli-test"),
      system_prompt="system",
    )
    .append(User(UserMessage("hello")))
    .append(Assistant(AssistantMessage("answer")))
  store.create(session)
  let summary_path = root + "/summary.txt"
  @fs.write_file(summary_path, "summarized turn", create_mode=CreateOrTruncate)
  let parsed = cli_command().parse(
    argv=[
      "--session-root", root, "--session", "cli-test", "--session-compact-file",
      summary_path, "--session-compact-from", "1", "--session-compact-to", "2",
    ],
    env={},
  )
  assert_true(handle_session_command(parsed))
  let loaded = store.load(SessionId("cli-test"))
  assert_eq(loaded.events().length(), 3)
  guard loaded.events()[2].item() is Summary(summary) else {
    fail("expected summary")
  }
  assert_eq(summary.content(), "summarized turn")
  @fs.rmdir(root, recursive=true)
}

///|
async test "session compaction rejects missing summary file" {
  let parsed = cli_command().parse(
    argv=[
      "--session", "cli-test", "--session-compact-from", "1", "--session-compact-to",
      "2", "write", "MoonBit",
    ],
    env={ "DEEPSEEK": "test-key" },
  )
  let _ = handle_session_command(parsed) catch {
    error => {
      assert_true("\{error}".contains("--session-compact-file is required"))
      return
    }
  }
  fail("partial session compaction accepted")
}

///|
test "cli rejects invalid max steps" {
  let parsed = cli_command().parse(
    argv=["--max-steps", "0", "write", "MoonBit"],
    env={ "DEEPSEEK": "test-key" },
  )
  let _ = max_steps(parsed) catch {
    error => {
      assert_true("\{error}".contains("--max-steps must be a positive integer"))
      return
    }
  }
  fail("invalid max steps parsed")
}
