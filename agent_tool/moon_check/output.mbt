///|
/// Keep only the trailing `max_chars` characters of `content`. Char-based
/// rather than byte-based so multi-byte sequences aren't split.
fn retain_output_tail(content : String, max_chars : Int) -> String {
  if content.char_length() <= max_chars {
    content
  } else {
    let keep_from = content.char_length() - max_chars
    match content.offset_of_nth_char(keep_from) {
      Some(offset) => content[offset:].to_owned()
      None => content
    }
  }
}

///|
/// Return the part of `content` after the most recent
/// `Success/Had errors, waiting for filesystem changes...` marker. Keeps the
/// snapshot focused on the latest watcher pass instead of accumulating every
/// prior run. If the marker is on the last line (so the trailing slice would
/// be empty), the original `content` is returned unchanged — that gives the
/// caller something to display while the next run is still spooling up.
fn latest_run_segment(content : String) -> String {
  let success = "Success, waiting for filesystem changes..."
  let errors = "Had errors, waiting for filesystem changes..."
  let mut start = 0
  let mut offset = 0
  for line in content.split("\n") {
    offset += line.length() + 1
    if line.contains(success) || line.contains(errors) {
      start = offset
    }
  }
  let segment = content[start:]
  if segment == "" {
    content
  } else {
    segment.to_owned()
  }
}

///|
fn moon_check_run_complete(content : String) -> Bool {
  content.contains("Success, waiting for filesystem changes...") ||
  content.contains("Had errors, waiting for filesystem changes...")
}

///|
/// Detect the moon-itself-crashed banner (panic / accidental crash). Distinct
/// from MoonBit compile errors, which leave the watcher running.
fn moon_check_output_is_crash(output : String) -> Bool {
  output.contains("`moon` has accidentally crashed.") ||
  output.contains("panicked at")
}

///|
fn ensure_trailing_newline(output : String) -> String {
  if output == "" || output.has_suffix("\n") {
    output
  } else {
    output + "\n"
  }
}

///|
/// Reduce a `moon` panic banner into a few lines the agent can act on:
/// exit code, crash flag, the `panicked at ...` line, the underlying detail,
/// and the restart budget. The full upstream "Please report it at ..." block
/// is dropped to keep the context window clean across restarts.
fn compact_moon_check_exit_output(
  output : String,
  exit_code : Int,
  restart_attempt~ : Int,
  restart_limit~ : Int,
) -> String {
  let lines : Array[String] = []
  lines.push("[moon_check watcher exited]")
  lines.push("exit=\{exit_code}")
  if moon_check_output_is_crash(output) {
    lines.push("moon_crash=true")
  }
  match first_line_containing(output, "panicked at") {
    Some(line) => lines.push("panic=\{line}")
    None => ()
  }
  match first_line_containing(output, "called `") {
    Some(line) => lines.push("detail=\{line}")
    None => ()
  }
  if restart_attempt <= restart_limit {
    lines.push("restart=attempt \{restart_attempt}/\{restart_limit}")
  } else {
    lines.push("restart=limit reached \{restart_limit}/\{restart_limit}")
  }
  lines.join("\n")
}

///|
fn first_line_containing(content : String, needle : String) -> String? {
  for line in content.split("\n") {
    if line.contains(needle) {
      return Some(line.trim().to_owned())
    }
  }
  None
}

///|
/// Format the `ToolAction` body returned to the agent. `watcher` is one of
/// `"started"`, `"reused"`, or `"restarted"`. Includes the watcher id, status,
/// seq, optional exit/truncation/restart metadata, then the captured output.
fn moon_check_response(
  watcher : String,
  snapshot : MoonCheckSnapshot,
) -> String {
  let cwd_text = match snapshot.cwd {
    Some(cwd) => cwd
    None => "."
  }
  let exit = match snapshot.exit_code {
    Some(code) => "\nexit=\{code}"
    None => ""
  }
  let truncated = if snapshot.output_truncated {
    "\ntruncated=true\nmax_output_chars=\{snapshot.max_output_chars}"
  } else {
    ""
  }
  let restart = if snapshot.restart_count > 0 ||
    snapshot.restart_reason is Some(_) {
    let reason = match snapshot.restart_reason {
      Some(reason) => "\nrestart_reason=\{reason}"
      None => ""
    }
    "\nrestart_count=\{snapshot.restart_count}\nrestart_limit=\{snapshot.restart_limit}\{reason}"
  } else {
    ""
  }
  let output = if snapshot.output == "" {
    "\n(no output yet)"
  } else {
    "\n" + snapshot.output
  }
  "cwd=\{cwd_text}\ncommand=\{snapshot.command}\nwatcher=\{watcher}\nid=\{snapshot.id}\nstatus=\{moon_check_status_label(snapshot.status)}\nseq=\{snapshot.seq}\{exit}\{truncated}\{restart}\{output}"
}

///|
fn moon_check_status_label(status : WatcherStatus) -> String {
  match status {
    Running => "running"
    Stopped => "stopped"
  }
}

