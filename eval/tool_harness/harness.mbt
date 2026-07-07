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
  let rows : Array[@report.ReportRow] = [
    run_read_case(1, tools),
    run_write_case(2, tools),
    run_edit_case(3, tools),
    run_shell_case(4, tools),
    run_plan_case(5, tools),
    run_finish_case(6, tools),
  ]
  build_report(rows)
}

///|
fn tool_definitions(
  runtime : @agent_runtime.AgentRuntime,
  scope : @agent_runtime.AgentTaskScope[@report.Report],
) -> @agent_tool.Tools raise {
  // No harness tool needs the runtime or task scope now that the moon_check
  // watcher is gone; the parameters stay so the registry shape still mirrors
  // the agent's build_tools.
  ignore(runtime)
  ignore(scope)
  Tools([
    @read.definition(),
    @write.definition(),
    @edit.definition(),
    @shell.definition(),
    @plan.definition(),
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
    "path": "\{root}/src/read.txt",
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
    "path": "\{root}/created.txt",
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
    "path": "\{root}/src/note.txt",
    "old_string": "beta\n",
    "new_string": "delta\n",
    "start_line": 2,
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
async fn run_plan_case(
  index : Int,
  tools : @agent_tool.Tools,
) -> @report.ReportRow {
  let action = dispatch(tools, "plan", {
    "steps": [
      { "title": "read the failing test", "status": "completed" },
      { "title": "fix the parser", "status": "in_progress" },
      { "title": "run moon test", "status": "pending" },
    ],
  })
  let mut reason = expect_respond(
    action,
    contains=["Plan updated: 1/3 done", "in progress: fix the parser"],
    error=false,
  )
  if reason == "" {
    let invalid = dispatch(tools, "plan", {
      "steps": [{ "title": "step", "status": "active" }],
    })
    reason = expect_respond(
      invalid,
      contains=[
        "arguments.steps[0].status to be one of pending|in_progress|completed",
      ],
      error=true,
    )
  }
  row(index~, name="plan", mode="pure", action="record plan", reason~)
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
  for item in rows; count = 0 {
    if item.success {
      continue count + 1
    }
  } nobreak {
    count
  }
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
    "\{squashed[:160]}..."
  }
}
