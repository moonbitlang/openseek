///|
test "parse simple moon command" {
  guard @shell_parse.parse_for_policy("moon check --target native")
    is Simple(commands) else {
    fail("expected simple command")
  }
  assert_eq(commands.length(), 1)
  assert_true(commands[0].argv == ["moon", "check", "--target", "native"])
  assert_eq(commands[0].env.length(), 0)
  assert_eq(commands[0].redirects.length(), 0)
  assert_true(@shell_parse.contains_command(Simple(commands), "moon"))
}

///|
test "parse cd then moon as separate top level commands" {
  guard @shell_parse.parse_for_policy("cd pkg/foo && moon test --target native")
    is Simple(commands) else {
    fail("expected simple compound command")
  }
  assert_eq(commands.length(), 2)
  assert_true(commands[0].argv == ["cd", "pkg/foo"])
  assert_true(commands[1].argv == ["moon", "test", "--target", "native"])
  assert_true(commands[0].separator_before is None)
  assert_true(commands[1].separator_before is Some("&&"))
  assert_true(commands[0].command_index() == Some(0))
  assert_true(commands[1].command_index() == Some(0))
}

///|
#cfg(not(platform="windows"))
test "parse quotes and backslash escapes without expansion" {
  guard @shell_parse.parse_for_policy(
      "moon run cmd/main -- \"a b\" 'c$d' escaped\\ space",
    )
    is Simple(commands) else {
    fail("expected quoted command")
  }
  assert_eq(commands.length(), 1)
  assert_true(
    commands[0].argv ==
    ["moon", "run", "cmd/main", "--", "a b", "c$d", "escaped space"],
  )
}

///|
#cfg(platform="windows")
test "parse Windows path backslashes as literal characters" {
  guard @shell_parse.parse_for_policy("moon -C .\\pkg fmt") is Simple(commands) else {
    fail("expected Windows path command")
  }
  assert_eq(commands.length(), 1)
  assert_true(commands[0].argv == ["moon", "-C", ".\\pkg", "fmt"])
}

///|
test "preserve empty quoted words" {
  guard @shell_parse.parse_for_policy("cmd \"\" '' arg") is Simple(commands) else {
    fail("expected empty quoted words")
  }
  assert_eq(commands.length(), 1)
  assert_true(commands[0].argv == ["cmd", "", "", "arg"])
  guard @shell_parse.parse_for_policy("\"\" moon") is Simple(empty_name) else {
    fail("expected empty command word")
  }
  assert_true(empty_name[0].argv == ["", "moon"])
  assert_true(!@shell_parse.contains_command(Simple(empty_name), "moon"))
}

///|
test "parse environment assignments and redirects" {
  guard @shell_parse.parse_for_policy(
      "FOO=bar JSON=a=b moon run cmd/main > out.json 2>> err.log 2>&1",
    )
    is Simple(commands) else {
    fail("expected command with env and redirects")
  }
  assert_eq(commands.length(), 1)
  assert_true(
    commands[0].env ==
    [{ name: "FOO", value: "bar", }, { name: "JSON", value: "a=b", }],
  )
  assert_true(commands[0].argv == ["moon", "run", "cmd/main"])
  assert_true(
    commands[0].redirects ==
    [
      { op: ">", target: "out.json", },
      { op: "2>>", target: "err.log", },
      { op: "2>&", target: "1", },
    ],
  )
}

