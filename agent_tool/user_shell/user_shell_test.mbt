///|
#cfg(not(platform="windows"))
async test "collect_shell_output captures merged output and the exit code" {
  let output = @user_shell.collect_shell_output(
    "printf %s 'out'; printf %s 'err' >&2; exit 3",
  )
  assert_eq(output.exit_code, Some(3))
  assert_eq(output.text, "outerr")
  assert_false(output.output_limit_reached)
}

///|
#cfg(not(platform="windows"))
async test "collect_shell_output runs in cwd" {
  let output = @user_shell.collect_shell_output("pwd", cwd="/")
  assert_eq(output.text, "/\n")
}

///|
#cfg(not(platform="windows"))
async test "collect_shell_output runs with exactly the given environment" {
  let output = @user_shell.collect_shell_output(
    "printf '%s|%s' \"$USER_SHELL_PROBE\" \"${HOME-unset}\"",
    env={ "USER_SHELL_PROBE": "probe", "PATH": "/usr/bin:/bin" },
  )
  assert_eq(output.text, "probe|unset")
}

///|
#cfg(not(platform="windows"))
async test "collect_shell_output gives the command a closed stdin" {
  let output = @user_shell.collect_shell_output("cat; echo done")
  assert_eq(output.exit_code, Some(0))
  assert_eq(output.text, "done\n")
}

///|
#cfg(not(platform="windows"))
async test "encode follows shell output fields on Unix" {
  let output = @user_shell.collect_shell_output("printf %s 'abc'")
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
  let truncated = @user_shell.collect_shell_output(
    "printf %s 'abcdef'",
    max_output_chars=3,
  )
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
  assert_eq(
    @command_context.encode("printf %s 'abcdef'", Ok(truncated)),
    expected,
  )
}

///|
#cfg(platform="windows")
async test "encode follows shell output fields on Windows" {
  let output = @user_shell.collect_shell_output("[Console]::Out.Write('abc')")
  let expected =
    #|<user_shell_command>
    #|<command>
    #|[Console]::Out.Write('abc')
    #|</command>
    #|<result>
    #|exit=0
    #|abc
    #|</result>
    #|</user_shell_command>
  assert_eq(
    @command_context.encode("[Console]::Out.Write('abc')", Ok(output)),
    expected,
  )
}
