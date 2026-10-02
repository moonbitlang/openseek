///|
test "encode carries the exit code and output of a finished command" {
  let output : @command_context.ShellOutput = {
    exit_code: Some(0),
    text: "abc",
    output_limit_reached: false,
  }
  let expected =
    #|<user_shell_command>
    #|<command>
    #|printf %s 'abc'
    #|</command>
    #|<result>
    #|exit=0
    #|abc
    #|</result>
    #|</user_shell_command>
  assert_eq(@command_context.encode("printf %s 'abc'", Ok(output)), expected)
}

///|
test "encode adds the truncation preamble when the output cap was hit" {
  let output : @command_context.ShellOutput = {
    exit_code: None,
    text: "abc",
    output_limit_reached: true,
  }
  let expected =
    #|<user_shell_command>
    #|<command>
    #|printf %s 'abcdef'
    #|</command>
    #|<result>
    #|exit=cancelled
    #|truncated=true
    #|output_limit_reached=true
    #|shown_chars=3
    #|max_output_chars=3
    #|abc
    #|</result>
    #|</user_shell_command>
  assert_eq(@command_context.encode("printf %s 'abcdef'", Ok(output)), expected)
}

///|
test "a command that could not run round-trips as a failed card" {
  let envelope = @command_context.encode("nope", Err(Failure("spawn failed")))
  guard @command_context.parse(envelope) is Some(parsed) else {
    fail("expected a well-formed envelope to parse")
  }
  assert_eq(parsed.command, "nope")
  assert_eq(parsed.exit, "failed")
  assert_true(parsed.output is [line] && line.contains("spawn failed"))
}

///|
test "a multi-line command and non-zero exit round-trip" {
  let output : @command_context.ShellOutput = {
    exit_code: Some(2),
    text: "one\ntwo",
    output_limit_reached: false,
  }
  let command = "echo one\necho two; exit 2"
  guard @command_context.parse(@command_context.encode(command, Ok(output)))
    is Some(parsed) else {
    fail("expected a well-formed envelope to parse")
  }
  assert_eq(parsed.command, command)
  assert_eq(parsed.exit, "2")
  assert_eq(parsed.output, ["one", "two"])
}

///|
test "parse recovers the command and output of an encoded envelope" {
  let envelope =
    #|<user_shell_command>
    #|<command>
    #|echo hi
    #|</command>
    #|<result>
    #|exit=0
    #|hi
    #|</result>
    #|</user_shell_command>
  guard @command_context.parse(envelope) is Some(parsed) else {
    fail("expected a well-formed envelope to parse")
  }
  assert_eq(parsed.command, "echo hi")
  assert_eq(parsed.exit, "0")
  assert_eq(parsed.output.join("\n"), "hi")
  assert_false(parsed.output_limit_reached)
}

///|
test "parse strips truncation metadata and flags the cap" {
  let envelope =
    #|<user_shell_command>
    #|<command>
    #|printf %s 'abcdef'
    #|</command>
    #|<result>
    #|exit=cancelled
    #|truncated=true
    #|output_limit_reached=true
    #|shown_chars=3
    #|max_output_chars=3
    #|abc
    #|</result>
    #|</user_shell_command>
  guard @command_context.parse(envelope) is Some(parsed) else {
    fail("expected a well-formed envelope to parse")
  }
  assert_eq(parsed.command, "printf %s 'abcdef'")
  assert_eq(parsed.exit, "cancelled")
  assert_eq(parsed.output.join("\n"), "abc")
  assert_true(parsed.output_limit_reached)
}

///|
test "parse keeps real output lines that merely look like truncation metadata" {
  // A non-truncated command whose own output begins with `key=value` lines that
  // share the metadata key names, but not the full four-line preamble. They are
  // real output and must survive — and the card must not be flagged truncated.
  let envelope =
    #|<user_shell_command>
    #|<command>
    #|cat config
    #|</command>
    #|<result>
    #|exit=0
    #|truncated=true
    #|shown_chars=5
    #|</result>
    #|</user_shell_command>
  guard @command_context.parse(envelope) is Some(parsed) else {
    fail("expected a well-formed envelope to parse")
  }
  assert_eq(parsed.exit, "0")
  assert_eq(parsed.output.join("\n"), "truncated=true\nshown_chars=5")
  assert_false(parsed.output_limit_reached)
}

///|
test "parse rejects an ordinary user message" {
  assert_true(@command_context.parse("just a normal prompt") is None)
}
