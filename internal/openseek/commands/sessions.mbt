///|
/// `openseek sessions <list|show|compact|fork|migrate-images>` — durable-session management. Prints
/// for humans directly on stdout, so it never opens the event sink; an event a
/// compaction reports is dropped.
pub async fn run_sessions_command(matches : @argparse.Matches) -> Unit {
  match matches.subcommand {
    Some(("list", m)) => sessions_list(m)
    Some(("show", m)) => sessions_show(m)
    Some(("compact", m)) => sessions_compact(m)
    Some(("migrate-images", m)) => sessions_migrate_images(m)
    Some(("fork", m)) => sessions_fork(m)
    _ =>
      fail("usage: openseek sessions <list|show|compact|fork|migrate-images>")
  }
}

///|
fn sessions_target_id(
  matches : @argparse.Matches,
) -> @agent_session.SessionId raise {
  match matches {
    { values: { "id": [id, ..], .. }, .. } if !id.is_blank() =>
      SessionId(id.trim().to_owned())
    _ => fail("a session id is required (e.g. `openseek sessions show <id>`)")
  }
}

///|
async fn sessions_list(matches : @argparse.Matches) -> Unit {
  let workspace_root = @setup.prepare_workspace_root(matches, log_created=false)
  let store = @store.SessionStore(@setup.session_root(matches, workspace_root~))
  match session_list_format(matches) {
    Text =>
      for listing in store.listings() {
        println(format_session_listing(listing))
      }
    Json => println(session_list_json(store).stringify())
  }
}

///|
async fn sessions_show(matches : @argparse.Matches) -> Unit {
  let workspace_root = @setup.prepare_workspace_root(matches, log_created=false)
  let store = @store.SessionStore(@setup.session_root(matches, workspace_root~))
  println(ToJson::to_json(store.load(sessions_target_id(matches))).stringify())
}

///|
async fn sessions_compact(matches : @argparse.Matches) -> Unit {
  let workspace_root = @setup.prepare_workspace_root(matches, log_created=false)
  let store = @store.SessionStore(@setup.session_root(matches, workspace_root~))
  let id = sessions_target_id(matches)
  let (compact_file, from_input, to_input) = match matches {
    {
      values: {
        "file": [compact_file, ..],
        "from": [from_input, ..],
        "to": [to_input, ..],
        ..
      },
      ..
    } => (compact_file.trim().to_owned(), from_input, to_input)
    _ => fail("missing parsed session compaction arguments")
  }
  guard !compact_file.is_empty() else {
    fail("`openseek sessions compact` requires --file")
  }
  let from_sequence = required_positive_int(from_input, "--from")
  let to_sequence = required_positive_int(to_input, "--to")
  let summary_path = @workspace_path.resolve(workspace_root, compact_file)
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
}

///|
/// `openseek sessions fork <id> [--as <new-id>] [--through <n>]`: start a new
/// session from another one's history. The fork's system prompt is the one a
/// new session started with this command's `--dir`, `--model`, and prompt
/// options would get, with the fork's own scratch directory. The new id is
/// the one thing a caller needs back, to resume it with `--session`, so it is
/// the whole of stdout.
async fn sessions_fork(matches : @argparse.Matches) -> Unit {
  let workspace_root = @setup.prepare_workspace_root(matches, log_created=false)
  let store = @store.SessionStore(@setup.session_root(matches, workspace_root~))
  let source = sessions_target_id(matches)
  let fork = match matches {
    { values: { "as": [id, ..], .. }, .. } => {
      guard !id.is_blank() else { fail("--as needs a session id") }
      @agent_session.SessionId(id.trim().to_owned())
    }
    _ => @setup.generated_session_id()
  }
  let through = match matches {
    { values: { "through": [input, ..], .. }, .. } =>
      Some(@cli.parse_positive_int(input.trim().to_owned(), "--through"))
    _ => None
  }
  let (model, _, _) = @options.agent_settings(matches)
  let system_prompt = @setup.configured_system_prompt(
    matches,
    model,
    workspace_root~,
    session_scratch_dir=store.scratch_dir(fork),
  )
  println(store.fork(source, fork, through?, system_prompt~).id().value())
}

///|
/// Longest first-prompt label a `sessions list` row carries; enough to
/// recognize a conversation without wrapping a normal terminal row.
const PromptLabelMaxChars : Int32 = 60

///|
/// Collapse a prompt to a single-line label — a stored prompt must not be able
/// to inject terminal escape sequences into the listing — elided at
/// `PromptLabelMaxChars`. A session without a recorded prompt shows `-` so the
/// column never vanishes.
fn compact_prompt_label(prompt : String) -> String {
  let label = @cli.terminal_safe_line(prompt, limit=PromptLabelMaxChars)
  if label.is_empty() {
    "-"
  } else {
    label
  }
}

