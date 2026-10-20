///|
fn job(
  id : String,
  command : String,
  running~ : Bool,
  subagent? : @wire.SubagentInfo,
) -> @protocol.JobView {
  {
    job: {
      generation: "runtime",
      id,
      revision: 1,
      command,
      description: None,
      cwd: None,
      state: if running {
        Running
      } else {
        Exited(0)
      },
      started_at_ms: 1000L,
      backgrounded_at_ms: 1000L,
      finished_at_ms: if running {
        None
      } else {
        Some(2000L)
      },
      last_output_at_ms: None,
      output_file: None,
      output_persistent: false,
      output_bytes: 0L,
      output_chars: 0,
      output_truncated: false,
      invalid_utf8: false,
      output_error: None,
      persistence_error: None,
      cleanup_error: None,
      data: None,
      subagent,
    },
    output_path: None,
    controllable: running,
    error: None,
  }
}

///|
fn subagent(session : String, label : String) -> @wire.SubagentInfo {
  {
    kind: "explore",
    label,
    session,
    launch: Direct,
    outcome: None,
    usage: None,
    report: None,
    workspace: InPlace,
  }
}

///|
/// A workflow of `session` whose children `sr-1` and `sr-2` have started.
fn workflow(session : String) -> Array[@workflow.Run] {
  let runs = @workflow.opened(
    [],
    id="wf-1",
    session~,
    first_child=1,
    child_count=2,
  )
  let runs = @workflow.child_opened(runs, id="sr-1", kind="review", label="a")
  @workflow.child_opened(runs, id="sr-2", kind="review", label="b")
}

///|
test "the card has nothing to show while nothing runs" {
  assert_true(
    @conversation_overview.BackgroundTasks::from_listing(
      jobs=[job("1", "make", running=false)],
      more_jobs=false,
      workflows=[],
    )
    is None,
  )
}

///|
test "running commands and subagents are listed, ended ones counted" {
  guard @conversation_overview.BackgroundTasks::from_listing(
      jobs=[
        job("3", "npm run dev", running=true),
        job(
          "2",
          "subagent",
          running=true,
          subagent=subagent("parent-sr-9", "map the code"),
        ),
        job("1", "make", running=false),
      ],
      more_jobs=true,
      workflows=[],
    )
    is Some(tasks) else {
    fail("a running job should show the card")
  }
  assert_eq(tasks.jobs, [{ command: "npm run dev", started_at_ms: 1000L, }])
  assert_eq(tasks.subagents, ["explore: map the code"])
  assert_eq(tasks.running(), 2)
  assert_eq(tasks.finished, 1)
  assert_true(tasks.more_finished)
  assert_true(tasks.in_jobs)
}

///|
test "a workflow's subagent that is also a job is one task" {
  let runs = workflow("parent")
  let runs = @workflow.child_closed(
    runs,
    id="sr-2",
    status="ok",
    steps=3,
    tokens=10,
  )
  guard @conversation_overview.BackgroundTasks::from_listing(
      jobs=[
        job(
          "1",
          "subagent",
          running=true,
          subagent=subagent("parent-sr-1", "a"),
        ),
      ],
      more_jobs=false,
      workflows=runs,
    )
    is Some(tasks) else {
    fail("a running subagent should show the card")
  }
  // The job's own title wins; the workflow adds only the child it alone knows.
  assert_eq(tasks.subagents, ["explore: a"])
  assert_eq(tasks.finished, 1)
  assert_true(tasks.in_jobs)
}

///|
test "subagents only a workflow knows about open the workflows panel" {
  guard @conversation_overview.BackgroundTasks::from_listing(
      jobs=[],
      more_jobs=false,
      workflows=workflow("parent"),
    )
    is Some(tasks) else {
    fail("running workflow children should show the card")
  }
  assert_eq(tasks.subagents, ["review: a", "review: b"])
  assert_false(tasks.in_jobs)
  // A closed run's unfinished children will not finish: nothing runs.
  assert_true(
    @conversation_overview.BackgroundTasks::from_listing(
      jobs=[],
      more_jobs=false,
      workflows=@workflow.closed(workflow("parent"), id="wf-1"),
    )
    is None,
  )
}
