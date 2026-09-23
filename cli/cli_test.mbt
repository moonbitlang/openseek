///|
test "parse_positive_int accepts positives and rejects zero, negatives, junk" {
  assert_eq(@cli.parse_positive_int("42", "--max-steps"), 42)
  for bad in ["0", "-3", "", "abc"] {
    try ignore(@cli.parse_positive_int(bad, "--max-steps")) catch {
      err => assert_true("\{err}".contains("must be a positive integer"))
    } noraise {
      _ => fail("expected \{bad} to be rejected")
    }
  }
}

///|
test "terminal_safe_line collapses whitespace, drops controls, elides at limit" {
  assert_eq(
    @cli.terminal_safe_line("  fix the \n\t streaming   bug  "),
    "fix the streaming bug",
  )
  // C0 (ESC), OSC and C1 (CSI) all disappear rather than reaching the terminal.
  assert_eq(
    @cli.terminal_safe_line("\u{1b}[31mred\u{1b}]0;title\u{7}\u{9b}31m text"),
    "[31mred]0;title31m text",
  )
  assert_eq(@cli.terminal_safe_line("abcdef", limit=3), "abc…")
  assert_eq(@cli.terminal_safe_line("   "), "")
}

///|
test "failure_message avoids duplicating argparse error prefix" {
  assert_eq(
    @cli.failure_message(
      "error: unexpected argument '--xxy' found\n\nUsage: openseek",
    ),
    "unexpected argument '--xxy' found\n\nUsage: openseek",
  )
}