///|
#cfg(not(platform="windows"))
test "parse quoted and escaped environment assignment values" {
  guard @shell_parse.parse_for_policy("FOO=\"bar baz\" PATH=\\~/bin moon check")
    is Simple(commands) else {
    fail("expected quoted assignment values")
  }
  assert_eq(commands.length(), 1)
  assert_true(
    commands[0].env ==
    [{ name: "FOO", value: "bar baz", }, { name: "PATH", value: "~/bin", }],
  )
  assert_true(commands[0].argv == ["moon", "check"])
  guard @shell_parse.parse_for_policy("FOO=bar\\ baz moon check")
    is Simple(escaped) else {
    fail("expected escaped assignment value")
  }
  assert_true(escaped[0].env == [{ name: "FOO", value: "bar baz", }])
  assert_true(escaped[0].argv == ["moon", "check"])
  guard @shell_parse.parse_for_policy("HOME=\"~\" moon check")
    is Simple(quoted_tilde) else {
    fail("expected quoted tilde assignment value")
  }
  assert_true(quoted_tilde[0].env == [{ name: "HOME", value: "~", }])
  assert_true(quoted_tilde[0].argv == ["moon", "check"])
}

///|
test "parse fd qualified input redirects" {
  guard @shell_parse.parse_for_policy("cmd 0<input 2<err.log")
    is Simple(commands) else {
    fail("expected fd qualified input redirects")
  }
  assert_eq(commands.length(), 1)
  assert_true(commands[0].argv == ["cmd"])
  assert_true(
    commands[0].redirects ==
    [{ op: "0<", target: "input", }, { op: "2<", target: "err.log", }],
  )
}

///|
test "preserve spaced numeric arguments before redirects" {
  guard @shell_parse.parse_for_policy("cmd 2 < input 3 > out")
    is Simple(commands) else {
    fail("expected spaced numeric arguments and redirects")
  }
  assert_eq(commands.length(), 1)
  assert_true(commands[0].argv == ["cmd", "2", "3"])
  assert_true(
    commands[0].redirects ==
    [{ op: "<", target: "input", }, { op: ">", target: "out", }],
  )
  guard @shell_parse.parse_for_policy("cmd 2>out 3>>err") is Simple(attached) else {
    fail("expected attached fd redirects")
  }
  assert_true(attached[0].argv == ["cmd"])
  assert_true(
    attached[0].redirects ==
    [{ op: "2>", target: "out", }, { op: "3>>", target: "err", }],
  )
}

///|
test "parse append both and fd duplicate redirects" {
  guard @shell_parse.parse_for_policy("cmd &>>out <&3 >| forced 4<>rw")
    is Simple(commands) else {
    fail("expected append-both, fd duplicate, and read-write redirects")
  }
  assert_eq(commands.length(), 1)
  assert_true(commands[0].argv == ["cmd"])
  assert_true(
    commands[0].redirects ==
    [
      { op: "&>>", target: "out", },
      { op: "<&", target: "3", },
      { op: ">|", target: "forced", },
      { op: "4<>", target: "rw", },
    ],
  )
}

///|
#cfg(not(platform="windows"))
test "keep quoted words out of special shell grammar" {
  guard @shell_parse.parse_for_policy("cmd \"2\"<input") is Simple(commands) else {
    fail("expected quoted numeric argument")
  }
  assert_true(commands[0].argv == ["cmd", "2"])
  assert_true(commands[0].redirects == [{ op: "<", target: "input", }])
  assert_true(@shell_parse.parse_for_policy("A\"\"=x env") is TooComplex(_))
  assert_true(@shell_parse.parse_for_policy("A\\=x env") is TooComplex(_))
  assert_true(@shell_parse.parse_for_policy("\"A\"=x env") is TooComplex(_))
}

///|
test "detect env wrapper command name" {
  guard @shell_parse.parse_for_policy("env FOO=bar moon check")
    is Simple(commands) else {
    fail("expected env wrapper")
  }
  assert_eq(commands.length(), 1)
  assert_true(commands[0].command_name() == Some("moon"))
  assert_true(commands[0].command_index() == Some(2))
  assert_true(@shell_parse.contains_command(Simple(commands), "moon"))
  guard @shell_parse.parse_for_policy("env -- FOO=bar moon check")
    is Simple(dash_dash_commands) else {
    fail("expected env -- wrapper")
  }
  assert_true(dash_dash_commands[0].command_name() == Some("moon"))
  assert_true(dash_dash_commands[0].command_index() == Some(3))
  assert_true(@shell_parse.contains_command(Simple(dash_dash_commands), "moon"))
}