///|
/// Format a single watcher snapshot for inclusion in the coalesced
/// `[moon_check update]` event block. Mirrors `moon_check_response` but leads
/// with `id=` and omits the `watcher=<started|reused|restarted>` action
/// verb — update events carry only the latest snapshot state, not the
/// dispatch decision that produced them. `cwd=` and `command=` are still
/// included because the parent block lists multiple watchers and each needs
/// its own identifying fields.
fn MoonCheckSnapshot::update_text(update : MoonCheckSnapshot) -> String {
  let cwd = match update.cwd {
    Some(cwd) => cwd
    None => "."
  }
  let exit = match update.exit_code {
    Some(code) => "\nexit=\{code}"
    None => ""
  }
  let truncated = if update.output_truncated { "\ntruncated=true" } else { "" }
  let restart = if update.restart_count > 0 || update.restart_reason is Some(_) {
    let reason = match update.restart_reason {
      Some(reason) => "\nrestart_reason=\{reason}"
      None => ""
    }
    "\nrestart_count=\{update.restart_count}\nrestart_limit=\{update.restart_limit}\{reason}"
  } else {
    ""
  }
  let output = if update.output == "" {
    "\n(no output yet)"
  } else {
    "\n" + update.output
  }
  "id=\{update.id}\ncwd=\{cwd}\ncommand=\{update.command}\nstatus=\{moon_check_status_label(update.status)}\nseq=\{update.seq}\{exit}\{truncated}\{restart}\{output}"
}

///|
/// Coalesce `MoonCheckUpdate` events by watcher key, keeping only the latest
/// snapshot per key (running or stopped — both can show up in a batch when a
/// watcher exits mid-turn). Called by the agent loop between turns; returns a
/// single `[moon_check update]` block whose body lists one section per
/// watcher key seen in this batch.
///
/// Returns `None` if the event batch contains no `MoonCheckUpdate` entries.
pub fn runtime_update_text(
  events : Array[@agent_runtime.AgentEvent],
) -> String? {
  let latest_moon_checks : Map[String, MoonCheckSnapshot] = {}
  let mut moon_check_count = 0
  for event in events {
    match event {
      MoonCheckUpdate(update) => {
        latest_moon_checks[update.key] = update
        moon_check_count += 1
      }
      _ => ()
    }
  }
  if moon_check_count == 0 {
    None
  } else {
    let parts = [
      for update in latest_moon_checks.values() => update.update_text()
    ]
    Some(
      "[moon_check update]\nevents=\{moon_check_count}\n" + parts.join("\n\n"),
    )
  }
}

///|
/// Heuristic for the `is_error` flag on the tool response. A snapshot is an
/// error when the watcher exited non-zero, or when the latest output contains
/// any of moon's error markers (`Had errors`, JSON `"level":"error"`,
/// `ERROR Run failed`, `Failed with N errors.`, or the project-level
/// `Error: failed when checking project`).
fn moon_check_snapshot_is_error(snapshot : MoonCheckSnapshot) -> Bool {
  match snapshot.exit_code {
    Some(code) if code != 0 => true
    _ =>
      snapshot.output.contains("Had errors, waiting for filesystem changes...") ||
      snapshot.output.contains("\"level\":\"error\"") ||
      snapshot.output.contains("ERROR Run failed") ||
      (
        snapshot.output.contains("Failed with") &&
        snapshot.output.contains("errors.")
      ) ||
      snapshot.output.contains("Error: failed when checking project")
  }
}

///|
test "moon_check update text coalesces by watcher key" {
  let message = runtime_update_text([
    MoonCheckUpdate(
      MoonCheckSnapshot(
        id="moon-check-1",
        key="cwd=.",
        command="moon check --watch --diagnostic-limit 10",
        cwd=None,
        status=Running,
        seq=1,
        output="old",
        output_truncated=false,
        max_output_chars=12000,
        exit_code=None,
        restart_count=0,
        restart_limit=3,
        restart_reason=None,
      ),
    ),
    MoonCheckUpdate(
      MoonCheckSnapshot(
        id="moon-check-1",
        key="cwd=.",
        command="moon check --watch --diagnostic-limit 10",
        cwd=None,
        status=Running,
        seq=2,
        output="new",
        output_truncated=false,
        max_output_chars=12000,
        exit_code=None,
        restart_count=0,
        restart_limit=3,
        restart_reason=None,
      ),
    ),
  ])
  guard message is Some(text) else { fail("expected message") }
  assert_true(text.contains("[moon_check update]"))
  assert_true(text.contains("events=2"))
  assert_true(text.contains("seq=2"))
  assert_true(text.contains("new"))
  assert_false(text.contains("old"))
}

///|
test "moon_check compacts moon watcher crash output" {
  let summary = compact_moon_check_exit_output(
    (
      #|thread 'notify-rs kqueue loop' panicked at /Users/runner/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/kqueue-1.1.1/src/lib.rs:661:86:
      #|called `Option::unwrap()` on a `None` value
      #|`moon` has accidentally crashed.
      #|Please report it at:
      #|    https://github.com/moonbitlang/moon/issues/new?template=bug_report.md
      #|
    ),
    101,
    restart_attempt=2,
    restart_limit=3,
  )
  inspect(
    summary,
    content=(
      #|[moon_check watcher exited]
      #|exit=101
      #|moon_crash=true
      #|panic=thread 'notify-rs kqueue loop' panicked at /Users/runner/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/kqueue-1.1.1/src/lib.rs:661:86:
      #|detail=called `Option::unwrap()` on a `None` value
      #|restart=attempt 2/3
    ),
  )
  assert_false(summary.contains("Please report it at"))
  assert_false(summary.contains("github.com/moonbitlang/moon/issues"))
}
