///|
#cfg(not(platform="windows"))
async test "terminal login uses the selected executable and isolated home with shell quoting" {
  let root = @fs.tmpdir(prefix="codex-terminal-login-")
  defer @fs.rmdir(root, recursive=true)
  let script = root + "/chosen Codex ' $literal"
  let home = root + "/identity ' $literal"
  let source =
    #|#!/bin/sh
    #|if [ "$1" = login ] && [ "$2" = --help ]; then
    #|  printf '%s' 'Usage: codex login --device-auth'; exit 0
    #|fi
    #|test "$1" = login && test "$2" = --device-auth && test "$#" = 2 || exit 11
    #|printf '%s' "$CODEX_HOME" > "$CODEX_HOME/login-home"
    #|printf '%s' "$0" > "$CODEX_HOME/login-executable"
  @fs.write_file(script, source, permission=0o700)
  let actor = @codex.Actor(CodexSettings(command=script, home=Some(Path(home))))
  let (command, device_auth) = actor.terminal_login_command()
  assert_true(device_auth)
  assert_false(@fs.exists(home + "/login-home"))
  let (code, _, _) = @processx.collect_output_no_stdin(
    "/bin/sh",
    ["-c", command],
    extra_env={ "CODEX_HOME": root + "/wrong-home" },
  )
  assert_eq(code, 0)
  assert_eq(
    @fs.read_file(home + "/login-home").text(),
    @pathx.Path(home).resolve().to_string(),
  )
  assert_eq(
    @fs.read_file(home + "/login-executable").text(),
    @pathx.Path(script).resolve().to_string(),
  )
  assert_false(@fs.exists(root + "/wrong-home"))
}

///|
#cfg(not(platform="windows"))
async test "terminal login refuses missing and unbounded CLI help" {
  let root = @fs.tmpdir(prefix="codex-terminal-capability-")
  defer @fs.rmdir(root, recursive=true)
  let script = root + "/codex"
  for
    (source, expected) in [
      ("#!/bin/sh\nhead -c 70000 /dev/zero\n", "exceeded 64 KiB"),
      ("#!/bin/sh\nexec sleep 30\n", "within 5 seconds"),
    ] {
    @fs.write_file(
      script,
      source,
      create_mode=CreateOrTruncate,
      permission=0o700,
    )
    let actor = @codex.Actor(
      CodexSettings(command=script, home=Some(Path(root + "/home"))),
    )
    try actor.terminal_login_command() catch {
      error =>
        assert_true(error.to_string().contains(expected), msg=error.to_string())
    } noraise {
      _ => fail("invalid CLI must not produce a login command")
    }
  }
  @fs.remove(script)
  let actor = @codex.Actor(
    CodexSettings(command=script, home=Some(Path(root + "/home"))),
  )
  try actor.terminal_login_command() catch {
    error => assert_true(error.to_string().contains(script))
  } noraise {
    _ => fail("missing explicit CLI must not fall back")
  }
}

///|
#cfg(not(platform="windows"))
async test "terminal login preserves the exact home when device auth is unavailable" {
  let root = @fs.tmpdir(prefix="codex-terminal-browser-")
  defer @fs.rmdir(root, recursive=true)
  let script = root + "/codex"
  @fs.write_file(
    script,
    "#!/bin/sh\nprintf '%s' 'Usage: login'\n",
    permission=0o700,
  )
  let actor = @codex.Actor(
    CodexSettings(command=script, home=Some(Path(root + "/home"))),
  )
  let (command, device_auth) = actor.terminal_login_command()
  assert_false(device_auth)
  assert_true(command.has_suffix(" login"))
  assert_true(command.contains(root + "/home"))
}
