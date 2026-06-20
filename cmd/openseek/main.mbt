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
    // --no-session contradicts an explicit --session in every mode. Checked
    // before the session-command and serve branches: serve loads its store
    // on its own path, so a later check could not stop it from recording
    // anyway (Codex review).
    if flag(matches, "no-session") && session_id(matches) is Some(_) {
      fail("--no-session contradicts --session; pick one behavior")
    }
    // Best-of-N fleet mode owns its own workspace materialization and session
    // creation, so it branches before prepare_workspace_root (which would
    // create a single --dir) and the session/serve handling.
    let concurrency = parse_positive_int(
      value(matches, "concurrency"),
      "--concurrency",
    )
    if concurrency >= 2 {
      run_fleet(matches, concurrency~)
      return
    }
    let session_commands = session_command_count(matches)
    let workspace_root = prepare_workspace_root(
      matches,
      log_created=session_commands == 0,
    )
    if handle_session_command(matches, workspace_root~) {
      return
    }
    if flag(matches, "serve") {
      if values(matches, "task").length() > 0 {
        fail("--serve reads commands from stdin; it does not take a task")
      }
      run_serve(matches, workspace_root~)
      return
    }
    let api_key = api_key(matches)
    let api_url = api_url(matches)
    let model = @deepseek.Model::parse(value(matches, "model"))
    let max_steps = max_steps(matches)
    let thinking = @deepseek.ThinkingMode::parse(value(matches, "thinking"))
    let task = task_text(matches)
    match resolved_session_id(matches) {
      None => {
        let system_prompt_text = configured_system_prompt(
          matches,
          model,
          workspace_root~,
        )
        @agent.run(
          api_key,
          model,
          task,
          max_steps~,
          system_prompt_text~,
          thinking~,
          api_url?,
          workspace_root~,
        )
      }
      Some(id) => {
        // Name the recording up front so a user scanning the event stream —
        // or its OPENSEEK_LOG_FILE mirror — knows where to find this run
        // later (--session-show, the viz server, or resuming by id).
        @xlog.info() <?
          {
            "event": "session_started",
            "session": id.value(),
            "session_root": session_root(matches, workspace_root~),
            "workspace_root": workspace_root,
          }
        let store = @store.SessionStore(session_root(matches, workspace_root~))
        let session = load_or_new_session(
          store,
          id,
          matches,
          model,
          workspace_root~,
        )
        ignore(
          @agent.run_turn_with_append(
            api_key,
            model,
            session,
            task,
            append_item=(session, item) => store.append(session, item),
            max_steps~,
            thinking~,
            api_url?,
            workspace_root~,
          ),
        )
      }
    }
  })
}

///|
/// The session this run records to: the explicit `--session` id, a generated
/// `cli-<stamp>-<salt>` id by default, or `None` under `--no-session`.
///
/// One-shot runs record by default because "what did the agent actually do?"
/// is asked after the run, when an unrecorded answer is gone for good; the
/// recording is a small JSONL directory under --session-root, and the
/// deferred first write means a run that fails before its first event still
/// leaves nothing behind. `--no-session` restores the ephemeral behavior for
/// callers that must not write to the workspace; combining it with an
/// explicit `--session` is a contradiction that `run_cli` rejects up front
/// for every mode (this helper repeats the check as defense in depth).
///
/// The generated id carries a random salt: two timestamp-only ids collide
/// when a parallel driver launches two bare CLI runs in the same
/// millisecond under one session root, and the colliding runs would append
/// to each other's conversation (Codex review).
async fn resolved_session_id(
  matches : @argparse.Matches,
) -> @agent_session.SessionId? {
  match (session_id(matches), flag(matches, "no-session")) {
    (Some(_), true) =>
      fail("--no-session contradicts --session; pick one behavior")
    (Some(id), false) => Some(id)
    (None, true) => None
    (None, false) =>
      Some(
        @agent_session.SessionId::generated(
          prefix="cli",
          now_ms=@env.now().reinterpret_as_int64(),
          salt=random_salt(),
        ),
      )
  }
}

