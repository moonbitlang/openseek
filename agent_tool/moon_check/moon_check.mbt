///|
pub(all) enum WatcherStatus {
  Running
  Stopped
}

///|
pub struct MoonCheckSnapshot {
  id : String
  key : String
  command : String
  cwd : String?
  status : WatcherStatus
  seq : Int
  output : String
  output_truncated : Bool
  max_output_chars : Int
  exit_code : Int?
  restart_count : Int
  restart_limit : Int
  restart_reason : String?
}

///|
pub fn MoonCheckSnapshot::MoonCheckSnapshot(
  id~ : String,
  key~ : String,
  command~ : String,
  cwd~ : String?,
  status~ : WatcherStatus,
  seq~ : Int,
  output~ : String,
  output_truncated~ : Bool,
  max_output_chars~ : Int,
  exit_code~ : Int?,
  restart_count~ : Int,
  restart_limit~ : Int,
  restart_reason~ : String?,
) -> MoonCheckSnapshot {
  {
    id,
    key,
    command,
    cwd,
    status,
    seq,
    output,
    output_truncated,
    max_output_chars,
    exit_code,
    restart_count,
    restart_limit,
    restart_reason,
  }
}

///|
pub(all) extenum @agent_runtime.AgentEvent += {
  MoonCheckUpdate(MoonCheckSnapshot)
}

///|
priv struct MoonCheckRecord {
  id : String
  key : String
  command : String
  cwd : String?
  process : @process.Process
  max_output_chars : Int
  mut status : WatcherStatus
  mut seq : Int
  mut output : String
  mut output_truncated : Bool
  mut exit_code : Int?
  mut run_complete : Bool
  restart_count : Int
  restart_limit : Int
  restart_reason : String?
}

///|
priv struct MoonCheckRuntime[X] {
  runtime : @agent_runtime.AgentRuntime[X]
  moon_checks : Map[String, MoonCheckRecord]
  mut next_moon_check_index : Int
}

///|
fn[X] MoonCheckRuntime::MoonCheckRuntime(
  runtime : @agent_runtime.AgentRuntime[X],
) -> MoonCheckRuntime[X] {
  { runtime, moon_checks: {}, next_moon_check_index: 1 }
}

///|
fn[X] MoonCheckRuntime::group(
  self : MoonCheckRuntime[X],
) -> @async.TaskGroup[X] {
  self.runtime.group()
}

///|
fn[X] MoonCheckRuntime::next_moon_check_id(
  self : MoonCheckRuntime[X],
) -> String {
  let id = "moon-check-\{self.next_moon_check_index}"
  self.next_moon_check_index += 1
  id
}

///|
fn[X] MoonCheckRuntime::register_moon_check(
  self : MoonCheckRuntime[X],
  key~ : String,
  id~ : String,
  command~ : String,
  cwd~ : String?,
  process~ : @process.Process,
  max_output_chars~ : Int,
  restart_count~ : Int,
  restart_limit~ : Int,
  restart_reason~ : String?,
) -> MoonCheckSnapshot {
  let record = {
    id,
    key,
    command,
    cwd,
    process,
    max_output_chars,
    status: Running,
    seq: 0,
    output: "",
    output_truncated: false,
    exit_code: None,
    run_complete: false,
    restart_count,
    restart_limit,
    restart_reason,
  }
  self.moon_checks[record.key] = record
  record.to_snapshot()
}

///|
fn[X] MoonCheckRuntime::moon_check_snapshot(
  self : MoonCheckRuntime[X],
  key : String,
) -> MoonCheckSnapshot? {
  match self.moon_checks.get(key) {
    Some(record) => Some(record.to_snapshot())
    None => None
  }
}

///|
fn[X] MoonCheckRuntime::record_moon_check_output(
  self : MoonCheckRuntime[X],
  key : String,
  id : String,
  chunk : String,
) -> MoonCheckSnapshot? {
  match self.moon_checks.get(key) {
    None => None
    Some(record) if record.id != id => None
    Some(record) => {
      let segment = if record.run_complete {
        latest_run_segment(chunk)
      } else {
        latest_run_segment(record.output + chunk)
      }
      record.output = retain_output_tail(segment, record.max_output_chars)
      record.output_truncated = segment.char_length() > record.max_output_chars
      record.run_complete = moon_check_run_complete(record.output)
      record.seq += 1
      let snapshot = record.to_snapshot()
      self.emit_moon_check(snapshot)
      Some(snapshot)
    }
  }
}

