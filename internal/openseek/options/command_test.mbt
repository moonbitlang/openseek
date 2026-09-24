///|
test "root command rejects an unknown subcommand" {
  // argparse owns this now (no hand-rolled dispatch): a bare non-subcommand word
  // is refused rather than silently opening the UI as a free-form prompt.
  let outcome = try {
    @options.root_command().parse(argv=["serv"], env=Map([])) |> ignore
    "parsed"
  } catch {
    e => "\{e}"
  }
  assert_false(outcome == "parsed")
  assert_true(outcome.contains("serv"))
}

///|
test "bare parse is rejected (no default subcommand)" {
  let outcome = try {
    @options.root_command().parse(argv=[], env={ "DEEPSEEK": "k" }) |> ignore
    "parsed"
  } catch {
    e => "\{e}"
  }
  // Pin the reason, so an unrelated parse failure (say, a root option ever
  // becoming `required`) cannot make this pass vacuously.
  assert_true(
    outcome.contains("required argument") && outcome.contains("'subcommand'"),
    msg="expected the missing-subcommand error, got: \{outcome}",
  )
}

///|
test "cli rejects unknown options before task text" {
  let _ = @testkit.run_matches(argv=["--xxy", "he"], env=Map([])) catch {
    error => {
      assert_true("\{error}".contains("unexpected argument '--xxy' found"))
      return
    }
  }
  fail("unknown option accepted as task text")
}

///|
test "cli accepts hyphen-leading task text after option delimiter" {
  let parsed = @testkit.run_matches(argv=["--", "--xxy", "he"], env=Map([]))
  assert_eq(@options.task_text(parsed), "--xxy he")
}

///|
test "sessions list needs no api key or task" {
  // The `sessions` subcommands do not declare api-key/task at all, so listing
  // works with no DeepSeek setup.
  let parsed = @testkit.sessions_leaf_matches(sub="list", argv=[], env=Map([]))
  assert_eq(@cli.value(parsed, "format"), "text")
  assert_eq(@cli.value(parsed, "session-root"), ".openseek")
}