///|
/// A short random token, or "" where none can be produced (the timestamp
/// alone then still names the session, as before).
///
/// The entropy comes from `mkdtemp` via `@fs.tmpdir`: the kernel arbitrates
/// the random suffix to be unique across concurrent processes — exactly the
/// guarantee two same-millisecond launches need — and the async runtime
/// cannot read `/dev/urandom` directly (character devices are not
/// pollable). The probe directory is removed immediately, and the suffix is
/// filtered to alphanumerics (platforms decorate it with pid and dots).
async fn random_salt() -> String {
  let prefix = "openseek-salt-"
  let dir = @fs.tmpdir(prefix~) catch { _ => return "" }
  @fs.rmdir(dir) catch {
    _ => ()
  }
  // Locate the prefix instead of splitting on a path separator: Windows
  // paths use backslashes, and a `/`-only basename split would drop the
  // salt there entirely (Codex review).
  guard dir.rev_split_once(prefix) is Some((_, suffix)) else { return "" }
  let salt = StringBuilder()
  for ch in suffix {
    if ch is ('0'..='9' | 'a'..='z' | 'A'..='Z') {
      salt <+ "\{ch}"
    }
  }
  salt.to_string()
}

///|
fn failure_message(error_text : String) -> String {
  match error_text.strip_prefix("error: ") {
    Some(message) => return "\{message}"
    None => ()
  }
  let marker = " FAILED: "
  let pieces = error_text.split(marker).collect()
  if pieces.length() < 2 {
    return error_text
  }
  let message = pieces[pieces.length() - 1]
  let message = match message.strip_suffix(")") {
    Some(trimmed) => trimmed
    None => message
  }
  "\{message}"
}