///|
fn[X] MoonCheckRuntime::replace_moon_check_output(
  self : MoonCheckRuntime[X],
  key : String,
  id : String,
  output : String,
) -> MoonCheckSnapshot? {
  match self.moon_checks.get(key) {
    None => None
    Some(record) if record.id != id => None
    Some(record) => {
      record.output = retain_output_tail(output, record.max_output_chars)
      record.output_truncated = output.char_length() > record.max_output_chars
      record.run_complete = moon_check_run_complete(record.output)
      record.seq += 1
      let snapshot = record.to_snapshot()
      self.emit_moon_check(snapshot)
      Some(snapshot)
    }
  }
}

///|
fn[X] MoonCheckRuntime::mark_moon_check_stopped(
  self : MoonCheckRuntime[X],
  key : String,
  id : String,
  exit_code : Int?,
) -> MoonCheckSnapshot? {
  match self.moon_checks.get(key) {
    None => None
    Some(record) if record.id != id => None
    Some(record) => {
      record.status = Stopped
      record.exit_code = exit_code
      record.seq += 1
      let snapshot = record.to_snapshot()
      self.emit_moon_check(snapshot)
      Some(snapshot)
    }
  }
}

///|
fn[X] MoonCheckRuntime::stop_moon_check(
  self : MoonCheckRuntime[X],
  key : String,
) -> MoonCheckSnapshot? {
  match self.moon_checks.get(key) {
    None => None
    Some(record) =>
      if record.status is Running {
        record.process.cancel()
        self.mark_moon_check_stopped(key, record.id, None)
      } else {
        Some(record.to_snapshot())
      }
  }
}

///|
fn[X] MoonCheckRuntime::emit_moon_check(
  self : MoonCheckRuntime[X],
  snapshot : MoonCheckSnapshot,
) -> Unit {
  self.runtime.emit_event(MoonCheckUpdate(snapshot))
}

///|
fn MoonCheckRecord::to_snapshot(self : MoonCheckRecord) -> MoonCheckSnapshot {
  {
    id: self.id,
    key: self.key,
    command: self.command,
    cwd: self.cwd,
    status: self.status,
    seq: self.seq,
    output: self.output,
    output_truncated: self.output_truncated,
    max_output_chars: self.max_output_chars,
    exit_code: self.exit_code,
    restart_count: self.restart_count,
    restart_limit: self.restart_limit,
    restart_reason: self.restart_reason,
  }
}

///|
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
/// Tool definition for `moon_check`: starts or reuses a session-scoped
/// `moon check --watch --diagnostic-limit 10` watcher for the given workspace
/// and check options. Repeated calls with the same arguments return the
/// latest watcher snapshot instead of starting another process.
///
/// ## Arguments
/// - `cwd` (string, optional): working directory. Empty means current process
///   directory.
/// - `target` (string, optional): one of MoonBit's `moon check --target`
///   values.
/// - `warn_list` (string, optional): value for `--warn-list`.
/// - `deny_warn` (bool, optional): add `--deny-warn` when true.
/// - `fmt` (bool, optional): add `--fmt` when true.
/// - `explain` (bool, optional): add `--explain` when true.
///
/// ## Result
/// - `Respond(ToolOutput("cwd=...\ncommand=...\nwatcher=...\n...",
///   is_error=<latest check has errors>))` when `moon` runs or is already
///   running.
/// - `Respond(ToolOutput("error running moon_check: ...", is_error=true))`
///   when launching the process raises.
/// - `Respond(ToolOutput("error: moon_check requires ...", is_error=true))`
///   for invalid arguments.
pub fn[X] definition(
  runtime : @agent_runtime.AgentRuntime[X],
) -> @agent_tool.AgentToolDefinition {
  let moon_runtime = MoonCheckRuntime(runtime)
  AgentToolDefinition(
    name="moon_check",
    description="Start or inspect a persistent `moon check --watch --diagnostic-limit 10` watcher for the given cwd/options. The first call starts the watcher; later calls with the same arguments return the latest snapshot without starting another watcher.",
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "cwd": { "type": "string" },
        "target": {
          "type": "string",
          "enum": ["wasm", "wasm-gc", "js", "native", "llvm", "all"],
        },
        "warn_list": { "type": "string" },
        "deny_warn": { "type": "boolean" },
        "fmt": { "type": "boolean" },
        "explain": { "type": "boolean" },
      },
    }),
    execute=Async(arguments => execute(moon_runtime, arguments)),
  )
}

