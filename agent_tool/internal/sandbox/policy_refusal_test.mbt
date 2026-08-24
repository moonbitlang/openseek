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
  assert_true(feedback.contains("write outside its own"))
  assert_true(feedback.contains("spawn allowlist"))
  // And it ends on the move that answers the refusals that actually happen —
  // POSIX utilities with a one-line MoonBit form.
  assert_true(feedback.contains("MoonBit replacement"))
}

///|
/// The sanctioned way past a refusal is named AT the refusal, not only in a
/// tool description read once at the top of a session — that is the moment the
/// model is deciding what to do instead, and the moment it otherwise
/// reconstructs the refused command out of allowed parts without saying so.
test "policy guidance names escalation only where it exists" {
  let without = @sandbox.policy_refusal_feedback
  assert_false(without.contains("escalated"))
  let with_escalation = @sandbox.policy_refusal_with_escalation
  assert_true(with_escalation.contains("`escalated: true`"))
  // Pinned to the snippet already written, and to one attempt: naming an
  // escape at a refusal risks making the escape the first move. That same
  // wording is why only a foreground report may carry it — it says nothing
  // ran, which a background job's refusal cannot claim.
  assert_true(with_escalation.contains("this exact snippet ONCE"))
  // The refusal itself reads identically either way — only the answer differs.
  assert_true(with_escalation.has_prefix(without))
}
