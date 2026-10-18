///|
/// A worker's output says where its change is and the plain git that
/// reviews and takes it: the engine handed it over when the worker ended.
test "a worker's output says where its change is and how to take it" {
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
  // Where the change is, and the plain git that takes it.
  assert_true(
    output.content.contains("commit c0ffee on branch openseek/add-b"),
    msg=output.content,
  )
  assert_true(output.content.contains("git cherry-pick c0ffee"))
  assert_true(output.content.contains("git diff ba5e c0ffee"))
}
