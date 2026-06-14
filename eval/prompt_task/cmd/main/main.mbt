///|
async fn main {
  let matches = @argparse.parse(cli_command())
  if flag(matches, "analyze-only") {
    let report = @harness.analyze_run(value(matches, "out"))
    println(report.markdown())
    if !report.passed() {
      fail(report.failure_message())
    }
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
