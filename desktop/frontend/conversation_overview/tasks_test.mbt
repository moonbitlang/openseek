///|
/// A job running `command`, or a subagent job for the child `agent` names
/// (its session and label).
fn job(
  command : String,
  running~ : Bool,
  agent? : (String, String),
) -> @protocol.JobView {
  {
    job: {
      generation: "runtime",
      id: command,
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
      finished_at_ms: None,
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
      subagent: agent.map(agent => {
        kind: "explore",
        label: agent.1,
        session: agent.0,
        launch: Direct,
        outcome: None,
        usage: None,
        report: None,
        workspace: InPlace,
      }),
    },
    output_path: None,
    controllable: running,
    error: None,
  }
}

///|
/// A workflow of `parent` whose children `sr-1` and `sr-2` have started.
fn workflow() -> Array[@workflow.Run] {
  let runs = @workflow.opened(
    [],
    id="wf-1",
    session="parent",
    first_child=1,
    child_count=2,
  )
  let runs = @workflow.child_opened(runs, id="sr-1", kind="review", label="a")
  @workflow.child_opened(runs, id="sr-2", kind="review", label="b")
}

///|
fn summarize(
  jobs : Array[@protocol.JobView],
  more_jobs~ : Bool = false,
  workflows~ : Array[@workflow.Run] = [],
) -> @conversation_overview.BackgroundTasks? {
  @conversation_overview.BackgroundTasks::from_listing(
    jobs~,
    more_jobs~,
    workflows~,
  )
}

///|
test "running commands and subagents are listed, ended ones counted" {
  guard summarize(more_jobs=true, [
      job("npm run dev", running=true),
      job("subagent", running=true, agent=("parent-sr-9", "map the code")),
      job("make", running=false),
    ])
    is Some(tasks) else {
    fail("a running job should show the card")
  }
  assert_eq(tasks.jobs, [{ command: "npm run dev", started_at_ms: 1000L, }])
  assert_eq(tasks.subagents, ["explore: map the code"])
  assert_eq(tasks.running(), 2)
  assert_eq(tasks.finished, 1)
  assert_true(tasks.more_finished)
  assert_true(tasks.in_jobs)
  // With nothing running, there is no card.
  assert_true(summarize([job("make", running=false)]) is None)
}

///|
test "a workflow's subagent that is also a job is one task" {
  let workflows = @workflow.child_closed(
    workflow(),
    id="sr-2",
    status="ok",
    steps=3,
    tokens=10,
  )
  guard summarize(workflows~, [
      job("subagent", running=true, agent=("parent-sr-1", "a")),
    ])
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
  guard summarize(workflows=workflow(), []) is Some(tasks) else {
    fail("running workflow children should show the card")
  }
  assert_eq(tasks.subagents, ["review: a", "review: b"])
  assert_false(tasks.in_jobs)
  // A closed run's unfinished children will not finish: nothing runs.
  assert_true(
    summarize(workflows=@workflow.closed(workflow(), id="wf-1"), []) is None,
  )
}
