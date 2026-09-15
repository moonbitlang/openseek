///|
test "approval values parse" {
  assert_true(try_approval_policy("never", interactive=false) is Ok(Never))
  assert_true(try_approval_policy("always", interactive=false) is Ok(Always))
  assert_true(try_approval_policy("ask", interactive=true) is Ok(Ask))
}

///|
/// Refused where it is written, not five minutes later at a deadline nobody
/// was ever going to beat.
test "ask is refused where nobody can answer" {
  guard try_approval_policy("ask", interactive=false) is Err(message) else {
    fail("--approval ask should be refused without a controller")
  }
  assert_true(message.contains("needs a controller"))
  assert_true(message.contains("never"))
  assert_true(message.contains("always"))
}

///|
test "an unknown approval value names the accepted ones" {
  guard try_approval_policy("yolo", interactive=true) is Err(message) else {
    fail("an unknown --approval value should be refused")
  }
  assert_true(message.contains("ask, never, or always"))
}