///|
async fn[X] execute(
  runtime : MoonCheckRuntime[X],
  arguments : Json,
) -> @agent_tool.ToolAction {
  let input = @decode.decode(arguments) catch {
    error => {
      let message = @tool_error.failure_message("\{error}")
      return @agent_tool.ToolAction::respond(
        "error: moon_check requires \{message}",
        is_error=true,
      )
    }
  }
  moon_check(runtime, input) catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      @agent_tool.ToolAction::respond(
        "error running moon_check: \{error}",
        is_error=true,
      )
  }
}

///|
let default_initial_wait_ms : Int = 1000

///|
let default_max_output_chars : Int = 12000

///|
let default_diagnostic_limit : Int = 10

///|
let default_restart_limit : Int = 3

///|
fn command_args(input : @decode.MoonCheckInput, watch~ : Bool) -> Array[String] {
  let args : Array[String] = ["check"]
  if watch {
    args.push("--watch")
  }
  args.push("--diagnostic-limit")
  args.push(default_diagnostic_limit.to_string())
  match input.target {
    Some(target) => {
      args.push("--target")
      args.push(target)
    }
    None => ()
  }
  match input.warn_list {
    Some(warn_list) => {
      args.push("--warn-list")
      args.push(warn_list)
    }
    None => ()
  }
  if input.deny_warn {
    args.push("--deny-warn")
  }
  if input.fmt {
    args.push("--fmt")
  }
  if input.explain {
    args.push("--explain")
  }
  args
}

///|
async fn[X] moon_check(
  runtime : MoonCheckRuntime[X],
  input : @decode.MoonCheckInput,
) -> @agent_tool.ToolAction {
  let key = moon_check_key(input)
  match runtime.moon_check_snapshot(key) {
    Some(snapshot) if snapshot.status is Running =>
      @agent_tool.ToolAction::respond(
        moon_check_response("reused", snapshot),
        is_error=moon_check_snapshot_is_error(snapshot),
      )
    Some(snapshot) =>
      start_moon_check(
        runtime,
        input,
        key,
        action="restarted",
        restart_count=snapshot.restart_count,
        restart_reason=Some("manual restart after stopped watcher"),
      )
    None =>
      start_moon_check(
        runtime,
        input,
        key,
        action="started",
        restart_count=0,
        restart_reason=None,
      )
  }
}

///|
async fn[X] start_moon_check(
  runtime : MoonCheckRuntime[X],
  input : @decode.MoonCheckInput,
  key : String,
  action~ : String,
  restart_count~ : Int,
  restart_reason~ : String?,
) -> @agent_tool.ToolAction {
  let id = spawn_moon_check_watch(
    runtime,
    input,
    key,
    restart_count~,
    restart_reason~,
    initial_output="",
  )
  wait_for_initial_snapshot(runtime, key)
  match runtime.moon_check_snapshot(key) {
    None =>
      @agent_tool.ToolAction::respond(
        "error: moon_check lost watcher state for \{id}",
        is_error=true,
      )
    Some(snapshot) =>
      @agent_tool.ToolAction::respond(
        moon_check_response(action, snapshot),
        is_error=moon_check_snapshot_is_error(snapshot),
      )
  }
}

///|
async fn[X] spawn_moon_check_watch(
  runtime : MoonCheckRuntime[X],
  input : @decode.MoonCheckInput,
  key : String,
  restart_count~ : Int,
  restart_reason~ : String?,
  initial_output~ : String,
) -> String {
  let args = command_args(input, watch=true)
  let id = runtime.next_moon_check_id()
  let (reader, writer) = @process.read_from_process()
  let process = @process.spawn(
    runtime.group(),
    "moon",
    args,
    stdout=writer,
    stderr=writer,
    cwd?=input.cwd.map(cwd => cwd.view()),
    cancel_handler=@process.hard_cancel(),
    no_wait=true,
  )
  ignore(
    runtime.register_moon_check(
      key~,
      id~,
      command="moon \{args.join(" ")}",
      cwd=input.cwd,
      process~,
      max_output_chars=default_max_output_chars,
      restart_count~,
      restart_limit=default_restart_limit,
      restart_reason~,
    ),
  )
  if initial_output != "" {
    ignore(runtime.replace_moon_check_output(key, id, initial_output))
  }
  runtime.group().spawn_bg(no_wait=true, allow_failure=true) <| () => {
    monitor_moon_check(runtime, input, key, id, reader, process)
  }
  id
}

