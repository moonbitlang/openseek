///|
/// A scripted child: reads its request, finds its result file and session
/// among the arguments the launcher appends, and answers with `RESULT`.
let child : String =
  #|read line
  #|while [ $# -gt 0 ]; do
  #|  case "$1" in
  #|    --result-file) RESULT=$2; shift ;;
  #|    --session) SESSION=$2; shift ;;
  #|  esac
  #|  shift
  #|done
  #|printf '{"version":1,"request_id":"%s","status":"completed","output":{"answer":"42","citations":[]}}' "$SESSION" > "$RESULT"
  #|

///|
fn kinds() -> Array[@subagent.Kind] {
  [
    {
      name: "explore",
      ceiling: 40,
      validate: report => {
        if report is { "answer": String(_), .. } {
          Ok(report)
        } else {
          Err("answer must be a string")
        }
      },
      takes_instructions: true,
      worktree: false,
    },
    {
      name: "change",
      ceiling: 40,
      validate: report => Ok(report),
      takes_instructions: false,
      worktree: true,
    },
  ]
}

///|
async fn[X] tool_and_runtime(
  group : @async.TaskGroup[X],
  max_live? : Int32,
  script? : String,
) -> (@agent_tool.AgentToolDefinition, @bgjobs.BgJobRuntime) {
  let root = @fs.tmpdir(prefix="openseek-subagent-tool-")
  group.add_defer(() => @fs.rmdir(root, recursive=true))
  let runtime = @bgjobs.BgJobRuntime(AgentTaskScope(group))
  let launcher = @agent_subagent.Launcher(
    AgentTaskScope(group),
    runtime~,
    children=ChildSession(root~, parent="p"),
    program="sh",
    args=["-c", script.unwrap_or(child), "sh"],
    result_dir="\{root}/results",
    max_live?,
    grace_ms=100,
  )
  (@subagent.definition(launcher, kinds()), runtime)
}

///|
async fn call(
  tool : @agent_tool.AgentToolDefinition,
  arguments : Json,
) -> @agent_tool.ToolOutput {
  guard tool.execute is Async(execute) else { fail("subagent should be async") }
  guard execute(arguments) is Respond(output) else {
    fail("subagent should respond")
  }
  output
}

///|
#cfg(not(platform="windows"))
async test "subagent starts a child and answers with its job at once" {
  @async.with_task_group(group => {
    let (tool, runtime) = tool_and_runtime(group)
    assert_true(tool.is_concurrent_safe())
    let output = call(tool, {
      "kind": "explore",
      "input": { "query": "where is X" },
      "label": "find X",
    })
    assert_false(output.is_error)
    guard output.data
      is Some({ "job_id": String(job_id), "session": String(session), .. }) else {
      fail("expected job data")
    }
    assert_eq(session, "p-sr-\{session.split("-sr-").last().unwrap()}")
    assert_true(output.content.contains("job_wait (job_ids=[\"\{job_id}\"])"))
    assert_true(output.content.contains("job_output (job_id=\"\{job_id}\")"))
    for _ in 0..<400 {
      if runtime.snapshot(job_id)
        is Some({ subagent: Some({ outcome: Some(_), .. }), .. }) {
        break
      }
      @async.sleep(25)
    }
    assert_true(
      runtime.snapshot(job_id)
      is Some(
        { subagent: Some({ outcome: Some(Captured), label: "find X", .. }), .. }
      ),
    )
  })
}

///|
#cfg(not(platform="windows"))
async test "subagent refuses an unknown kind and a missing input" {
  @async.with_task_group(group => {
    let (tool, _) = tool_and_runtime(group)
    let unknown = call(tool, { "kind": "worker", "input": {} })
    assert_true(unknown.is_error)
    assert_true(unknown.content.contains("one of explore"))
    let missing = call(tool, { "kind": "explore" })
    assert_true(missing.is_error)
  })
}

///|
#cfg(not(platform="windows"))
async test "subagent says when the session's slots are full" {
  @async.with_task_group(group => {
    let (tool, runtime) = tool_and_runtime(
      group,
      max_live=1,
      script="read line; cat >/dev/null",
    )
    let first = call(tool, { "kind": "explore", "input": { "query": "a" } })
    guard first.data is Some({ "job_id": String(job_id), .. }) else {
      fail("expected the first to start")
    }
    let second = call(tool, { "kind": "explore", "input": { "query": "b" } })
    assert_true(second.is_error)
    assert_true(second.content.contains("Nothing was started"))
    assert_true(runtime.stop(job_id))
  })
}