///|
test "env options are only recognized before assignments" {
  guard @shell_parse.parse_for_policy("env FOO=bar -i moon check")
    is Simple(after_assignment) else {
    fail("expected env command after assignment")
  }
  assert_true(after_assignment[0].command_name() == Some("-i"))
  assert_true(after_assignment[0].command_index() == Some(2))
  assert_true(!@shell_parse.contains_command(Simple(after_assignment), "moon"))
  guard @shell_parse.parse_for_policy("env FOO=bar -- moon check")
    is Simple(after_dash_dash) else {
    fail("expected env command after assignment before dash dash")
  }
  assert_true(after_dash_dash[0].command_name() == Some("--"))
  assert_true(after_dash_dash[0].command_index() == Some(2))
  assert_true(!@shell_parse.contains_command(Simple(after_dash_dash), "moon"))
  guard @shell_parse.parse_for_policy("env -i FOO=bar moon check")
    is Simple(before_assignment) else {
    fail("expected env option before assignment")
  }
  assert_true(before_assignment[0].command_name() == Some("moon"))
  assert_true(before_assignment[0].command_index() == Some(3))
  assert_true(@shell_parse.contains_command(Simple(before_assignment), "moon"))
}

///|
test "detect command wrapper and keep unknown env options conservative" {
  guard @shell_parse.parse_for_policy("command moon check") is Simple(commands) else {
    fail("expected command wrapper")
  }
  assert_eq(commands.length(), 1)
  assert_true(commands[0].command_name() == Some("moon"))
  assert_true(commands[0].command_index() == Some(1))
  assert_true(@shell_parse.contains_command(Simple(commands), "moon"))
  guard @shell_parse.parse_for_policy("command -- moon check")
    is Simple(dash_dash_commands) else {
    fail("expected command -- wrapper")
  }
  assert_true(dash_dash_commands[0].command_name() == Some("moon"))
  assert_true(dash_dash_commands[0].command_index() == Some(2))
  assert_true(@shell_parse.contains_command(Simple(dash_dash_commands), "moon"))
  guard @shell_parse.parse_for_policy("command -p moon check")
    is Simple(path_commands) else {
    fail("expected command -p wrapper")
  }
  assert_true(path_commands[0].command_name() == Some("moon"))
  assert_true(path_commands[0].command_index() == Some(2))
  assert_true(@shell_parse.contains_command(Simple(path_commands), "moon"))
  guard @shell_parse.parse_for_policy("command -v moon")
    is Simple(lookup_commands) else {
    fail("expected command -v lookup")
  }
  assert_true(lookup_commands[0].command_name() == Some("command"))
  assert_true(lookup_commands[0].command_index() == Some(0))
  assert_true(!@shell_parse.contains_command(Simple(lookup_commands), "moon"))
  guard @shell_parse.parse_for_policy("env -u FOO moon check")
    is Simple(env_commands) else {
    fail("expected env option wrapper to parse")
  }
  assert_true(env_commands[0].command_name() == Some("moon"))
  assert_true(env_commands[0].command_index() == Some(3))
  assert_true(@shell_parse.contains_command(Simple(env_commands), "moon"))
  guard @shell_parse.parse_for_policy("env -S 'moon check'")
    is Simple(complex_env_commands) else {
    fail("expected complex env option wrapper to parse")
  }
  assert_true(complex_env_commands[0].command_name() == Some("env"))
  assert_true(complex_env_commands[0].command_index() == Some(0))
  assert_true(
    !@shell_parse.contains_command(Simple(complex_env_commands), "moon"),
  )
  guard @shell_parse.parse_for_policy("env -C /tmp moon check")
    is Simple(env_chdir_commands) else {
    fail("expected env chdir wrapper to parse")
  }
  assert_true(env_chdir_commands[0].command_name() == Some("env"))
  assert_true(env_chdir_commands[0].command_index() == Some(0))
  assert_true(
    !@shell_parse.contains_command(Simple(env_chdir_commands), "moon"),
  )
}

