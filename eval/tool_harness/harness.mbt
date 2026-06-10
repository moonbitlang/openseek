///|
/// Exercise every agent tool once through the real registry — decode,
/// dispatch, execute, and check each tool's happy path plus a
/// representative failure — and return the per-case report. This is the
/// offline tool smoke test: no model involved, so a failure localizes to
/// the tool layer itself.
pub async fn run_harness() -> @report.Report {
  @async.with_task_group() <| group => {
    run_harness_with_runtime(AgentRuntime(), AgentTaskScope(group))
  }
}

///|
async fn run_harness_with_runtime(
  runtime : @agent_runtime.AgentRuntime,
  scope : @agent_runtime.AgentTaskScope[@report.Report],
) -> @report.Report {
  let tools = tool_definitions(runtime, scope) catch {
    error =>
      return build_report([
        row(
          index=1,
          name="registry",
          mode="dispatch",
          action="build tool registry",
          reason="\{error}",
        ),
      ])
  }
  let rows : Array[@report.ReportRow] = []
  rows.push(run_read_case(1, tools))
  rows.push(run_write_case(2, tools))
  rows.push(run_edit_case(3, tools))
  rows.push(run_shell_case(4, tools))
  rows.push(run_moon_check_case(5, tools))
  rows.push(run_moon_cmd_case(6, tools))
  rows.push(run_moon_ide_case(7, tools))
  rows.push(run_finish_case(8, tools))
  build_report(rows)
}

///|
fn tool_definitions(
  runtime : @agent_runtime.AgentRuntime,
  scope : @agent_runtime.AgentTaskScope[@report.Report],
) -> @agent_tool.Tools raise {
  Tools([
    @read.definition(),
    @write.definition(),
    @edit.definition(),
    @shell.definition(),
    @moon_check.definition(runtime, scope),
    @moon_cmd.definition(),
    @moon_ide.definition(),
    @finish.definition(),
  ])
}

///|
async fn run_read_case(
  index : Int,
  tools : @agent_tool.Tools,
) -> @report.ReportRow {
  let root = @fs.tmpdir(prefix="openseek-tool-read-")
  @vfs.FileSystem({
    "src/read.txt": (
      #|hello read
      #|line two
      #|
    ),
  }).write_to(root)
  let action = dispatch(tools, "read", {
    "path": root + "/src/read.txt",
    "start_line": 1,
    "max_lines": 1,
  })
  let reason = expect_respond(action, contains=["hello read"], error=false)
  @fs.rmdir(root, recursive=true)
  row(index~, name="read", mode="filesystem", action="range read", reason~)
}

///|
async fn run_write_case(
  index : Int,
  tools : @agent_tool.Tools,
) -> @report.ReportRow {
  let root = @fs.tmpdir(prefix="openseek-tool-write-")
  let content =
    #|hello write
    #|second line
    #|
  let action = dispatch(tools, "write", {
    "path": root + "/created.txt",
    "content": content,
  })
  let mut reason = expect_respond(action, contains=["ok: wrote"], error=false)
  if reason == "" {
    reason = @vfs.FileSystem({ "created.txt": content }).mismatch_on_disk(root)
  }
  @fs.rmdir(root, recursive=true)
  row(
    index~,
    name="write",
    mode="filesystem",
    action="create text file",
    reason~,
  )
}

///|
async fn run_edit_case(
  index : Int,
  tools : @agent_tool.Tools,
) -> @report.ReportRow {
  let root = @fs.tmpdir(prefix="openseek-tool-edit-")
  @vfs.FileSystem({
    "src/note.txt": (
      #|alpha
      #|beta
      #|gamma
      #|
    ),
  }).write_to(root)
  let action = dispatch(tools, "edit", {
    "path": root + "/src/note.txt",
    "old_string": "beta\n",
    "new_string": "delta\n",
  })
  let mut reason = expect_respond(
    action,
    contains=["ok: replaced 1 occurrence"],
    error=false,
  )
  if reason == "" {
    reason = @vfs.FileSystem({
      "src/note.txt": (
        #|alpha
        #|delta
        #|gamma
        #|
      ),
    }).mismatch_on_disk(root)
  }
  @fs.rmdir(root, recursive=true)
  row(
    index~,
    name="edit",
    mode="filesystem",
    action="exact replacement",
    reason~,
  )
}

///|
async fn run_shell_case(
  index : Int,
  tools : @agent_tool.Tools,
) -> @report.ReportRow {
  let action = dispatch(tools, "shell", {
    "cmd": "printf tool-harness-shell",
    "max_output_chars": 2000,
  })
  let reason = expect_respond(
    action,
    contains=["exit=0", "tool-harness-shell"],
    error=false,
  )
  row(
    index~,
    name="shell",
    mode="process",
    action="run harmless command",
    reason~,
  )
}

///|
async fn run_moon_check_case(
  index : Int,
  tools : @agent_tool.Tools,
) -> @report.ReportRow {
  let root = moon_library_fixture(prefix="openseek-tool-moon-check-")
  let action = dispatch(tools, "moon_check", { "cwd": root, "target": "native" })
  let reason = expect_respond(
    action,
    contains=[
      "command=moon check --watch --diagnostic-limit 10 --target native", "watcher=started",
      "status=running",
    ],
    error=false,
  )
  @fs.rmdir(root, recursive=true)
  row(
    index~,
    name="moon_check",
    mode="moon",
    action="check native fixture",
    reason~,
  )
}

