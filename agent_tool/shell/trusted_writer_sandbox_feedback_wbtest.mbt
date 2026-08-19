///|
test "sandbox attributes a Moon info interface-copy denial" {
  let output = "ERROR Failed to copy generated mbti file from /repo/_build/wasm/debug/check/argparse/argparse.mbti to /repo/argparse/pkg.generated.mbti: Operation not permitted (os error 1)"
  let feedback = shell_sandbox_denial_feedback(true, false, output)
  assert_true(feedback.contains("standalone static command"))
  assert_true(feedback.contains("Run `moon info` in its own shell call"))
  assert_true(feedback.contains("concrete literal values"))
  assert_false(
    feedback.contains("make source changes with line-anchored `edit`"),
  )
}

///|
test "sandbox keeps generic guidance when the denied writer is unknown" {
  let feedback = shell_sandbox_denial_feedback(
    true, false, "./generator: main.mbt: Operation not permitted",
  )
  assert_eq(feedback, SandboxSourceWriteFeedback)
}

///|
test "sandbox keeps generic guidance for mixed source-write denials" {
  let output =
    #|ERROR Failed to copy generated mbti file from /repo/_build/pkg.mbti to /repo/pkg.generated.mbti: Operation not permitted (os error 1)
    #|sh: main.mbt: Operation not permitted
  assert_eq(
    shell_sandbox_denial_feedback(true, false, output),
    SandboxSourceWriteFeedback,
  )
}

///|
test "sandbox does not recommend Moon info retry in read-only review mode" {
  let output = "ERROR Failed to copy generated mbti file from /repo/_build/pkg.mbti to /repo/pkg.generated.mbti: Operation not permitted (os error 1)"
  let feedback = shell_sandbox_denial_feedback(true, true, output)
  assert_true(feedback.contains("read-only review mode"))
  assert_true(feedback.contains("Do not retry it here"))
  assert_true(feedback.contains("outside review mode"))
  assert_false(feedback.contains("Run `moon info` in its own shell call"))
}

///|
test "sandbox keeps generic guidance when standalone retry is still confined" {
  let output = "ERROR Failed to copy generated mbti file from /repo/_build/pkg.mbti to /repo/pkg.generated.mbti: Operation not permitted (os error 1)"
  assert_eq(
    shell_sandbox_denial_feedback(false, false, output),
    SandboxSourceWriteFeedback,
  )
}
