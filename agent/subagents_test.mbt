///|
/// A scripted child that reports `{"answer": "the answer"}` for its request.
let reporting_child : String =
  #|read line
  #|while [ $# -gt 0 ]; do
  #|  case "$1" in
  #|    --result-file) RESULT=$2; shift ;;
  #|    --session) SESSION=$2; shift ;;
  #|  esac
  #|  shift
  #|done
  #|printf '{"version":1,"request_id":"%s","status":"completed","output":{"answer":"the answer"}}' "$SESSION" > "$RESULT"
  #|

///|
/// The registry a session that may delegate gets: the `subagent` tool, an
/// exit notice that names the child's outcome, and `job_output` answering
/// with the report.
#cfg(not(platform="windows"))
async test "a session's subagent ends with a notice and a readable report" {
  let root = @fs.tmpdir(prefix="openseek-agent-subagents-")
  defer @fs.rmdir(root, recursive=true)
  @async.with_timeout(10000, () => {
    @async.with_task_group(group => {
      let runtime = @agent_runtime.AgentRuntime()
      let scope : @agent_runtime.AgentTaskScope[Unit] = AgentTaskScope(group)
      let mut woke = false
      let tools = @agent.build_tools(
        runtime,
        scope,
        on_background_wake=() => woke = true,
        subagents={
          launcher: jobs => {
            Launcher(
              scope,
              runtime=jobs,
              children=ChildSession(root~, parent="p"),
              program="sh",
              args=["-c", reporting_child, "sh"],
              result_dir="\{root}/results",
            )
          },
          kinds: [
            {
              name: "explore",
              ceiling: 40,
              validate: report => Ok(report),
              takes_instructions: true,
              changes_code: false,
            },
          ],
          audit_context: () => Json::null(),
          notified: _ => false,
        },
      )
      guard tools.find("subagent") is Some(subagent) &&
        subagent.execute is Async(start) else {
        fail("a delegating session has the subagent tool")
      }
      guard start({
          "kind": "explore",
          "input": { "query": "q" },
          "label": "scout",
        })
        is Respond({ data: Some({ "job_id": String(job_id), .. }), .. }) else {
        fail("expected the child to start")
      }
      for _ in 0..<400 {
        if woke {
          break
        }
        @async.sleep(25)
      }
      let notices = runtime
        .drain_steers()
        .filter_map(steer => {
          match steer {
            Notice(text) => Some(text)
            _ => None
          }
        })
      guard notices is [notice] else { fail("expected one exit notice") }
      assert_true(
        notice.contains("subagent job \{job_id} (explore: scout) reported"),
      )
      guard tools.find("job_output") is Some(job_output) &&
        job_output.execute is Async(read) else {
        fail("job_output is registered")
      }
      guard read({ "job_id": job_id }) is Respond(output) else {
        fail("job_output responds")
      }
      assert_true(output.content.contains("ended: reported"))
      assert_true(output.content.contains("\"answer\": \"the answer\""))
    })
  })
}

///|
/// Without subagents, the registry has no `subagent` tool.
async test "a session that may not delegate has no subagent tool" {
  @async.with_task_group(group => {
    let tools = @agent.build_tools(AgentRuntime(), AgentTaskScope(group))
    assert_true(tools.find("subagent") is None)
  })
}
