///|
/// A worker's worktree as `job_output` shows it is the state its job ended
/// with, which integrating or discarding changes later: the reader is told
/// so, and where the current state is.
test "a worker's output says its worktree state is as its job ended" {
  let info : @protocol.SubagentInfo = {
    kind: "worker",
    label: "add b",
    session: "parent-sr-1",
    launch: Direct,
    outcome: Some(Captured),
    usage: None,
    report: None,
    workspace: Worktree({
      name: "add-b",
      path: "/repo/.worktrees/add-b",
      branch: "openseek/add-b--1a2b3c4d-sr-1",
      base: "ba5e",
      allowed_paths: ["lib"],
      state: Committed(commit="c0ffee"),
    }),
  }
  guard subagent_output("job-1", info, false, None) is Respond(output) else {
    fail("expected a response")
  }
  assert_true(
    output.content.contains(
      "when its job ended it was committed as c0ffee, ready to integrate",
    ),
    msg=output.content,
  )
  assert_true(output.content.contains("worktree (action=\"list\")"))
}