///|
async fn[X] wait_for_initial_snapshot(
  runtime : MoonCheckRuntime[X],
  key : String,
) -> Unit {
  let ticks = default_initial_wait_ms / 50
  for _ in 0..<ticks {
    match runtime.moon_check_snapshot(key) {
      Some(snapshot) if snapshot.output != "" || snapshot.status is Stopped =>
        return
      _ => @async.sleep(50)
    }
  }
}

///|
async fn[X] monitor_moon_check(
  runtime : MoonCheckRuntime[X],
  input : @decode.MoonCheckInput,
  key : String,
  id : String,
  reader : @process.ReadFromProcess,
  process : @process.Process,
) -> Unit {
  defer reader.close()
  for ;; {
    let chunk = reader.read_some(max_len=1024) catch {
      error if @async.is_being_cancelled() => raise error
      error => {
        ignore(
          runtime.record_moon_check_output(
            key,
            id,
            "\n[moon_check reader error: \{error}]\n",
          ),
        )
        ignore(runtime.mark_moon_check_stopped(key, id, None))
        return
      }
    }
    match chunk {
      None => {
        let exit_code = process.wait()
        handle_moon_check_exit(runtime, input, key, id, exit_code)
        return
      }
      Some(bytes) =>
        ignore(
          runtime.record_moon_check_output(key, id, @utf8.decode_lossy(bytes)),
        )
    }
  }
}

///|
async fn[X] handle_moon_check_exit(
  runtime : MoonCheckRuntime[X],
  input : @decode.MoonCheckInput,
  key : String,
  id : String,
  exit_code : Int,
) -> Unit {
  guard runtime.moon_check_snapshot(key) is Some(snapshot) &&
    snapshot.id == id &&
    snapshot.status is Running else {
    return
  }
  let moon_crashed = moon_check_output_is_crash(snapshot.output)
  if exit_code != 0 && moon_crashed {
    let restart_attempt = snapshot.restart_count + 1
    ignore(
      runtime.replace_moon_check_output(
        key,
        id,
        compact_moon_check_exit_output(
          snapshot.output,
          exit_code,
          restart_attempt~,
          restart_limit=snapshot.restart_limit,
        ),
      ),
    )
  }
  let stopped = runtime.mark_moon_check_stopped(key, id, Some(exit_code))
  guard stopped is Some(stopped_snapshot) else { return }
  if should_auto_restart_moon_check(stopped_snapshot, exit_code, moon_crashed~) {
    ignore(
      spawn_moon_check_watch(
        runtime,
        input,
        key,
        restart_count=stopped_snapshot.restart_count + 1,
        restart_reason=Some("auto restart after exit \{exit_code}"),
        initial_output=ensure_trailing_newline(stopped_snapshot.output),
      ),
    )
  }
}

///|
fn should_auto_restart_moon_check(
  snapshot : MoonCheckSnapshot,
  exit_code : Int,
  moon_crashed~ : Bool,
) -> Bool {
  moon_crashed &&
  exit_code != 0 &&
  snapshot.restart_count < snapshot.restart_limit
}

