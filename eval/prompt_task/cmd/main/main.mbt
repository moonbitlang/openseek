///|
async fn main {
  let matches = @argparse.parse(cli_command())
  if flag(matches, "analyze-only") {
    let out_dir = value(matches, "out")
    if @harness.suite_manifest_exists(out_dir) {
      let report = @harness.analyze_suite(out_dir)
      println(report.markdown())
      if !report.passed() {
        fail(report.failure_message())
      }
    } else {
      let report = @harness.analyze_run(out_dir)
      println(report.markdown())
      if !report.passed() {
        fail(report.failure_message())
      }
    }
    return
  }
  if value(matches, "suite-file") != "" {
    let config = suite_config_from_matches(matches)
    let manifest = @harness.run_suite(config)
    println(
      "prompt task suite manifest: \{@harness.suite_manifest_path(manifest.out_dir)}",
    )
    return
  }
  let config = config_from_matches(matches)
  let manifest = @harness.run_experiments(config)
  println(
    "prompt task run manifest: \{@harness.manifest_path(manifest.out_dir)}",
  )
}

///|
fn cli_command() -> @argparse.Command {
  Command(
    "prompt-task-eval",
    about="Run repeated prompt-task evals against the OpenSeek agent.",
    options=[
      OptionArg(
        "api-key",
        long="api-key",
        default_values=[""],
        about="API key for the selected chat provider.",
      ),
      OptionArg(
        "model",
        long="model",
        default_values=[@deepseek.Deepseek(V4Flash).to_string()],
        about="Chat model: deepseek-v4-flash, deepseek-v4-pro, kimi-k2.7-code, or kimi-k2.7-code-highspeed.",
      ),
      OptionArg(
        "runs",
        long="runs",
        default_values=["5"],
        about="Number of independent trials.",
      ),
      OptionArg(
        "concurrency",
        long="concurrency",
        default_values=["5"],
        about="Maximum number of trials to run concurrently.",
      ),
      OptionArg(
        "min-successes",
        long="min-successes",
        default_values=["5"],
        about="Minimum successful trials required.",
      ),
      OptionArg(
        "max-steps",
        long="max-steps",
        default_values=["160"],
        about="Maximum agent steps per trial.",
      ),
      OptionArg(
        "task-file",
        long="task-file",
        default_values=["eval/prompt_tasks/toml_parser_cli.md"],
        about="Task template file. `{{WORKSPACE}}` is replaced per trial.",
      ),
      OptionArg(
        "suite-file",
        long="suite-file",
        default_values=[""],
        about="JSON suite config containing models, problems, probes, and run shape.",
      ),
      OptionArg(
        "out",
        long="out",
        default_values=[".moonagent/eval_runs/prompt_task_flash"],
        about="Directory for workspaces, logs, and reports.",
      ),
      OptionArg(
        "repo-root",
        long="repo-root",
        default_values=["."],
        about="OpenSeek repository root used to run cmd/main.",
      ),
      OptionArg(
        "engine",
        long="engine",
        default_values=[""],
        about="Prebuilt openseek binary to exec per trial; empty falls back to `moon run <repo-root>/cmd/openseek` (which breaks when the repo defines dev_build rules, since their paths resolve against the trial cwd).",
      ),
      OptionArg(
        "prompt-label",
        long="prompt-label",
        default_values=["builtin"],
        about="Human-readable label for the prompt variant under evaluation.",
      ),
      OptionArg(
        "system-prompt-file",
        long="system-prompt-file",
        default_values=[""],
        about="Pass a replacement system prompt file through to OpenSeek.",
      ),
      OptionArg(
        "system-prompt-addendum-file",
        long="system-prompt-addendum-file",
        default_values=[""],
        about="Pass a system prompt addendum file through to OpenSeek.",
      ),
    ],
    flags=[
      FlagArg(
        "analyze-only",
        long="analyze-only",
        about="Analyze an existing --out directory without running agent trials.",
      ),
    ],
  )
}

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
    "--system-prompt-file", "prompt/default_prompt.mbt.md",
  ])
  let config = config_from_matches(matches)
  assert_eq(config.runs, 3)
  assert_eq(config.concurrency, 2)
  assert_eq(config.min_successes, 2)
  assert_eq(config.prompt_label, "flash-v2")
  assert_eq(config.system_prompt_file, "prompt/default_prompt.mbt.md")
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
test "empty api key parses through for environment fallback" {
  // An empty --api-key is no longer rejected here: the harness falls back to
  // the provider's environment variable so one suite can span providers. The
  // key-presence check moved to run time (require_api_access), which names the
  // exact missing variable.
  let matches = cli_command().parse(argv=[])
  let config = config_from_matches(matches)
  assert_eq(config.api_key, "")
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
