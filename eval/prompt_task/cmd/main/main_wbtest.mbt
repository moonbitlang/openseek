///|
test "cli defaults to five concurrent flash toml runs" {
  let matches = cli_command().parse(argv=["--api-key", "test-key"])
  let config = config_from_matches(matches)
  assert_eq(config.api_key, "test-key")
  assert_eq(config.model.to_string(), "deepseek-v4-flash")
  assert_eq(config.runs, 5)
  assert_eq(config.concurrency, 5)
  assert_eq(config.min_successes, 5)
  assert_eq(config.max_steps, 160)
  assert_eq(config.task_file, "eval/prompt_tasks/toml_parser_cli.md")
}

///|
test "cli parses prompt and task options" {
  let matches = cli_command().parse(argv=[
    "--api-key", "test-key", "--runs", "3", "--concurrency", "2", "--min-successes",
    "2", "--prompt-label", "flash-v2", "--task-file", "eval/prompt_tasks/toml_parser_cli.md",
    "--system-prompt-file", "prompt/flash_prompt.md",
  ])
  let config = config_from_matches(matches)
  assert_eq(config.runs, 3)
  assert_eq(config.concurrency, 2)
  assert_eq(config.min_successes, 2)
  assert_eq(config.prompt_label, "flash-v2")
  assert_eq(config.system_prompt_file, "prompt/flash_prompt.md")
}

///|
test "analyze-only mode does not require an api key" {
  let matches = cli_command().parse(argv=["--analyze-only", "--out", "existing"])
  assert_true(flag(matches, "analyze-only"))
  assert_eq(value(matches, "out"), "existing")
}

///|
test "cli parses suite file option" {
  let matches = cli_command().parse(argv=[
    "--api-key", "test-key", "--suite-file", "suite.json", "--out", "runs",
  ])
  assert_eq(value(matches, "suite-file"), "suite.json")
  assert_eq(value(matches, "out"), "runs")
}

///|
test "running trials requires an api key" {
  let matches = cli_command().parse(argv=[])
  let _ = config_from_matches(matches) catch {
    error => {
      assert_true("\{error}".contains("--api-key is required"))
      return
    }
  }
  fail("missing api key parsed")
}

///|
test "cli rejects impossible threshold" {
  let matches = cli_command().parse(argv=[
    "--api-key", "test-key", "--runs", "3", "--min-successes", "4",
  ])
  let _ = config_from_matches(matches) catch {
    error => {
      assert_true("\{error}".contains("--min-successes must be <= --runs"))
      return
    }
  }
  fail("impossible threshold parsed")
}
