///|
async fn main {
  let config = @argparse.parse(cli_command()) |> config_from_matches
  let report = @harness.run_suite(config)
  println(report.markdown())
  if !report.passed() {
    fail(report.failure_message())
  }
}

///|
fn cli_command() -> @argparse.Command {
  Command(
    "file-edit-eval",
    about="Run statistical file-editing evals against the OpenSeek agent.",
    options=[
      OptionArg(
        "api-key",
        long="api-key",
        required=true,
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
        default_values=["10"],
        about="Number of trials. Cases repeat in order.",
      ),
      OptionArg(
        "concurrency",
        long="concurrency",
        default_values=["1"],
        about="Maximum number of trials to run concurrently.",
      ),
      OptionArg(
        "min-successes",
        long="min-successes",
        default_values=["8"],
        about="Minimum successful trials required.",
      ),
      OptionArg(
        "max-steps",
        long="max-steps",
        default_values=["200"],
        about="Maximum agent steps per trial.",
      ),
      OptionArg(
        "out",
        long="out",
        default_values=[".moonagent/eval_runs/file_edit_flash"],
        about="Directory for workspaces, logs, and reports.",
      ),
      OptionArg(
        "repo-root",
        long="repo-root",
        default_values=["."],
        about="OpenSeek repository root used to run the cmd/openseek engine.",
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
  )
}

///|
test "cli defaults to flash baseline" {
  let matches = cli_command().parse(argv=["--api-key", "test-key"])
  let config = config_from_matches(matches)
  assert_eq(config.api_key, "test-key")
  assert_eq(config.model.to_string(), "deepseek-v4-flash")
  assert_eq(config.runs, 10)
  assert_eq(config.concurrency, 1)
  assert_eq(config.min_successes, 8)
  assert_eq(config.max_steps, 200)
  assert_eq(config.prompt_label, "builtin")
  assert_eq(config.system_prompt_file, "")
  assert_eq(config.system_prompt_addendum_file, "")
}

///|
test "cli parses concurrency option" {
  let matches = cli_command().parse(argv=[
    "--api-key", "test-key", "--runs", "5", "--min-successes", "5", "--concurrency",
    "5",
  ])
  let config = config_from_matches(matches)
  assert_eq(config.runs, 5)
  assert_eq(config.concurrency, 5)
}

///|
test "cli parses prompt experiment options" {
  let matches = cli_command().parse(argv=[
    "--api-key", "test-key", "--prompt-label", "run-e-addendum", "--system-prompt-file",
    "prompts/base.md", "--system-prompt-addendum-file", "prompts/run-e.md",
  ])
  let config = config_from_matches(matches)
  assert_eq(config.prompt_label, "run-e-addendum")
  assert_eq(config.system_prompt_file, "prompts/base.md")
  assert_eq(config.system_prompt_addendum_file, "prompts/run-e.md")
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
