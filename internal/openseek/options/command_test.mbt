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

///|
test "MCP configs append in order and explicit arguments replace the env fallback" {
  for subcommand in ["run", "serve", "mcp"] {
    let env = { "OPENSEEK_MCP_CONFIG": "fallback.json" }
    let cases : Array[(Array[String], Array[String])] = [
      ([], ["fallback.json"]),
      (["--mcp-config", "a.json", "--mcp-config=b.json"], ["a.json", "b.json"]),
      (["--mcp-config="], []),
      (["--mcp-config=", "--mcp-config=b.json"], ["b.json"]),
      (["--mcp-config=a.json", "--mcp-config="], ["a.json"]),
    ]
    for (args, expected) in cases {
      guard @options.root_command().parse(argv=[subcommand, ..args], env~).subcommand
        is Some((_, matches)) else {
        fail("expected subcommand")
      }
      assert_eq(@options.mcp_config_paths(matches), expected)
    }
  }
}

///|
test "setup requires no model credentials and has no installation options" {
  let parsed = @options.root_command().parse(argv=["setup"], env=Map([]))
  assert_true(parsed.subcommand is Some(("setup", _)))
  for option in ["--json", "--bundle-url"] {
    let error = try {
      @options.root_command().parse(argv=["setup", option], env=Map([]))
      |> ignore
      "accepted"
    } catch {
      error => "\{error}"
    }
    assert_true(error.contains("unexpected argument"))
  }
}