///|
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
pub fn MoonCheckSnapshot::update_text(update : MoonCheckSnapshot) -> String {
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
fn moon_check_key(input : @decode.MoonCheckInput) -> String {
  let cwd = match input.cwd {
    Some(cwd) => cwd
    None => "."
  }
  let target = match input.target {
    Some(target) => target
    None => ""
  }
  let warn_list = match input.warn_list {
    Some(warn_list) => warn_list
    None => ""
  }
  "cwd=\{cwd}\ntarget=\{target}\nwarn_list=\{warn_list}\ndeny_warn=\{input.deny_warn}\nfmt=\{input.fmt}\nexplain=\{input.explain}"
}

///|
fn test_snapshot(
  restart_count~ : Int,
  restart_limit~ : Int,
) -> MoonCheckSnapshot {
  MoonCheckSnapshot(
    id="moon-check-test",
    key="cwd=.",
    command="moon check --watch --diagnostic-limit 10",
    cwd=None,
    status=Running,
    seq=1,
    output="",
    output_truncated=false,
    max_output_chars=12000,
    exit_code=None,
    restart_count~,
    restart_limit~,
    restart_reason=None,
  )
}

///|
async test "moon_check advertises expected schema" {
  @async.with_task_group() <| group => {
    let tool = definition(AgentRuntime(group))
    assert_eq(tool.name, "moon_check")
    let JsonSchema(schema) = tool.schema
    let text = schema.stringify()
    assert_false(text.contains("\"path\""))
    assert_false(text.contains("\"paths\""))
    assert_true(text.contains("\"target\""))
  }
}

///|
test "moon_check builds direct moon command arguments" {
  let input = @decode.decode({
    "cwd": "/tmp",
    "target": "native",
    "warn_list": "+unnecessary_annotation",
    "deny_warn": true,
    "fmt": true,
    "explain": true,
  })
  assert_eq(
    command_args(input, watch=false).join("|"),
    "check|--diagnostic-limit|10|--target|native|--warn-list|+unnecessary_annotation|--deny-warn|--fmt|--explain",
  )
}

///|
test "moon_check builds watch command arguments" {
  let input = @decode.decode({ "target": "native" })
  assert_eq(
    command_args(input, watch=true).join("|"),
    "check|--watch|--diagnostic-limit|10|--target|native",
  )
}

///|
test "moon_check rejects invalid target" {
  let _ = @decode.decode({ "target": "browser" }) catch {
    error => {
      assert_true("\{error}".contains("arguments.target"))
      return
    }
  }
  fail("invalid target parsed")
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

///|
test "moon_check auto restart respects exit code and budget" {
  let snapshot = test_snapshot(restart_count=2, restart_limit=3)
  assert_true(should_auto_restart_moon_check(snapshot, 101, moon_crashed=true))
  assert_false(should_auto_restart_moon_check(snapshot, 0, moon_crashed=true))
  assert_false(
    should_auto_restart_moon_check(snapshot, 101, moon_crashed=false),
  )
  assert_false(
    should_auto_restart_moon_check(
      test_snapshot(restart_count=3, restart_limit=3),
      101,
      moon_crashed=true,
    ),
  )
}

///|
async test "moon_check runtime ignores stale watcher id updates" {
  @async.with_task_group() <| group => {
    let runtime = MoonCheckRuntime(AgentRuntime(group))
    let key = "cwd=/tmp"
    let (reader1, writer1) = @process.read_from_process()
    let process1 = @process.spawn(
      group,
      "moon",
      ["--version"],
      stdout=writer1,
      stderr=writer1,
      no_wait=true,
    )
    let (reader2, writer2) = @process.read_from_process()
    let process2 = @process.spawn(
      group,
      "moon",
      ["--version"],
      stdout=writer2,
      stderr=writer2,
      no_wait=true,
    )
    ignore(
      runtime.register_moon_check(
        key~,
        id="moon-check-1",
        command="moon check --watch",
        cwd=None,
        process=process1,
        max_output_chars=12000,
        restart_count=0,
        restart_limit=3,
        restart_reason=None,
      ),
    )
    ignore(
      runtime.register_moon_check(
        key~,
        id="moon-check-2",
        command="moon check --watch",
        cwd=None,
        process=process2,
        max_output_chars=12000,
        restart_count=0,
        restart_limit=3,
        restart_reason=None,
      ),
    )
    assert_true(
      runtime.record_moon_check_output(key, "moon-check-1", "stale") is None,
    )
    assert_true(
      runtime.mark_moon_check_stopped(key, "moon-check-1", Some(101)) is None,
    )
    guard runtime.record_moon_check_output(key, "moon-check-2", "fresh")
      is Some(snapshot) else {
      fail("expected current watcher update")
    }
    assert_eq(snapshot.output, "fresh")
    assert_true(snapshot.status is Running)
    ignore(process1.wait())
    ignore(process2.wait())
    reader1.close()
    reader2.close()
  }
}

///|
async test "moon_check keeps crash summary in replacement output" {
  @async.with_task_group() <| group => {
    let runtime = MoonCheckRuntime(AgentRuntime(group))
    let key = "cwd=/tmp"
    let (reader, writer) = @process.read_from_process()
    let process = @process.spawn(
      group,
      "moon",
      ["--version"],
      stdout=writer,
      stderr=writer,
      no_wait=true,
    )
    ignore(
      runtime.register_moon_check(
        key~,
        id="moon-check-2",
        command="moon check --watch",
        cwd=None,
        process~,
        max_output_chars=12000,
        restart_count=1,
        restart_limit=3,
        restart_reason=Some("auto restart after exit 101"),
      ),
    )
    let summary =
      #|[moon_check watcher exited]
      #|exit=101
      #|restart=attempt 1/3
      #|
    ignore(runtime.replace_moon_check_output(key, "moon-check-2", summary))
    let first_replacement_output =
      #|Finished. moon: ran 2 tasks, now up to date
      #|Success, waiting for filesystem changes...
      #|
    guard runtime.record_moon_check_output(
        key, "moon-check-2", first_replacement_output,
      )
      is Some(snapshot) else {
      fail("expected replacement watcher output")
    }
    assert_true(snapshot.output.contains("[moon_check watcher exited]"))
    assert_true(snapshot.output.contains("restart=attempt 1/3"))
    assert_true(
      snapshot.output.contains("Success, waiting for filesystem changes..."),
    )
    ignore(process.wait())
    reader.close()
  }
}

///|
async test "moon_check rejects non-object arguments" {
  @async.with_task_group() <| group => {
    let result = execute(MoonCheckRuntime(AgentRuntime(group)), Json::null())
    guard result is Respond(output) else { fail("expected Respond") }
    assert_eq(output.content, "error: moon_check requires object arguments")
    assert_true(output.is_error)
  }
}

///|
async test "moon_check validates a real fixture project" {
  let project = copy_fixture_project("valid_project")
  let canonical = @fs.realpath(project)
  @async.with_task_group() <| group => {
    let runtime = MoonCheckRuntime(AgentRuntime(group))
    let result = execute(runtime, { "cwd": project })
    ignore(
      runtime.stop_moon_check(
        moon_check_key(@decode.decode({ "cwd": project })),
      ),
    )
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    inspect(
      stable_moon_check_output(output.content, project, canonical),
      content=(
        #|cwd=<fixture>
        #|command=moon check --watch --diagnostic-limit 10
        #|watcher=started
        #|id=moon-check-1
        #|status=running
        #|seq=<seq>
        #|Finished. moon: ran 2 tasks, now up to date
      ),
    )
  }
  @fs.rmdir(project, recursive=true)
}

///|
async test "moon_check reuses a running watcher for the same arguments" {
  let project = copy_fixture_project("valid_project")
  @async.with_task_group() <| group => {
    let runtime = MoonCheckRuntime(AgentRuntime(group))
    let args : Json = { "cwd": project }
    let first = execute(runtime, args)
    let second = execute(runtime, args)
    ignore(runtime.stop_moon_check(moon_check_key(@decode.decode(args))))
    guard first is Respond(first_output) else { fail("expected Respond") }
    guard second is Respond(second_output) else { fail("expected Respond") }
    assert_false(first_output.is_error)
    assert_false(second_output.is_error)
    assert_true(first_output.content.contains("watcher=started"))
    assert_true(first_output.content.contains("id=moon-check-1"))
    assert_true(second_output.content.contains("watcher=reused"))
    assert_true(second_output.content.contains("id=moon-check-1"))
    assert_false(second_output.content.contains("id=moon-check-2"))
  }
  @fs.rmdir(project, recursive=true)
}

///|
async test "moon_check restarts a stopped watcher on explicit next call" {
  let project = copy_fixture_project("valid_project")
  @async.with_task_group() <| group => {
    let runtime = MoonCheckRuntime(AgentRuntime(group))
    let args : Json = { "cwd": project }
    let key = moon_check_key(@decode.decode(args))
    let first = execute(runtime, args)
    ignore(runtime.stop_moon_check(key))
    let second = execute(runtime, args)
    ignore(runtime.stop_moon_check(key))
    guard first is Respond(first_output) else { fail("expected Respond") }
    guard second is Respond(second_output) else { fail("expected Respond") }
    assert_true(first_output.content.contains("watcher=started"))
    assert_true(first_output.content.contains("id=moon-check-1"))
    assert_true(second_output.content.contains("watcher=restarted"))
    assert_true(second_output.content.contains("id=moon-check-2"))
    assert_true(
      second_output.content.contains(
        "restart_reason=manual restart after stopped watcher",
      ),
    )
  }
  @fs.rmdir(project, recursive=true)
}

///|
async test "moon_check reports diagnostics from a broken fixture project" {
  let project = copy_fixture_project("invalid_project")
  let canonical = @fs.realpath(project)
  @async.with_task_group() <| group => {
    let runtime = MoonCheckRuntime(AgentRuntime(group))
    let result = execute(runtime, { "cwd": project })
    ignore(
      runtime.stop_moon_check(
        moon_check_key(@decode.decode({ "cwd": project })),
      ),
    )
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    inspect(
      stable_moon_check_output(output.content, project, canonical),
      content=(
        #|cwd=<fixture>
        #|command=moon check --watch --diagnostic-limit 10
        #|watcher=started
        #|id=moon-check-1
        #|status=running
        #|seq=<seq>
        #|Error: [4014]
        #|   ╭─[ <fixture>/lib.mbt:3:3 ]
        #|   │
        #| 3 │   "not an int"
        #|   │   ──────┬─────
        #|   │         ╰─────── Expr Type Mismatch
        #|        has type : String
        #|        wanted   : Int
        #|───╯
        #|Failed with 0 warnings, 1 errors.
        #|ERROR Run failed with error error=failed when checking project
        #|failed when checking project
        #|Had errors, waiting for filesystem changes...
      ),
    )
  }
  @fs.rmdir(project, recursive=true)
}

///|
async test "moon_check validates a virtual filesystem workspace" {
  let project = @fs.tmpdir(prefix="openseek-moon-check-vfs-")
  @vfs.FileSystem({
    "moon.mod": (
      #|name = "openseek/moon_check_vfs_fixture"
      #|
      #|version = "0.1.0"
      #|
      #|preferred_target = "native"
      #|
    ),
    "math/moon.pkg": (
      #|warnings = "+unnecessary_annotation"
      #|
    ),
    "math/math.mbt": (
      #|///|
      #|pub fn add(left : Int, right : Int) -> Int {
      #|  left + right
      #|}
      #|
    ),
  }).write_to(project)
  let canonical = @fs.realpath(project)
  @async.with_task_group() <| group => {
    let runtime = MoonCheckRuntime(AgentRuntime(group))
    let args : Json = { "cwd": project, "target": "native" }
    let result = execute(runtime, args)
    ignore(runtime.stop_moon_check(moon_check_key(@decode.decode(args))))
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    inspect(
      stable_moon_check_output(output.content, project, canonical),
      content=(
        #|cwd=<fixture>
        #|command=moon check --watch --diagnostic-limit 10 --target native
        #|watcher=started
        #|id=moon-check-1
        #|status=running
        #|seq=<seq>
        #|Finished. moon: ran 2 tasks, now up to date
      ),
    )
  }
  @fs.rmdir(project, recursive=true)
}

///|
async fn copy_fixture_project(name : String) -> String {
  let target = @fs.tmpdir(prefix="openseek-moon-check-")
  copy_fixture_file(name, "moon.mod.fixture", target + "/moon.mod")
  copy_fixture_file(name, "moon.pkg.fixture", target + "/moon.pkg")
  copy_fixture_file(name, "lib.mbt.fixture", target + "/lib.mbt")
  target
}

///|
async fn copy_fixture_file(
  fixture : String,
  file : String,
  target : String,
) -> Unit {
  let content = @fs.read_file(
    "agent_tool/moon_check/fixtures/\{fixture}/\{file}",
  ).text()
  @fs.write_file(target, content, create_mode=CreateOrTruncate)
}

///|
fn stable_moon_check_output(
  content : String,
  project : String,
  canonical : String,
) -> String {
  let normalized = content
    .replace_all(old=canonical, new="<fixture>")
    .replace_all(old=project, new="<fixture>")
    .replace_all(
      old="──────┬─────  \n",
      new="──────┬─────\n",
    )
  let stable_lines : Array[String] = []
  for line in normalized.split("\n") {
    if line.has_prefix("seq=") {
      stable_lines.push("seq=<seq>")
    } else if line == "Success, waiting for filesystem changes..." {
      ()
    } else if !line.has_prefix("failed: ") {
      stable_lines.push(line.to_owned())
    }
  }
  stable_lines.join("\n").trim().to_owned()
}
