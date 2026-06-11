///|
/// How long `start_moon_check` polls (in 50ms ticks) for the first output or
/// stop before returning the initial snapshot to the caller. Bounds the
/// perceived latency of the first tool call against a slow `moon` startup.
let default_initial_wait_ms : Int = 1000

///|
/// Per-watcher cap on retained output (char-counted, see `retain_output_tail`
/// in output.mbt). Above this, the snapshot keeps only the trailing slice and
/// sets `truncated=true` in the response.
let default_max_output_chars : Int = 12000

///|
/// Value forwarded as `--diagnostic-limit` on every `moon check` invocation.
/// Caps how many diagnostics moon prints per run so an early broken-project
/// state can't flood the agent's context.
let default_diagnostic_limit : Int = 10

///|
/// Maximum number of auto-restarts after a moon crash (see
/// `should_auto_restart_moon_check`). Restart count is carried forward across
/// restarts; once it hits this limit, the watcher stays stopped and the next
/// caller is responsible for restarting manually.
let default_restart_limit : Int = 3

///|
/// Build the `moon check ...` argv. `watch=true` produces the watcher form
/// (`moon check --watch --diagnostic-limit 10 ...`); `watch=false` produces
/// the equivalent one-shot form, used by the command-args tests.
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
/// Spawn a watcher, wait briefly for its first output, then return the
/// snapshot wrapped in a `ToolAction`. Called by `moon_check` for both the
/// initial start (`action="started"`) and the manual restart after a stopped
/// watcher (`action="restarted"`).
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
/// The exact command line a `moon_check` input runs. Doubles as the option
/// fingerprint: a running watcher whose command equals the incoming input's
/// is reusable; any difference means the options changed and the watcher is
/// replaced.
fn moon_check_command_line(input : @decode.MoonCheckInput) -> String {
  "moon \{command_args(input, watch=true).join(" ")}"
}

///|
/// Spawn `moon check --watch ...` with combined stdout/stderr piped back to
/// `monitor_moon_check`. Returns the freshly assigned watcher id. The caller
/// can pre-populate the recorded output via `initial_output` — used when an
/// auto-restart wants to carry the previous crash summary forward.
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
  let exited : @async.Queue[Unit] = Queue(kind=Unbounded)
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
      command=moon_check_command_line(input),
      cwd=input.cwd,
      process~,
      max_output_chars=default_max_output_chars,
      restart_count~,
      restart_limit=default_restart_limit,
      restart_reason~,
      exited~,
    ),
  )
  if initial_output != "" {
    ignore(runtime.replace_moon_check_output(key, id, initial_output))
  }
  runtime.group().spawn_bg(no_wait=true, allow_failure=true) <| () => {
    // Every monitor exit path has reaped (or failed to read) the child by
    // the time it returns; signal regardless of which path ran so a waiting
    // replacement can never hang.
    defer ignore(exited.try_put(()) catch { _ => false })
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
/// Background task: read process output in 1KB chunks, feed each into
/// `record_moon_check_output`, and on EOF wait for the exit code and hand off
/// to `handle_moon_check_exit`.
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
/// React to a watcher exit. Three cases:
/// - **Crash exit** (non-zero exit code AND output matches the moon crash
///   banner): replace the output with a compact summary (see
///   `compact_moon_check_exit_output`), mark stopped, and auto-restart if the
///   restart budget allows (see `should_auto_restart_moon_check`).
/// - **Non-crash non-zero exit**: mark stopped, no output replacement, no
///   auto-restart. The next caller of `moon_check` triggers a manual restart.
/// - **Clean exit** (exit code 0): mark stopped, no auto-restart.
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
/// Auto-restart only when moon itself crashed (panic / accidental crash
/// banner) with a non-zero exit, and we still have restart budget left.
/// Normal compile errors leave the watcher running, so they never reach this
/// path — only outright watcher exits do.
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