///|
test "failure_message avoids duplicating argparse error prefix" {
  assert_eq(
    failure_message(
      "error: unexpected argument '--xxy' found\n\nUsage: openseek",
    ),
    "unexpected argument '--xxy' found\n\nUsage: openseek",
  )
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
        "dir",
        long="dir",
        env="OPENSEEK_DIR",
        default_values=["."],
        about="Workspace directory for relative paths; creates only the final path component if its parent exists.",
      ),
      OptionArg(
        "max-steps",
        long="max-steps",
        env="OPENSEEK_MAX_STEPS",
        default_values=["1000"],
        about="Maximum number of agent loop steps before stopping.",
      ),
      OptionArg(
        "concurrency",
        long="concurrency",
        env="OPENSEEK_CONCURRENCY",
        default_values=["1"],
        about="Run the task in N sibling copies of --dir concurrently (best-of-N); 1 means a single run.",
      ),
      OptionArg(
        "thinking",
        long="thinking",
        env="OPENSEEK_THINKING",
        default_values=["max"],
        about="DeepSeek thinking mode: no, high, or max.",
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
        "global-skills-dir",
        long="global-skills-dir",
        env="OPENSEEK_GLOBAL_SKILLS_DIR",
        default_values=[""],
        about="User-level skills directory advertised alongside workspace skills; empty means $HOME/.openseek/skills, or %USERPROFILE%/.openseek/skills on Windows.",
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
      OptionArg(
        "format",
        long="format",
        default_values=["text"],
        about="Output format for --session-list: text or json.",
      ),
    ],
    flags=[
      FlagArg(
        "serve",
        long="serve",
        about="Run as a session server: read JSONL commands (prompt/steer/cancel) from stdin.",
      ),
      FlagArg(
        "no-session",
        long="no-session",
        about="Run ephemerally: do not record this run to a durable session.",
      ),
      FlagArg(
        "session-list",
        long="session-list",
        about="List durable sessions (see --format) and exit.",
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
  let key = value(matches, "api-key").trim()
  if key.is_empty() {
    fail("--api-key or DEEPSEEK is required for agent runs")
  }
  "\{key}"
}

///|
fn api_url(matches : @argparse.Matches) -> String? raise {
  let url = value(matches, "api-url").trim()
  if url.is_empty() {
    None
  } else {
    Some("\{url}")
  }
}

///|
fn max_steps(matches : @argparse.Matches) -> Int raise {
  parse_positive_int(value(matches, "max-steps"), "--max-steps")
}

///|
fn task_text(matches : @argparse.Matches) -> String raise {
  let task = values(matches, "task").join(" ").trim()
  if task.is_empty() {
    fail("task description is required for agent runs")
  }
  "\{task}"
}

///|
fn session_id(matches : @argparse.Matches) -> @agent_session.SessionId? raise {
  let id = value(matches, "session").trim()
  if id.is_empty() {
    None
  } else {
    Some(SessionId("\{id}"))
  }
}

///|
async fn prepare_workspace_root(
  matches : @argparse.Matches,
  log_created? : Bool = true,
) -> String {
  let dir = trim_trailing_path_separators("\{value(matches, "dir").trim()}")
  if dir.is_empty() {
    fail("--dir or OPENSEEK_DIR must not be empty")
  }
  if @fs.exists(dir) {
    if @fs.kind(dir) != Directory {
      fail("--dir is not a directory: \{dir}")
    }
    return @fs.realpath(dir)
  }
  let parent = @path.Path(dir).dirname().to_string()
  let parent = if parent == "" { "." } else { parent }
  if !@fs.exists(parent) {
    fail("parent directory for --dir does not exist: \{parent}")
  }
  if @fs.kind(parent) != Directory {
    fail("parent path for --dir is not a directory: \{parent}")
  }
  @fs.mkdir(dir)
  let root = @fs.realpath(dir)
  if log_created {
    @xlog.info() <? { "event": "workspace_created", "dir": root }
  }
  root
}

///|
fn trim_trailing_path_separators(path : String) -> String {
  let mut result = path
  while !is_path_root(result) &&
        (result.has_suffix("/") || result.has_suffix("\\")) {
    result = result[:result.length() - 1].to_owned()
  }
  result
}

///|
fn is_path_root(path : String) -> Bool {
  path == "/" ||
  path == "\\" ||
  path == "//" ||
  path == "\\\\" ||
  is_windows_drive_root(path)
}

///|
fn is_windows_drive_root(path : String) -> Bool {
  path.length() == 3 &&
  path[1] == ':' &&
  (path.has_suffix("/") || path.has_suffix("\\"))
}

///|
fn session_root(
  matches : @argparse.Matches,
  workspace_root? : String = ".",
) -> String raise {
  let root = value(matches, "session-root").trim()
  if root.is_empty() {
    fail("--session-root or OPENSEEK_SESSION_ROOT must not be empty")
  }
  @workspace_path.resolve(workspace_root, "\{root}")
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
  let out = StringBuilder()
  for ch in prompt.trim(); last_was_space = false, count = 0 {
    if count >= PromptLabelMaxChars {
      out.write_char('…')
      break
    }
    if ch is (' ' | '\t' | '\n' | '\r') {
      if !last_was_space {
        out.write_char(' ')
        continue true, count + 1
      }
      continue true, count
    } else if ch.to_int() < 0x20 ||
      ch.to_int() == 0x7F ||
      (ch.to_int() >= 0x80 && ch.to_int() <= 0x9F) {
      // C0/C1 controls and DEL: ESC, CSI, OSC and friends render as terminal
      // commands, not text.
      continue last_was_space, count
    } else {
      out.write_char(ch)
      continue false, count + 1
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
async fn handle_session_command(
  matches : @argparse.Matches,
  workspace_root? : String = ".",
) -> Bool {
  let command_count = session_command_count(matches)
  if command_count == 0 {
    return false
  }
  if command_count > 1 {
    fail(
      "choose only one of --session-list, --session-show, or --session-compact-file",
    )
  }
  let list_sessions = flag(matches, "session-list")
  let show_session = flag(matches, "session-show")
  let compact_file = value(matches, "session-compact-file").trim()
  let compact_from = value(matches, "session-compact-from").trim()
  let compact_to = value(matches, "session-compact-to").trim()
  let store = @store.SessionStore(session_root(matches, workspace_root~))
  if list_sessions {
    match session_list_format(matches) {
      Text =>
        for listing in store.listings() {
          println(format_session_listing(listing))
        }
      Json => println(session_list_json(store).stringify())
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
    "\{compact_from}",
    "--session-compact-from",
  )
  let to_sequence = required_positive_int(
    "\{compact_to}",
    "--session-compact-to",
  )
  let summary_path = @workspace_path.resolve(workspace_root, "\{compact_file}")
  let summary = @fs.read_file(summary_path).text()
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
fn session_command_count(matches : @argparse.Matches) -> Int raise {
  let compact_session = !value(matches, "session-compact-file")
    .trim()
    .is_empty() ||
    !value(matches, "session-compact-from").trim().is_empty() ||
    !value(matches, "session-compact-to").trim().is_empty()
  (if flag(matches, "session-list") { 1 } else { 0 }) +
  (if flag(matches, "session-show") { 1 } else { 0 }) +
  (if compact_session { 1 } else { 0 })
}

///|
priv enum SessionListFormat {
  Text
  Json
}

///|
fn session_list_format(matches : @argparse.Matches) -> SessionListFormat raise {
  match value(matches, "format") {
    "text" => Text
    "json" => Json
    other => fail("--format must be text or json, got: \{other}")
  }
}

///|
/// The store's listings as JSON for machine consumers (e.g. the desktop
/// client's sidebar): an array of `{id, title, updated_at_ms}`, most
/// recently active first. `title` is the untruncated first line of the first
/// user prompt; `updated_at_ms` is the session file mtime rounded down to
/// milliseconds, or `null` for a directory whose session files cannot be
/// stat-ed (such husks sort last, like the human-readable listing).
async fn session_list_json(store : @store.SessionStore) -> Json {
  let entries : Array[Json] = []
  for listing in store.listings() {
    let updated_at_ms : Json = match
      session_listing_updated_at_ms(store, listing) {
      Some(milliseconds) => Json::number(milliseconds.to_double())
      None => Json::null()
    }
    entries.push({
      "id": listing.id().value(),
      "title": session_title(listing.first_prompt()),
      "updated_at_ms": updated_at_ms,
    })
  }
  Json::array(entries)
}

///|
async fn session_listing_updated_at_ms(
  store : @store.SessionStore,
  listing : @store.SessionListing,
) -> Int64? {
  let id = listing.id()
  let stamp = @fs.mtime(store.event_log_file(id)) catch {
    _ => @fs.mtime(store.header_file(id)) catch { _ => return None }
  }
  let (seconds, nanoseconds) = stamp
  Some(mtime_to_unix_millis(seconds, nanoseconds))
}

///|
fn mtime_to_unix_millis(seconds : Int64, nanoseconds : Int) -> Int64 {
  seconds * 1000 + (nanoseconds / 1000000).to_int64()
}

///|
/// A machine-facing title for a session: the first line of its first user
/// prompt, untruncated. Empty when the session has no user prompt.
fn session_title(first_prompt : String) -> String {
  let content = first_prompt.trim()
  let title = match content.split_once("\n") {
    Some((line, _)) => line.trim()
    None => content
  }
  "\{title}"
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
  workspace_root? : String = ".",
) -> @agent_session.Session {
  if store.exists(id) {
    store.load(id) catch {
      @os_error.OSError(_) as error if error.is_ENOENT() =>
        Session(
          id,
          system_prompt=configured_system_prompt(
            matches,
            model,
            workspace_root~,
          ),
        )
      error => raise error
    }
  } else {
    Session(
      id,
      system_prompt=configured_system_prompt(matches, model, workspace_root~),
    )
  }
}

///|
async fn configured_system_prompt(
  matches : @argparse.Matches,
  model : @deepseek.Model,
  workspace_root? : String = ".",
) -> String {
  let base_path = value(matches, "system-prompt-file")
  let addendum_path = value(matches, "system-prompt-addendum-file")
  let base = if base_path == "" {
    @prompt.system_prompt_for_model(model)
  } else {
    @fs.read_file(@workspace_path.resolve(workspace_root, base_path)).text()
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
    let addendum = @fs.read_file(
      @workspace_path.resolve(workspace_root, addendum_path),
    ).text()
    (
      $|\{base}
      $|
      $|\{addendum}
    )
  }
  let tail =
    $|\{with_addendum}
    $|
    $|\{environment_prompt_section(workspace_root~)}
  // Workspace skills join the per-project tail after the environment
  // section: like the cwd they vary per project (and change when skills are
  // edited), so they must sit after all globally shared text to keep it
  // prefix-cache hittable.
  match
    skills_prompt_section_for_cwd(
      global_dir=value(matches, "global-skills-dir"),
      workspace_root~,
    ) {
    Some(section) =>
      (
        $|\{tail}
        $|
        $|\{section}
      )
    None => tail
  }
}

///|
fn global_skills_dir_for_home(value : String?) -> String? {
  if value is Some(value) {
    let home = value.trim()
    if !home.is_empty() {
      return Some("\{home}/.openseek/skills")
    }
  }
  None
}

///|
#cfg(platform="windows")
fn default_global_skills_dir() -> String? {
  if global_skills_dir_for_home(@env.get_env_var("USERPROFILE")) is Some(dir) {
    return Some(dir)
  }
  if global_skills_dir_for_home(@env.get_env_var("HOME")) is Some(dir) {
    return Some(dir)
  }
  None
}

///|
#cfg(not(platform="windows"))
fn default_global_skills_dir() -> String? {
  global_skills_dir_for_home(@env.get_env_var("HOME"))
}

///|
/// The skills advertised to the model: the user-level library (`global_dir`,
/// defaulting to `$HOME/.openseek/skills` or `%USERPROFILE%/.openseek/skills`
/// when empty) merged with the
/// workspace library under `.openseek/skills`, listing `<name>.md` files and
/// `<name>/SKILL.md` layouts. Workspace skills shadow same-named global ones
/// so a project can specialize a shared playbook. Empty or absent
/// directories advertise nothing — and eval harnesses point `global_dir` at
/// a path inside the trial workspace so the developer's own library never
/// leaks into trials.
async fn skills_prompt_section_for_cwd(
  global_dir~ : String,
  workspace_root~ : String,
) -> String? {
  let resolved_global_dir = if global_dir != "" {
    Some(@workspace_path.resolve(workspace_root, global_dir))
  } else {
    default_global_skills_dir()
  }
  let global_skills = if resolved_global_dir is Some(resolved_global_dir) {
    @agent_skill.discover_skills(resolved_global_dir)
  } else {
    []
  }
  @agent_skill.skills_prompt_section(
    @agent_skill.merge_skills(
      global_skills,
      overrides=@agent_skill.discover_skills(
        @workspace_path.resolve(workspace_root, ".openseek/skills"),
      ),
    ),
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
async fn environment_prompt_section(workspace_root? : String = ".") -> String {
  let cwd = if workspace_root == "." || workspace_root == "" {
    @fs.realpath(".") catch {
      _ => "."
    }
  } else {
    @fs.realpath(workspace_root) catch {
      _ => workspace_root
    }
  }
  let section =
    $|## Environment
    $|
    $|Working directory: \{cwd}
    $|Relative paths resolve against it; treat it as the workspace root and stay inside it. Parent and sibling directories belong to other projects. Never pass a cwd you have not verified exists.
  let body = @vfs.dir_outline(cwd)
  let layout = if body == "" {
    ""
  } else {
    "\n\nProject layout (directories; hidden, build, and vendored dirs omitted):\n\{body}"
  }
  "\{section}\{layout}"
}

///|
async test "environment section names the cwd and appends the layout outline" {
  let section = environment_prompt_section()
  let cwd = @fs.realpath(".")
  assert_true(section.contains("Working directory: \{cwd}"))
  assert_true(section.contains("stay inside it"))
  // The repo root has subdirectories, so the layout outline is appended (its
  // content is covered by @layout's own snapshot test).
  assert_true(section.contains("Project layout"))
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
  let trimmed = input.trim()
  if trimmed.is_empty() {
    fail("\{label} is required")
  }
  parse_positive_int("\{trimmed}", label)
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
    "OPENSEEK_DIR": "/tmp/openseek-workspace",
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
  assert_eq(value(parsed, "dir"), "/tmp/openseek-workspace")
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
  assert_eq(value(parsed, "dir"), ".")
  assert_eq(max_steps(parsed), 1000)
  assert_true(session_id(parsed) is None)
  assert_eq(session_root(parsed), ".openseek")
}

///|
test "cli rejects unknown options before task text" {
  let _ = cli_command().parse(argv=["--xxy", "he"], env={}) catch {
    error => {
      assert_true("\{error}".contains("unexpected argument '--xxy' found"))
      return
    }
  }
  fail("unknown option accepted as task text")
}

///|
test "cli accepts hyphen-leading task text after option delimiter" {
  let parsed = cli_command().parse(argv=["--", "--xxy", "he"], env={})
  assert_eq(task_text(parsed), "--xxy he")
}

///|
test "cli allows session management without api key or task" {
  let parsed = cli_command().parse(argv=["--session-list"], env={})
  assert_true(flag(parsed, "session-list"))
  assert_eq(value(parsed, "api-key"), "")
  assert_eq(values(parsed, "task").length(), 0)
}

///|
async test "--dir creates a missing final component when its parent exists" {
  let parent = @fs.tmpdir(prefix="openseek-dir-parent-")
  let child = "\{parent}/child"
  let parsed = cli_command().parse(argv=["--dir", child, "write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  let root = prepare_workspace_root(parsed)
  assert_true(@fs.exists(child))
  assert_eq(root, @fs.realpath(child))
  @fs.rmdir(parent, recursive=true)
}

///|
async test "--dir creates a missing final component with trailing separator" {
  let parent = @fs.tmpdir(prefix="openseek-dir-trailing-")
  let child = "\{parent}/child"
  let parsed = cli_command().parse(
    argv=["--dir", "\{child}/", "write", "MoonBit"],
    env={ "DEEPSEEK": "test-key" },
  )
  let root = prepare_workspace_root(parsed)
  assert_true(@fs.exists(child))
  assert_eq(root, @fs.realpath(child))
  @fs.rmdir(parent, recursive=true)
}

///|
test "--dir trailing separator trim preserves roots" {
  assert_eq(trim_trailing_path_separators("/"), "/")
  assert_eq(trim_trailing_path_separators("//"), "//")
  assert_eq(trim_trailing_path_separators("C:\\"), "C:\\")
  assert_eq(trim_trailing_path_separators("C:/"), "C:/")
  assert_eq(trim_trailing_path_separators("C:\\workspace\\"), "C:\\workspace")
  assert_eq(trim_trailing_path_separators("C:/workspace/"), "C:/workspace")
}

///|
async test "--dir rejects missing parents instead of creating recursively" {
  let root = @fs.tmpdir(prefix="openseek-dir-missing-parent-")
  let child = "\{root}/missing/child"
  let parsed = cli_command().parse(argv=["--dir", child, "write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  let _ = prepare_workspace_root(parsed) catch {
    error => {
      assert_true(
        "\{error}".contains(
          "parent directory for --dir does not exist: \{root}/missing",
        ),
      )
      @fs.rmdir(root, recursive=true)
      return
    }
  }
  @fs.rmdir(root, recursive=true)
  fail("missing parent accepted")
}

///|
async test "--dir rejects existing non-directories" {
  let root = @fs.tmpdir(prefix="openseek-dir-file-")
  let path = "\{root}/file"
  @fs.write_file(path, "not a directory", create_mode=CreateOrTruncate)
  let parsed = cli_command().parse(argv=["--dir", path, "write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  let _ = prepare_workspace_root(parsed) catch {
    error => {
      assert_true("\{error}".contains("--dir is not a directory: \{path}"))
      @fs.rmdir(root, recursive=true)
      return
    }
  }
  @fs.rmdir(root, recursive=true)
  fail("file path accepted as --dir")
}

///|
test "session root resolves relative to workspace root" {
  let parsed = cli_command().parse(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  assert_eq(
    session_root(parsed, workspace_root="/tmp/openseek-workspace"),
    "/tmp/openseek-workspace/.openseek",
  )
  let custom = cli_command().parse(
    argv=["--session-root", "sessions", "write", "MoonBit"],
    env={ "DEEPSEEK": "test-key" },
  )
  assert_eq(
    session_root(custom, workspace_root="/tmp/openseek-workspace"),
    "/tmp/openseek-workspace/sessions",
  )
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
async test "one-shot runs record to a generated salted cli session by default" {
  let parsed = cli_command().parse(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  guard resolved_session_id(parsed) is Some(id) else {
    fail("expected a generated session id")
  }
  assert_true(id.value().has_prefix("cli-"))
  // cli- + YYYYMMDD-HHMMSS-mmm is 23 chars; anything beyond is the random
  // salt that keeps two same-millisecond launches under one session root
  // apart (mkdtemp-arbitrated, so its exact length is platform-defined).
  assert_true(id.value().length() > 24)
}

///|
async test "--no-session restores the ephemeral one-shot" {
  let parsed = cli_command().parse(argv=["--no-session", "write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  assert_true(resolved_session_id(parsed) is None)
}

///|
async test "an explicit --session id is used verbatim" {
  let parsed = cli_command().parse(
    argv=["--session", "demo", "write", "MoonBit"],
    env={ "DEEPSEEK": "test-key" },
  )
  guard resolved_session_id(parsed) is Some(id) else {
    fail("expected the explicit id")
  }
  assert_eq(id.value(), "demo")
}

///|
async test "--session with --no-session is a contradiction" {
  let parsed = cli_command().parse(
    argv=["--session", "demo", "--no-session", "write", "MoonBit"],
    env={ "DEEPSEEK": "test-key" },
  )
  let _ = resolved_session_id(parsed) catch {
    error => {
      assert_true("\{error}".contains("--no-session contradicts --session"))
      return
    }
  }
  fail("expected a contradiction failure")
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
  let prompt_path = "\{dir}/prompt.md"
  let addendum_path = "\{dir}/addendum.md"
  @fs.write_file(prompt_path, "base prompt\n", create_mode=CreateOrTruncate)
  @fs.write_file(addendum_path, "addendum\n", create_mode=CreateOrTruncate)
  let parsed = cli_command().parse(
    argv=[
      "--system-prompt-file", prompt_path, "--system-prompt-addendum-file", addendum_path,
      "write", "MoonBit",
    ],
    // The pinned global-skills dir keeps the exact-text assertion below
    // machine-independent: without it, a developer's ~/.openseek/skills
    // would append a ## Skills section (Codex review).
    env={
      "DEEPSEEK": "test-key",
      "OPENSEEK_GLOBAL_SKILLS_DIR": "\{dir}/no-global-skills",
    },
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
async test "configured system prompt advertises global skills" {
  let dir = @fs.tmpdir(prefix="openseek-global-skills-")
  @fs.mkdir("\{dir}/skills", recursive=true)
  @fs.write_file(
    "\{dir}/skills/release.md",
    (
      #|---
      #|name: release
      #|description: Cut a release.
      #|---
      #|steps
    ),
    create_mode=CreateOrTruncate,
  )
  let prompt_path = "\{dir}/prompt.md"
  @fs.write_file(prompt_path, "base\n", create_mode=CreateOrTruncate)
  let parsed = cli_command().parse(
    argv=["--system-prompt-file", prompt_path, "write", "MoonBit"],
    env={
      "DEEPSEEK": "test-key",
      "OPENSEEK_GLOBAL_SKILLS_DIR": "\{dir}/skills",
    },
  )
  let prompt = configured_system_prompt(parsed, V4Flash)
  assert_true(prompt.contains("## Skills"))
  assert_true(
    prompt.contains(
      "release — Cut a release. (file: \{dir}/skills/release.md)",
    ),
  )
  @fs.rmdir(dir, recursive=true)
}

///|
async test "configured system prompt uses the selected workspace root" {
  let workspace = @fs.tmpdir(prefix="openseek-prompt-workspace-")
  let real_workspace = @fs.realpath(workspace)
  @fs.write_file(
    "\{workspace}/prompt.md",
    "workspace prompt\n",
    create_mode=CreateOrTruncate,
  )
  @fs.mkdir("\{workspace}/.openseek/skills", recursive=true)
  @fs.write_file(
    "\{workspace}/.openseek/skills/release.md",
    (
      #|---
      #|name: release
      #|description: Cut a workspace release.
      #|---
      #|steps
    ),
    create_mode=CreateOrTruncate,
  )
  let parsed = cli_command().parse(
    argv=[
      "--dir", workspace, "--system-prompt-file", "prompt.md", "write", "MoonBit",
    ],
    env={
      "DEEPSEEK": "test-key",
      "OPENSEEK_GLOBAL_SKILLS_DIR": "\{workspace}/no-global-skills",
    },
  )
  let prompt = configured_system_prompt(
    parsed,
    V4Flash,
    workspace_root=real_workspace,
  )
  assert_true(prompt.has_prefix("workspace prompt"))
  assert_true(prompt.contains("Working directory: \{real_workspace}"))
  assert_true(
    prompt.contains(
      "release — Cut a workspace release. (file: \{real_workspace}/.openseek/skills/release.md)",
    ),
  )
  @fs.rmdir(workspace, recursive=true)
}

///|
async test "configured system prompt defaults to the flash prompt" {
  let parsed = cli_command().parse(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  assert_true(
    configured_system_prompt(parsed, V4Flash).contains("optimized for DeepSeek"),
  )
  assert_true(
    configured_system_prompt(parsed, V4Pro).contains("optimized for DeepSeek"),
  )
}

///|
async test "load_or_new_session defers first durable write until append" {
  let root = @fs.tmpdir(prefix="openseek-cli-session-")
  let store = @store.SessionStore(root)
  let id : @agent_session.SessionId = SessionId("cli-test")
  let prompt_path = "\{root}/prompt.md"
  @fs.write_file(prompt_path, "system", create_mode=CreateOrTruncate)
  let parsed = cli_command().parse(
    argv=[
      "--session-root", root, "--session", "cli-test", "--system-prompt-file", prompt_path,
      "write", "MoonBit",
    ],
    // Pinned so the exact-prompt assertions stay machine-independent.
    env={
      "DEEPSEEK": "test-key",
      "OPENSEEK_GLOBAL_SKILLS_DIR": "\{root}/no-global-skills",
    },
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
  @fs.mkdir("\{root}/sessions/\{id.value()}", recursive=true)
  let prompt_path = "\{root}/prompt.md"
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
    // Pinned so the exact-prompt assertion stays machine-independent.
    env={
      "DEEPSEEK": "test-key",
      "OPENSEEK_GLOBAL_SKILLS_DIR": "\{root}/no-global-skills",
    },
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
test "session list format defaults to text and rejects unknown values" {
  let default_format = cli_command().parse(argv=["--session-list"], env={})
  assert_true(session_list_format(default_format) is Text)
  let json_format = cli_command().parse(
    argv=["--session-list", "--format", "json"],
    env={},
  )
  assert_true(session_list_format(json_format) is Json)
  let bogus = cli_command().parse(argv=["--session-list", "--format", "yaml"], env={})
  let _ = session_list_format(bogus) catch {
    error => {
      assert_true("\{error}".contains("--format must be text or json"))
      return
    }
  }
  fail("unknown format accepted")
}

///|
async test "session list json reports titles newest first with husks last" {
  let root = @fs.tmpdir(prefix="openseek-cli-session-list-json-")
  let store = @store.SessionStore(root)
  let older : @agent_session.Session = Session(
    SessionId("older"),
    system_prompt="system",
  )
  store.create(
    older.append(User(UserMessage("  first question\nwith detail  "))),
  )
  let newer : @agent_session.Session = Session(
    SessionId("newer"),
    system_prompt="system",
  )
  store.create(newer)
  // A directory with no session files at all still appears — last, with no
  // timestamp — matching the human-readable listing's behavior.
  @fs.mkdir(root + "/sessions/husk", recursive=true)
  guard session_list_json(store) is Array(entries) else {
    fail("expected a JSON array")
  }
  assert_eq(entries.length(), 3)
  guard entries[0] is Object(newest) &&
    entries[1] is Object(oldest) &&
    entries[2] is Object(husk) else {
    fail("expected JSON objects")
  }
  assert_true(newest.get("id") is Some(String("newer")))
  assert_true(newest.get("title") is Some(String("")))
  assert_true(oldest.get("id") is Some(String("older")))
  assert_true(oldest.get("title") is Some(String("first question")))
  guard oldest.get("updated_at_ms") is Some(Number(stamp, ..)) else {
    fail("expected updated_at_ms")
  }
  assert_true(stamp > 0)
  assert_true(husk.get("id") is Some(String("husk")))
  assert_true(husk.get("updated_at_ms") is Some(Null))
  @fs.rmdir(root, recursive=true)
}

///|
test "session title keeps the untruncated first line" {
  assert_eq(session_title("  first line\nsecond line  "), "first line")
  let long_line = "x".repeat(256)
  let title = session_title(long_line)
  assert_eq(title.char_length(), 256)
  assert_eq(title, long_line)
}

///|
test "mtime to unix millis preserves subsecond precision" {
  assert_eq(mtime_to_unix_millis(42L, 987654321), 42987L)
  assert_eq(mtime_to_unix_millis(42L, 999999), 42000L)
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
  let summary_path = "\{root}/summary.txt"
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
async test "session compact file resolves relative to workspace root" {
  let workspace = @fs.tmpdir(prefix="openseek-cli-session-compact-workspace-")
  let session_root = "\{workspace}/.openseek"
  let store = @store.SessionStore(session_root)
  let session = @agent_session.Session(
      SessionId("cli-test"),
      system_prompt="system",
    )
    .append(User(UserMessage("hello")))
    .append(Assistant(AssistantMessage("answer")))
  store.create(session)
  @fs.write_file(
    "\{workspace}/summary.txt",
    "workspace summary",
    create_mode=CreateOrTruncate,
  )
  let parsed = cli_command().parse(
    argv=[
      "--session", "cli-test", "--session-compact-file", "summary.txt", "--session-compact-from",
      "1", "--session-compact-to", "2",
    ],
    env={},
  )
  assert_true(handle_session_command(parsed, workspace_root=workspace))
  let loaded = store.load(SessionId("cli-test"))
  guard loaded.events()[2].item() is Summary(summary) else {
    fail("expected summary")
  }
  assert_eq(summary.content(), "workspace summary")
  @fs.rmdir(workspace, recursive=true)
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