///|
fn format_utc_minute(seconds : Int64) -> String {
  fn pad2(value : Int32) -> String {
    value.to_string().pad_start(2, '0')
  }

  let time = @time.unix(seconds) catch { _ => return "-" }
  "\{time.year()}-\{pad2(time.month())}-\{pad2(time.day())} \{pad2(time.hour())}:\{pad2(time.minute())}"
}

///|
/// One `sessions list` row: tab-separated id, last-activity stamp (UTC,
/// minute precision; `-` for an unreadable session), and its explicit title
/// or first user prompt as a one-line label. Tab separation keeps the listing scriptable —
/// `sessions list | cut -f1` recovers the bare ids the old format printed.
fn format_session_listing(listing : @store.SessionListing) -> String {
  let when = listing.last_active_unix_seconds().map_or("-", format_utc_minute)
  let title = listing.title().unwrap_or_else(() => listing.first_prompt())
  "\{listing.id().value()}\t\{when}\t\{compact_prompt_label(title)}"
}

///|
priv enum SessionListFormat {
  Text
  Json
}

///|
fn session_list_format(matches : @argparse.Matches) -> SessionListFormat raise {
  match matches {
    { values: { "format": ["text", ..], .. }, .. } => Text
    { values: { "format": ["json", ..], .. }, .. } => Json
    { values: { "format": [other, ..], .. }, .. } =>
      fail("--format must be text or json, got: \{other}")
    _ => fail("missing parsed argument: format")
  }
}

///|
/// The store's listings as JSON for machine consumers (e.g. the desktop
/// client's sidebar): an array of `{id, title, updated_at_ms}`, most
/// recently active first. `title` is the untruncated first line of the first
/// user prompt unless an explicit title sidecar overrides it;
/// `updated_at_ms` is the session file mtime rounded down to milliseconds, or
/// `null` for a directory whose session files cannot be stat-ed (such husks
/// sort last, like the human-readable listing).
async fn session_list_json(store : @store.SessionStore) -> Json {
  let entries : Array[Json] = [
    for listing in store.listings() => {
      let updated_at_ms : Json = match
        session_listing_updated_at_ms(store, listing) {
        Some(milliseconds) => Json(milliseconds.to_double())
        None => Json::null()
      }
      {
        "id": listing.id().value(),
        "title": listing
        .title()
        .unwrap_or_else(() => session_title(listing.first_prompt())),
        "updated_at_ms": updated_at_ms,
      }
    }
  ]
  Json(entries)
}

///|
async fn session_listing_updated_at_ms(
  store : @store.SessionStore,
  listing : @store.SessionListing,
) -> Int64? {
  let (seconds, nanoseconds) = @fs.mtime(store.session_file(listing.id())) catch {
    _ => return None
  }
  Some(mtime_to_unix_millis(seconds, nanoseconds))
}

///|
fn mtime_to_unix_millis(seconds : Int64, nanoseconds : Int32) -> Int64 {
  seconds * 1000 + (nanoseconds / 1000000).to_int64()
}

///|
/// A machine-facing title for a session: the first line of its first user
/// prompt, untruncated. Empty when the session has no user prompt. A session
/// opened by a `!` command is titled by its `$ command` line rather than the
/// `<user_shell_command>` tag its stored envelope begins with.
fn session_title(first_prompt : String) -> String {
  let first_prompt = match @command_context.parse(first_prompt) {
    Some(shell) => "$ \{shell.command}"
    None => first_prompt
  }
  let content = first_prompt.trim()
  let title = match content.split_once("\n") {
    Some((line, _)) => line.trim()
    None => content
  }
  "\{title}"
}

///|
fn required_positive_int(input : String, label : String) -> Int32 raise {
  let trimmed = input.trim()
  if trimmed.is_empty() {
    fail("\{label} is required")
  }
  @cli.parse_positive_int("\{trimmed}", label)
}

///|
async fn sessions_migrate_images(matches : @argparse.Matches) -> Unit {
  let workspace_root = @setup.prepare_workspace_root(matches, log_created=false)
  let store = @store.SessionStore(@setup.session_root(matches, workspace_root~))
  let session = store.migrate_images(
    sessions_target_id(matches),
    attachments=@attachments.AttachmentStore::default(),
  )
  println(
    "migrated images for session \{session.id().value()}; last_sequence=\{session.last_sequence()}",
  )
}
