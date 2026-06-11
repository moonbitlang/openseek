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
        about="DeepSeek API key.",
      ),
      OptionArg(
        "model",
        long="model",
        default_values=[@deepseek.V4Flash.to_string()],
        about="DeepSeek model: deepseek-v4-flash or deepseek-v4-pro.",
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
