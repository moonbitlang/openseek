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
  runtime : @agent_runtime.AgentRuntime,
  scope : @agent_runtime.AgentTaskScope[X],
) -> @agent_tool.AgentToolDefinition {
  let moon_runtime = MoonCheckRuntime(runtime, scope)
  AgentToolDefinition(
    name="moon_check",
    description="Start or inspect a persistent `moon check --watch --diagnostic-limit 10` watcher for the given cwd. One watcher runs per directory: the first call starts it, later calls with the same arguments return the latest snapshot, and calling with different options replaces the watcher instead of stacking a second one.",
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
/// JSON entry point invoked by the agent runtime. Decodes the arguments and
/// delegates to `moon_check`. Decoding failures become `is_error=true`
/// responses with a stable `"error: moon_check requires ..."` message;
/// unexpected runtime failures during the `moon_check` call surface as
/// `"error running moon_check: ..."`. Cancellations propagate.
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
/// Dispatch by watcher key (one watcher per cwd):
/// - A running record with the same command → reuse (`watcher=reused`), no
///   new process.
/// - A running record whose command differs (the options changed) → stop it
///   and start fresh (`watcher=replaced`). Stacking a second watcher on the
///   same directory would make the two compete for moon's build lock and
///   report stale results.
/// - A stopped record for `key` → restart (`watcher=restarted`) with the
///   *new* options, carrying the prior `restart_count` forward.
/// - No record for `key` → fresh start (`watcher=started`).
async fn[X] moon_check(
  runtime : MoonCheckRuntime[X],
  input : @decode.MoonCheckInput,
) -> @agent_tool.ToolAction {
  let key = moon_check_key(input)
  match runtime.moon_check_snapshot(key) {
    Some(snapshot) if snapshot.status is Running =>
      if snapshot.command == moon_check_command_line(input) {
        @agent_tool.ToolAction::respond(
          moon_check_response("reused", snapshot),
          is_error=moon_check_snapshot_is_error(snapshot),
        )
      } else {
        ignore(runtime.stop_moon_check(key))
        start_moon_check(
          runtime,
          input,
          key,
          action="replaced",
          restart_count=snapshot.restart_count,
          restart_reason=Some("options changed; replaced \{snapshot.command}"),
        )
      }
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
async test "moon_check advertises expected schema" {
  @async.with_task_group() <| group => {
    let tool = definition(AgentRuntime(), AgentTaskScope(group))
    assert_eq(tool.name, "moon_check")
    let JsonSchema(schema) = tool.schema
    let text = schema.stringify()
    assert_false(text.contains("\"path\""))
    assert_false(text.contains("\"paths\""))
    assert_true(text.contains("\"target\""))
  }
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
async test "moon_check rejects non-object arguments" {
  @async.with_task_group() <| group => {
    let result = execute(
      MoonCheckRuntime(AgentRuntime(), AgentTaskScope(group)),
      Json::null(),
    )
    guard result is Respond(output) else { fail("expected Respond") }
    assert_eq(output.content, "error: moon_check requires object arguments")
    assert_true(output.is_error)
  }
}

///|
async test "moon_check validates a real fixture project" {
  let project = valid_project()
  let canonical = @fs.realpath(project)
  @async.with_task_group() <| group => {
    let runtime = MoonCheckRuntime(AgentRuntime(), AgentTaskScope(group))
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
  let project = valid_project()
  @async.with_task_group() <| group => {
    let runtime = MoonCheckRuntime(AgentRuntime(), AgentTaskScope(group))
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
async test "changed options replace the cwd's watcher instead of stacking" {
  let project = valid_project()
  @async.with_task_group() <| group => {
    let runtime = MoonCheckRuntime(AgentRuntime(), AgentTaskScope(group))
    let first = execute(runtime, { "cwd": project })
    // Same cwd, different options: the running watcher is stopped and
    // replaced — never a second concurrent watcher fighting it for moon's
    // build lock.
    let second = execute(runtime, { "cwd": project, "deny_warn": true })
    let key = moon_check_key(@decode.decode({ "cwd": project }))
    guard first is Respond(first_output) else { fail("expected Respond") }
    guard second is Respond(second_output) else { fail("expected Respond") }
    assert_true(first_output.content.contains("watcher=started"))
    assert_true(first_output.content.contains("id=moon-check-1"))
    assert_true(second_output.content.contains("watcher=replaced"))
    assert_true(second_output.content.contains("id=moon-check-2"))
    assert_true(second_output.content.contains("--deny-warn"))
    // One record per cwd: the replacement owns the key, with the new
    // command, and a same-options follow-up reuses it.
    guard runtime.moon_check_snapshot(key) is Some(snapshot) else {
      fail("expected a registry record")
    }
    assert_true(snapshot.status is Running)
    assert_true(snapshot.command.contains("--deny-warn"))
    let third = execute(runtime, { "cwd": project, "deny_warn": true })
    guard third is Respond(third_output) else { fail("expected Respond") }
    assert_true(third_output.content.contains("watcher=reused"))
    assert_true(third_output.content.contains("id=moon-check-2"))
    ignore(runtime.stop_moon_check(key))
  }
  @fs.rmdir(project, recursive=true)
}

///|
async test "moon_check restarts a stopped watcher on explicit next call" {
  let project = valid_project()
  @async.with_task_group() <| group => {
    let runtime = MoonCheckRuntime(AgentRuntime(), AgentTaskScope(group))
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
  let project = invalid_project()
  let canonical = @fs.realpath(project)
  @async.with_task_group() <| group => {
    let runtime = MoonCheckRuntime(AgentRuntime(), AgentTaskScope(group))
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
    let runtime = MoonCheckRuntime(AgentRuntime(), AgentTaskScope(group))
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
/// Materialize a single-package moon workspace into a fresh temp directory
/// via `@vfs.FileSystem`. The caller passes in the module name (used as the
/// `moon.mod` `name`) and the `lib.mbt` body; everything else — `moon.pkg`
/// warning policy, `moon.mod` version — is shared boilerplate. Returns the
/// temp directory path so the test can pass it to `moon_check` as `cwd` and
/// later `@fs.rmdir` it.
async fn write_fixture_project(
  module_name~ : String,
  lib_content~ : String,
) -> String {
  let target = @fs.tmpdir(prefix="openseek-moon-check-")
  @vfs.FileSystem({
    "moon.mod": "name = \"openseek/\{module_name}\"\n\nversion = \"0.1.0\"\n",
    "moon.pkg": "warnings = \"+unnecessary_annotation\"\n",
    "lib.mbt": lib_content,
  }).write_to(target)
  target
}

///|
async fn valid_project() -> String {
  write_fixture_project(
    module_name="moon_check_valid_fixture",
    lib_content=(
      #|///|
      #|pub fn meaning() -> Int {
      #|  42
      #|}
      #|
    ),
  )
}

///|
async fn invalid_project() -> String {
  write_fixture_project(
    module_name="moon_check_invalid_fixture",
    lib_content=(
      #|///|
      #|pub fn meaning() -> Int {
      #|  "not an int"
      #|}
      #|
    ),
  )
}

///|
/// Normalize fixture-test output so the inline `inspect(...)` snapshots are
/// stable across runs: replace canonical and original temp paths with
/// `<fixture>`, replace volatile `seq=N` with `seq=<seq>`, drop the
/// `Success, waiting for filesystem changes...` heartbeat (timing-dependent),
/// and strip any stray `failed: ...` lines from the snapshot diff machinery.
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