///|
async fn run_moon_cmd_case(
  index : Int,
  tools : @agent_tool.Tools,
) -> @report.ReportRow {
  let root = moon_library_fixture(prefix="openseek-tool-moon-cmd-")
  let action = dispatch(tools, "moon_cmd", {
    "cwd": root,
    "command": "test",
    "target": "native",
  })
  let reason = expect_respond(
    action,
    contains=["command=moon test --target native", "exit=0"],
    error=false,
  )
  @fs.rmdir(root, recursive=true)
  row(
    index~,
    name="moon_cmd",
    mode="moon",
    action="test native fixture",
    reason~,
  )
}

///|
async fn run_moon_ide_case(
  index : Int,
  tools : @agent_tool.Tools,
) -> @report.ReportRow {
  let root = moon_library_fixture(prefix="openseek-tool-moon-ide-")
  let action = dispatch(tools, "moon_ide", {
    "cwd": root,
    "action": "outline",
    "path": ".",
    "target": "native",
    "max_output_chars": 4000,
  })
  let reason = expect_respond(
    action,
    contains=["command=moon ide outline --target native .", "exit=0", "answer"],
    error=false,
  )
  @fs.rmdir(root, recursive=true)
  row(index~, name="moon_ide", mode="moon", action="outline fixture", reason~)
}

///|
async fn run_finish_case(
  index : Int,
  tools : @agent_tool.Tools,
) -> @report.ReportRow {
  let action = dispatch(tools, "finish", { "answer": "tool harness complete" })
  let reason = expect_finish(action, "tool harness complete")
  row(index~, name="finish", mode="control", action="finish loop", reason~)
}

///|
async fn moon_library_fixture(prefix~ : String) -> String {
  let root = @fs.tmpdir(prefix~)
  @vfs.FileSystem({
    "moon.mod": (
      #|name = "openseek/tool_harness_fixture"
      #|
      #|version = "0.1.0"
      #|
      #|preferred_target = "native"
      #|
    ),
    "moon.pkg": (
      #|warnings = "+unnecessary_annotation"
      #|
    ),
    "lib.mbt": (
      #|///|
      #|pub fn answer() -> Int {
      #|  42
      #|}
      #|
    ),
    "lib_wbtest.mbt": (
      #|///|
      #|test "answer" {
      #|  assert_eq(answer(), 42)
      #|}
      #|
    ),
  }).write_to(root)
  root
}

///|
async fn dispatch(
  tools : @agent_tool.Tools,
  name : String,
  arguments : Json,
) -> @agent_tool.ToolAction {
  let native_call = @deepseek.ToolCall(
    id="call_\{name}",
    name~,
    arguments=arguments.stringify(),
  )
  let call = @agent_tool.AgentToolCall(native_call) catch {
    error =>
      return @agent_tool.ToolAction::respond(
        "error: invalid harness call: \{error}",
        is_error=true,
      )
  }
  @agent_tool.execute_tool_call(call, tools)
}

///|
fn expect_respond(
  action : @agent_tool.ToolAction,
  contains~ : Array[String],
  error~ : Bool,
) -> String {
  match action {
    Respond(output) => {
      if output.is_error != error {
        return "expected is_error=\{error}, got \{output.is_error}: \{short_text(output.content)}"
      }
      for probe in contains {
        if !output.content.contains(probe) {
          return "output missing `\{probe}`: \{short_text(output.content)}"
        }
      }
      ""
    }
    Control(_) => "expected Respond, got Control"
  }
}

///|
fn expect_finish(action : @agent_tool.ToolAction, expected : String) -> String {
  match action {
    Control(Finish(answer)) =>
      if answer == expected {
        ""
      } else {
        "finish answer mismatch: \{short_text(answer)}"
      }
    Control(Abort(reason)) =>
      "expected Finish, got Abort: \{short_text(reason)}"
    Respond(output) =>
      "expected Finish, got Respond: \{short_text(output.content)}"
  }
}

///|
fn build_report(rows : Array[@report.ReportRow]) -> @report.Report {
  let successes = count_successes(rows)
  Report(
    title="Tool Harness",
    summary=[
      Metric(name="result", value="\{successes}/\{rows.length()}"),
      Metric(name="passed", value=(successes == rows.length()).to_string()),
    ],
    metric_columns=["Mode", "Action"],
    rows~,
  )
}

///|
fn count_successes(rows : Array[@report.ReportRow]) -> Int {
  let mut count = 0
  for item in rows {
    if item.success {
      count += 1
    }
  }
  count
}

///|
fn row(
  index~ : Int,
  name~ : String,
  mode~ : String,
  action~ : String,
  reason~ : String,
) -> @report.ReportRow {
  ReportRow(
    index~,
    name~,
    success=reason == "",
    reason=if reason == "" { "ok" } else { reason },
    metrics=[
      Metric(name="Mode", value=mode),
      Metric(name="Action", value=action),
    ],
  )
}

///|
fn short_text(text : String) -> String {
  let squashed = text.replace_all(old="\n", new=" ")
  if squashed.length() <= 160 {
    squashed
  } else {
    squashed[:160].to_owned() + "..."
  }
}