///|
/// A child's budget is always bounded by its kind's ceiling: an omitted
/// budget is the ceiling, never the engine's own default, and a larger one
/// is capped.
#cfg(not(platform="windows"))
async test "subagent bounds every child's step budget by its kind's ceiling" {
  for case in [(None, 40), (Some(10), 10), (Some(500), 40)] {
    let (requested, expected) = case
    @async.with_task_group(group => {
      let seen = @fs.tmpdir(prefix="openseek-subagent-request-")
      group.add_defer(() => @fs.rmdir(seen, recursive=true))
      let (tool, runtime) = tool_and_runtime(
        group,
        script="read line; printf '%s' \"$line\" > \{seen}/request.json",
      )
      let arguments : Json = match requested {
        Some(steps) =>
          { "kind": "explore", "input": { "query": "q" }, "max_steps": steps }
        None => { "kind": "explore", "input": { "query": "q" } }
      }
      guard call(tool, arguments).data is Some({ "job_id": String(job_id), .. }) else {
        fail("expected the child to start")
      }
      for _ in 0..<400 {
        if runtime.snapshot(job_id)
          is Some({ subagent: Some({ outcome: Some(_), .. }), .. }) {
          break
        }
        @async.sleep(25)
      }
      let request = @json.parse(@fs.read_file("\{seen}/request.json").text())
      assert_true(
        request is { "limits": { "max_steps": Number(steps, ..), .. }, .. } &&
        steps == expected.to_double(),
        msg=request.stringify(),
      )
    })
  }
}

///|
#cfg(not(platform="windows"))
async test "only a kind that changes code takes a worktree, and it must" {
  @async.with_task_group(group => {
    let (tool, _) = tool_and_runtime(group)
    let missing = call(tool, { "kind": "change", "input": { "task": "t" } })
    assert_true(missing.is_error && missing.content.contains("needs worktree"))
    let malformed = call(tool, {
      "kind": "change",
      "input": { "task": "t" },
      "worktree": { "name": "x", "allowed_paths": [1] },
    })
    assert_true(
      malformed.is_error && malformed.content.contains("needs worktree"),
    )
    let stray = call(tool, {
      "kind": "explore",
      "input": { "query": "q" },
      "worktree": { "name": "x", "allowed_paths": ["lib"] },
    })
    assert_true(
      stray.is_error && stray.content.contains("only a kind that changes code"),
    )
  })
}

///|
#cfg(not(platform="windows"))
async test "worktree names what it cannot act on" {
  @async.with_task_group(group => {
    let root = @fs.tmpdir(prefix="openseek-worktree-tool-")
    group.add_defer(() => @fs.rmdir(root, recursive=true))
    let runtime = @bgjobs.BgJobRuntime(AgentTaskScope(group))
    let launcher = @agent_subagent.Launcher(
      AgentTaskScope(group),
      runtime~,
      children=ChildSession(root~, parent="p"),
      program="sh",
      args=[],
      result_dir="\{root}/results",
      cwd=root,
    )
    let tool = @subagent.worktree_definition(launcher)
    // Not a git checkout: no worker could have a worktree here.
    let listed = call(tool, { "action": "list" })
    assert_false(listed.is_error)
    assert_true(listed.content.contains("No worker"))
    let unknown = call(tool, { "action": "integrate", "worker": "job-9" })
    assert_true(unknown.is_error && unknown.content.contains("job-9"))
    let no_worker = call(tool, { "action": "discard" })
    assert_true(no_worker.is_error)
  })
}

///|
/// A child of a kind that reads no instructions is refused at once, with
/// what to do instead, rather than with a retry that can never succeed.
#cfg(not(platform="windows"))
async test "subagent_send refuses a kind that takes no instructions" {
  @async.with_task_group(group => {
    let root = @fs.tmpdir(prefix="openseek-subagent-send-")
    group.add_defer(() => @fs.rmdir(root, recursive=true))
    let runtime = @bgjobs.BgJobRuntime(AgentTaskScope(group))
    let launcher = @agent_subagent.Launcher(
      AgentTaskScope(group),
      runtime~,
      children=ChildSession(root~, parent="p"),
      program="sh",
      args=["-c", "read line; cat >/dev/null", "sh"],
      result_dir="\{root}/results",
      grace_ms=100,
    )
    let kinds : Array[@subagent.Kind] = [
      {
        name: "review",
        ceiling: 40,
        validate: report => Ok(report),
        takes_instructions: false,
        worktree: false,
      },
    ]
    let start = @subagent.definition(launcher, kinds)
    let send = @subagent.send_definition(launcher, kinds)
    let started = call(start, { "kind": "review", "input": { "goal": "g" } })
    guard started.data is Some({ "job_id": String(job_id), .. }) else {
      fail("expected the review to start")
    }
    let refused = call(send, { "job_id": job_id, "message": "narrow it" })
    assert_true(refused.is_error)
    assert_true(refused.content.contains("takes no instructions"))
    assert_false(refused.content.contains("retry"))
    assert_true(runtime.stop(job_id))
  })
}
