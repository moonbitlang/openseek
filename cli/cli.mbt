///|
/// Shared helpers for the command mains (`cmd/openseek`, the `eval` harness
/// mains, and the out-of-tree `openseek_tui` binary): accessors over
/// `@argparse.Matches`, the shared agent options, and the sanitizer every
/// command runs untrusted text through before printing it. Each main used to
/// carry its own byte-identical copies; keeping one copy here removes the risk
/// of the copies drifting apart. Error messages are part of each command's
/// contract and must not change when helpers move. This package is public (not
/// `internal`) because the terminal UI lives in its own module,
/// `moonbitlang/openseek_tui`, and imports it.

///|
/// Parse `input` as a strictly positive integer; `label` names the offending
/// option in the failure message.
pub fn parse_positive_int(input : String, label : String) -> Int raise {
  let parsed = @string.parse_int(input) catch {
    _ => fail("\{label} must be a positive integer, got: \{input}")
  }
  guard parsed > 0 else {
    fail("\{label} must be a positive integer, got: \{input}")
  }
  parsed
}

///|
test "parse_positive_int accepts positives and rejects zero, negatives, junk" {
  assert_eq(parse_positive_int("42", "--max-steps"), 42)
  for bad in ["0", "-3", "", "abc"] {
    try ignore(parse_positive_int(bad, "--max-steps")) catch {
      err => assert_true("\{err}".contains("must be a positive integer"))
    } noraise {
      _ => fail("expected \{bad} to be rejected")
    }
  }
}

///|
/// Collapse untrusted text to one terminal-safe line: leading and trailing
/// whitespace goes, interior whitespace runs become a single space, C0/C1
/// controls and DEL are dropped — ESC, CSI, OSC and friends render as terminal
/// commands, not text, so anything a session log, an MCP server or a config
/// file hands back must not be able to reach the terminal intact — and
/// anything past `limit` characters is elided with `…`.
pub fn terminal_safe_line(text : String, limit? : Int = 72) -> String {
  let out = StringBuilder()
  for ch in text.trim(); last_was_space = false, count = 0 {
    if count >= limit {
      out.write_char('…')
      break
    }
    if ch is (' ' | '\t' | '\n' | '\r') {
      if !last_was_space {
        out.write_char(' ')
        continue true, count + 1
      }
      continue true, count
    } else if ch.to_int() < 0x20 ||
      ch.to_int() == 0x7F ||
      (ch.to_int() >= 0x80 && ch.to_int() <= 0x9F) {
      continue last_was_space, count
    } else {
      out.write_char(ch)
      continue false, count + 1
    }
  }
  out.to_string()
}

///|
test "terminal_safe_line collapses whitespace, drops controls, elides at limit" {
  assert_eq(
    terminal_safe_line("  fix the \n\t streaming   bug  "),
    "fix the streaming bug",
  )
  // C0 (ESC), OSC and C1 (CSI) all disappear rather than reaching the terminal.
  assert_eq(
    terminal_safe_line("\u{1b}[31mred\u{1b}]0;title\u{7}\u{9b}31m text"),
    "[31mred]0;title31m text",
  )
  assert_eq(terminal_safe_line("abcdef", limit=3), "abc…")
  assert_eq(terminal_safe_line("   "), "")
}

///|
/// Normalize a raised error's text for a one-line stderr report. argparse
/// already prefixes its own errors with `error: `, and some Moon failures carry
/// a `FAILED: ` marker, so strip those to avoid `error: error: …`. This is the
/// single sanitizer both command mains (`cmd/openseek` here and the
/// `openseek_tui` binary in `moonbitlang/openseek_tui`) run untrusted failure
/// text through.
pub fn failure_message(error_text : String) -> String {
  lexmatch error_text {
    (re"^error: ", after=message) => message.to_owned()
    // `(.|\n)*` is greedy across lines, so the remainder follows the LAST
    // marker occurrence — the same piece the split-and-take-last form chose.
    (re"^(.|\n)* FAILED: ", after=last) =>
      last.strip_suffix(")").unwrap_or(last).to_owned()
    _ => error_text
  }
}

///|
test "failure_message avoids duplicating argparse error prefix" {
  assert_eq(
    failure_message(
      "error: unexpected argument '--xxy' found\n\nUsage: openseek",
    ),
    "unexpected argument '--xxy' found\n\nUsage: openseek",
  )
}
