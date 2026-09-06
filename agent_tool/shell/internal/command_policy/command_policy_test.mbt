///|
test "command policy allows moon subcommands through shell" {
  // moon check now runs through shell like every other moon subcommand.
  for
    cmd in [
      "moon check", "cd demo && moon check", "moon test", "moon run cmd/main", "moon info",
      "moon fmt", "moon build", "OPENSEEK_MODEL=x moon run cmd/main", "git status --short",
    ] {
    assert_true(
      @command_policy.moonbit_command_policy_error(cmd) is None,
      msg=cmd,
    )
  }
}

///|
test "command policy still redirects the moon_cmd tool name" {
  guard @command_policy.moonbit_command_policy_error("moon_cmd check")
    is Some(message) else {
    fail("expected moon_cmd to be redirected")
  }
  assert_true(message.contains("moon_cmd is not a shell command"))
}

///|
test "command policy detects moon_cmd in simple shell compounds" {
  for
    cmd in [
      "cd demo && moon_cmd check", "OPENSEEK_MODEL=x moon_cmd run cmd/main", "env OPENSEEK_MODEL=x moon_cmd check",
      "env -- OPENSEEK_MODEL=x moon_cmd check", "command moon_cmd check", "command -- moon_cmd check",
      "command -p moon_cmd check", "true || moon_cmd test", "moon_cmd check > out.log",
      "cd demo && moon_cmd check # trailing note", "true;\nmoon_cmd check",
    ] {
    guard @command_policy.moonbit_command_policy_error(cmd) is Some(message) else {
      fail("expected moon_cmd to be redirected for \{cmd}")
    }
    assert_true(message.contains("moon_cmd is not a shell command"))
  }
}

///|
test "command policy does not match moon_cmd as data" {
  for
    cmd in [
      "printf '%s\\n' moon_cmd", "echo moon_cmd | cat", "MOON_TOOL=moon_cmd moon check",
      "env OPENSEEK_MODEL=x -i moon_cmd check",
    ] {
    assert_true(
      @command_policy.moonbit_command_policy_error(cmd) is None,
      msg=cmd,
    )
  }
}

///|
test "command policy redirects sed in-place editing to the edit tool" {
  for
    cmd in [
      "sed -i 's/a/b/' file.mbt", "sed -i.bak 's/a/b/' file.mbt", "sed -i '' 's/a/b/' file.mbt",
      "sed --in-place 's/a/b/' f", "sed --in-place=.bak 's/a/b/' f", "sed -Ei 's/a/b/' f",
      "sed -ni 's/a/b/' f", "command sed -i 's/a/b/' f", "env FOO=bar sed -i 's/a/b/' f",
      "env -u FOO sed -i 's/a/b/' f", "env --unset FOO sed -i 's/a/b/' f", "cat f | sed -i 's/a/b/' f",
      "cd src && sed -i 's/a/b/' f", "'sed' -i 's/a/b/' f",
      // Path-qualified sed (Simple parse) is matched by basename.
       "/usr/bin/sed -i 's/a/b/' file.mbt", "./sed -i 's/a/b/' f",
    ] {
    guard @command_policy.moonbit_command_policy_error(cmd) is Some(message) else {
      fail("expected sed -i to be redirected for \{cmd}")
    }
    assert_true(message.contains("sed -i") && message.contains("edit"))
    assert_true(message.contains("line-anchored"))
    assert_false(message.contains("`write`"))
  }
}

///|
test "command policy does not block sed -i in too-complex (glob/heredoc) parses" {
  // Documented tradeoff: a globbed / heredoc / expansion `sed -i` parses as
  // TooComplex and is allowed to run. Blocking it would need a rough text scan
  // of an unparseable command, which causes false positives (a quoted `|` in
  // `grep 'a|sed -i' *.x`, a heredoc body), and a false block is worse than a
  // missed glob. The precise path still catches every `Simple` form above.
  for
    cmd in [
      "sed -i 's/a/b/' *.mbt", "cd src && sed -i 's/a/b/' *.mbt", "sed -i 's/a/b/' $(ls)",
    ] {
    guard @command_policy.moonbit_command_policy_error(cmd) is None else {
      fail("expected \{cmd} to be allowed (too-complex parse)")
    }
  }
}

///|
test "command policy allows read-only and non-sed uses of -i" {
  for
    cmd in [
      "sed -n '1,5p' file.mbt", "sed 's/a/b/' file.mbt", "cat file | sed 's/a/b/'",
      "grep -i sed file.mbt", "env -i sed 's/a/b/' file", "echo sed -i", "sed -e 's/i/x/' file",
      // `-f`/`-e` consume the next word as the script/file, so a script file
      // named `-i` is not an in-place flag.
       "sed -f -i file.mbt", "sed -e 's/a/b/' -e p file.mbt",
      // TooComplex parses that are NOT in-place edits must never be blocked:
      // read-only sed, non-sed leaders, a quoted `|sed -i` inside a grep
      // pattern, and a heredoc body that writes `sed -i`.
       "sed 's/a/b/' *.mbt", "echo sed -i *.txt", "grep -i sed *.mbt", "cat *.mbt | sed 's/a/b/'",
      "cd src && grep -i sed *.mbt", "grep 'foo|sed -i' *.mbt", "cat > script.sh <<EOF\nsed -i 's/a/b/' f\nEOF",
    ] {
    guard @command_policy.moonbit_command_policy_error(cmd) is None else {
      fail("expected \{cmd} to be allowed")
    }
  }
}