///|
#cfg(not(platform="windows"))
test "parse safe quoted glob and escaped dollar as literals" {
  guard @shell_parse.parse_for_policy(
      "moon test \"*.mbt\" '${NOT_EXPANDED}' \"\\$literal\"",
    )
    is Simple(commands) else {
    fail("expected quoted literals")
  }
  assert_true(
    commands[0].argv == ["moon", "test", "*.mbt", "${NOT_EXPANDED}", "$literal"],
  )
}

///|
test "parse shell comments without losing visible commands" {
  guard @shell_parse.parse_for_policy("moon check # trailing note")
    is Simple(one_line) else {
    fail("expected trailing comment to be ignored")
  }
  assert_eq(one_line.length(), 1)
  assert_true(one_line[0].argv == ["moon", "check"])
  guard @shell_parse.parse_for_policy(
      "moon check # first command\n# blank comment\nmoon test",
    )
    is Simple(multi_line) else {
    fail("expected comments to preserve newline command separation")
  }
  assert_eq(multi_line.length(), 2)
  assert_true(multi_line[0].argv == ["moon", "check"])
  assert_true(multi_line[1].argv == ["moon", "test"])
  assert_true(multi_line[1].separator_before is Some(";"))
  guard @shell_parse.parse_for_policy("echo a#b # trailing note")
    is Simple(literal_hash) else {
    fail("expected hash inside word to remain literal")
  }
  assert_true(literal_hash[0].argv == ["echo", "a#b"])
  assert_true(
    @shell_parse.parse_for_policy("moon check && # note") is SyntaxError(_),
  )
  assert_true(
    @shell_parse.parse_for_policy("printf x > # note") is SyntaxError(_),
  )
}

///|
test "parse newlines without duplicate separators" {
  guard @shell_parse.parse_for_policy("moon fmt;\n") is Simple(trailing) else {
    fail("expected trailing separator before newline")
  }
  assert_eq(trailing.length(), 1)
  assert_true(trailing[0].argv == ["moon", "fmt"])
  guard @shell_parse.parse_for_policy("moon fmt\n\nmoon test")
    is Simple(blank_line) else {
    fail("expected blank line between commands")
  }
  assert_eq(blank_line.length(), 2)
  assert_true(blank_line[0].argv == ["moon", "fmt"])
  assert_true(blank_line[1].argv == ["moon", "test"])
  assert_true(blank_line[1].separator_before is Some(";"))
  guard @shell_parse.parse_for_policy("cd ./pkg &&\nmoon fmt")
    is Simple(and_newline) else {
    fail("expected newline after && to continue compound command")
  }
  assert_eq(and_newline.length(), 2)
  assert_true(and_newline[0].argv == ["cd", "./pkg"])
  assert_true(and_newline[1].argv == ["moon", "fmt"])
  assert_true(and_newline[1].separator_before is Some("&&"))
}

///|
test "parse pipes and conditionals as visible top level commands" {
  guard @shell_parse.parse_for_policy("moon check 2>&1 | tee out.log || true")
    is Simple(commands) else {
    fail("expected pipeline and conditional commands")
  }
  assert_eq(commands.length(), 3)
  assert_true(commands[0].argv == ["moon", "check"])
  assert_true(commands[0].redirects == [{ op: "2>&", target: "1", }])
  assert_true(commands[1].argv == ["tee", "out.log"])
  assert_true(commands[2].argv == ["true"])
  assert_true(commands[0].separator_before is None)
  assert_true(commands[1].separator_before is Some("|"))
  assert_true(commands[2].separator_before is Some("||"))
  assert_true(@shell_parse.contains_command(Simple(commands), "moon"))
}

///|
test "return syntax errors for dangling operators and redirects" {
  for
    cmd in [
      "moon check &&", "moon check >", "&& moon check", "moon 'unterminated",
    ] {
    assert_true(@shell_parse.parse_for_policy(cmd) is SyntaxError(_), msg=cmd)
  }
}

