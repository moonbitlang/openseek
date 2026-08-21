///|
/// The two wordings are pinned as moonrun actually prints them, captured from a
/// run under a policy rather than paraphrased. A refusal is recognized by these
/// strings alone, so a paraphrase here would silently stop matching production
/// output while the test kept passing.
test "a policy refusal is recognized by the runtime's own wording" {
  // A blocked access: moonrun's line, then the error the guest sees.
  assert_true(
    @sandbox.output_reports_policy_refusal(
      "Sandbox policy blocked file write: \"/private/tmp/escape.txt\"\n",
    ),
  )
  assert_true(
    @sandbox.output_reports_policy_refusal(
      "Sandbox policy blocked file read: \"/etc/hosts\"\n",
    ),
  )
  // A refused spawn: no line of moonrun's own, so the call itself is the marker.
  assert_true(
    @sandbox.output_reports_policy_refusal(
      "OSError(\"@process.spawn(): Permission denied\")\n",
    ),
  )
  // A permission error this tool did not cause reads as what it is. Both of
  // these were denials under the old path-subtracting detector, which called
  // any "Permission denied" outside a granted root its own.
  assert_false(
    @sandbox.output_reports_policy_refusal(
      "OSError(\"@fs.open(): \\\"/etc/shadow\\\": Permission denied\")\n",
    ),
  )
  assert_false(
    @sandbox.output_reports_policy_refusal("error: Permission denied\n"),
  )
  assert_false(@sandbox.output_reports_policy_refusal(""))
}

///|
/// The guidance has to cover both rules, because a refused spawn carries no path
/// and reading it as a blocked write once sent the model to debug one.
test "policy guidance names both rules that produce a refusal" {
  let feedback = @sandbox.policy_refusal_feedback
  assert_true(feedback.contains("left the workspace"))
  assert_true(feedback.contains("spawn allowlist"))
  // And it ends on the move that answers the refusals that actually happen —
  // POSIX utilities with a one-line MoonBit form.
  assert_true(feedback.contains("MoonBit replacement"))
}
