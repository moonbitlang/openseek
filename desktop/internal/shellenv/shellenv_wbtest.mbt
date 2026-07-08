///|
test "parse_probe_output extracts the marker-wrapped environment" {
  let mark = "__openseek_env_42__"
  let text = "p10k: warning\n\{mark}{\"PATH\":\"/opt/homebrew/bin:/usr/bin\",\"FOO\":\"a\\nb\"}\{mark}\ngoodbye\n"
  guard parse_probe_output(text, mark) is Some(env) else {
    fail("expected an environment")
  }
  assert_true(env.get("PATH") is Some("/opt/homebrew/bin:/usr/bin"))
  assert_true(env.get("FOO") is Some("a\nb"))
}

///|
test "parse_probe_output survives the mark leaking into the payload" {
  // zsh exports `_` as the last argument of the command line — the mark
  // itself — so the JSON payload can contain the mark. The greedy
  // first-to-last extraction must still capture the whole object.
  let mark = "__openseek_env_42__"
  let text = "\{mark}{\"_\":\"\{mark}\",\"PATH\":\"/usr/bin\"}\{mark}"
  guard parse_probe_output(text, mark) is Some(env) else {
    fail("expected an environment")
  }
  assert_true(env.get("PATH") is Some("/usr/bin"))
}

///|
test "parse_probe_output rejects noise without markers" {
  assert_true(parse_probe_output("no marks here", "__mark__") is None)
  assert_true(parse_probe_output("__mark__ only one", "__mark__") is None)
  assert_true(
    parse_probe_output("__mark__not json__mark__", "__mark__") is None,
  )
}

///|
test "session-local variables are not grafted" {
  assert_true(session_local("OPENSEEK_RESOLVING_ENVIRONMENT"))
  assert_true(session_local("_"))
  assert_true(session_local("SHLVL"))
  assert_true(session_local("PWD"))
  assert_true(session_local("OLDPWD"))
  assert_false(session_local("PATH"))
}

///|
test "shell_quote escapes embedded single quotes" {
  assert_eq(
    shell_quote("/Applications/My App.app/host"),
    "'/Applications/My App.app/host'",
  )
  assert_eq(shell_quote("it's"), "'it'\\''s'")
}
