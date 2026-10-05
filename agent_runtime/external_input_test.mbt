///|
async test "outside input joins the steering queue in arrival order" {
  let batches = [
    [
      @agent_runtime.SteerInput::Prompt(
        Content([Text("first")]),
        submission_id=Some("m1"),
      ),
    ],
    [],
    [
      Prompt(Content([Text("second")]), submission_id=Some("m2")),
      Notice("third"),
    ],
  ]
  let mut asked = 0
  let runtime = @agent_runtime.AgentRuntime(external_input=() => {
    asked += 1
    batches.get(asked - 1).unwrap_or([])
  })
  // Nothing is asked of the source until the loop pulls.
  assert_eq(runtime.drain_steers().length(), 0)
  assert_eq(asked, 0)
  runtime.queue_steer(Command("typed meanwhile", submission_id=None))
  runtime.pull_external_input()
  runtime.pull_external_input()
  runtime.pull_external_input()
  let steers = runtime.drain_steers()
  assert_true(
    steers
    is [
      Command("typed meanwhile", ..),
      Prompt(Content([Text("first")]), submission_id=Some("m1")),
      Prompt(Content([Text("second")]), submission_id=Some("m2")),
      Notice("third"),
    ],
  )
}

///|
/// A failure is held for the loop to report, never queued: queued input
/// overrides a completion, and a broken side channel must not.
async test "a source that fails is dropped without steering the turn" {
  let mut asked = 0
  let runtime = @agent_runtime.AgentRuntime(external_input=() => {
    asked += 1
    fail("inbox unreadable")
  })
  runtime.pull_external_input()
  runtime.pull_external_input()
  assert_eq(asked, 1)
  assert_eq(runtime.drain_steers().length(), 0)
  guard runtime.take_external_input_failure() is Some(reason) else {
    fail("expected the failure to be held")
  }
  assert_true(reason.contains("inbox unreadable"))
  assert_true(runtime.take_external_input_failure() is None)
}

///|
async test "a runtime with no source pulls nothing" {
  let runtime = @agent_runtime.AgentRuntime()
  runtime.pull_external_input()
  assert_eq(runtime.drain_steers().length(), 0)
}
