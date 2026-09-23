///|
/// Test helper: `--approval` through the real `run` tree, as a `Result`, so a
/// test can state both what a value parses to and what a refusal says.
fn try_approval_policy(
  argv : Array[String],
  interactive~ : Bool,
) -> Result[@execution.ApprovalPolicy, String] {
  Ok(
    @execution.approval_policy(
      @testkit.run_matches(argv=[..argv, "task"], env=Map([])),
      interactive~,
    ),
  ) catch {
    error => Err("\{error}")
  }
}

///|
test "approval values parse, and default to never" {
  assert_true(
    try_approval_policy(["--approval", "never"], interactive=false) is Ok(Never),
  )
  assert_true(
    try_approval_policy(["--approval", "always"], interactive=false)
    is Ok(Always),
  )
  assert_true(
    try_approval_policy(["--approval", "ask"], interactive=true) is Ok(Ask),
  )
  assert_true(try_approval_policy([], interactive=true) is Ok(Never))
}

///|
/// Refused where it is written, not five minutes later at a deadline nobody
/// was ever going to beat.
test "ask is refused where nobody can answer" {
  guard try_approval_policy(["--approval", "ask"], interactive=false)
    is Err(message) else {
    fail("--approval ask should be refused without a controller")
  }
  assert_true(message.contains("needs a controller"))
  assert_true(message.contains("never"))
  assert_true(message.contains("always"))
}

///|
test "an unknown approval value names the accepted ones" {
  guard try_approval_policy(["--approval", "yolo"], interactive=true)
    is Err(message) else {
    fail("an unknown --approval value should be refused")
  }
  assert_true(message.contains("ask, never, or always"))
}