///|
#cfg(not(platform="windows"))
test "return too complex for runtime expansion and shell structures" {
  for
    cmd in [
      "cd \"$(pwd)\" && moon check", "TOOL=moon; $TOOL check", "(cd pkg && moon check)",
      "for f in file; do moon check; done", "for f in *.mbt; do moon check; done",
      "moon test *.mbt", "moon check <<EOF", "moon \\\ncheck", "eval 'moon check'",
      "exit 0; moon fmt", "command exit 0; moon fmt", "command -p exit 0; moon fmt",
      "HOME=~ cmd", "PATH=/bin:~/bin cmd", "HOME=~/\"quoted\" cmd",
    ] {
    assert_true(@shell_parse.parse_for_policy(cmd) is TooComplex(_), msg=cmd)
  }
  assert_true(
    @shell_parse.parse_for_policy("command -v exit; moon fmt") is Simple(_),
  )
}

///|
test "allow trailing semicolon and blank input" {
  guard @shell_parse.parse_for_policy("moon check;") is Simple(commands) else {
    fail("expected trailing semicolon to be accepted")
  }
  assert_eq(commands.length(), 1)
  guard @shell_parse.parse_for_policy("   \t ") is Simple(blank) else {
    fail("expected blank command to parse")
  }
  assert_eq(blank.length(), 0)
}

///|
/// The `builtin` wrapper's boundaries, which the common `builtin cd …` cases
/// never reach: a bare wrapper with nothing to run, and a `--` end-of-options
/// marker with and without a command behind it.
test "builtin wrapper resolves its own edge shapes" {
  fn index_of(command : String) -> Int? raise {
    guard @shell_parse.parse_for_policy(command) is Simple(commands) else {
      fail("expected simple command")
    }
    commands[0].command_index()
  }

  fn name_of(command : String) -> String? raise {
    guard @shell_parse.parse_for_policy(command) is Simple(commands) else {
      fail("expected simple command")
    }
    commands[0].command_name()
  }

  // A command behind `--` is the effective command.
  assert_true(index_of("builtin -- cd pkg") is Some(2))
  assert_true(name_of("builtin -- cd pkg") is Some("cd"))
  // `--` with nothing behind it leaves the wrapper itself as the command.
  assert_true(index_of("builtin --") is Some(0))
  assert_true(name_of("builtin --") is Some("builtin"))
  // A bare wrapper likewise resolves to itself, not to None.
  assert_true(index_of("builtin") is Some(0))
  assert_true(name_of("builtin") is Some("builtin"))
  // Without `--`, the very next word is the command.
  assert_true(index_of("builtin cd pkg") is Some(1))
  assert_true(name_of("builtin cd pkg") is Some("cd"))
  // `command` and `env` wrappers keep their own resolution.
  assert_true(index_of("command cd pkg") is Some(1))
  assert_true(index_of("env FOO=bar cd pkg") is Some(2))
}

///|
/// `builtin`/`command` can hide a shell control word from the too-complex
/// check, so the wrapper's edge shapes matter here too: `--` with a control
/// word behind it must still be seen, and a wrapper with nothing behind it
/// must not be mistaken for one.
test "control word detection sees through builtin wrappers" {
  // The wrapper is seen through with and without `--`, so the control word
  // behind it is still refused.
  assert_true(
    @shell_parse.parse_for_policy("builtin -- while true; do x; done")
    is TooComplex(_),
  )
  assert_true(
    @shell_parse.parse_for_policy("builtin while true; do x; done")
    is TooComplex(_),
  )
  // Nothing behind the wrapper is no control word at all.
  assert_true(@shell_parse.parse_for_policy("builtin --") is Simple(_))
  assert_true(@shell_parse.parse_for_policy("builtin") is Simple(_))
  // A plain command behind the wrapper stays simple.
  assert_true(@shell_parse.parse_for_policy("builtin -- cd pkg") is Simple(_))
}
