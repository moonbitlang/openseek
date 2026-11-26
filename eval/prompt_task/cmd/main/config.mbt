///|
fn config_from_matches(matches : @argparse.Matches) -> @harness.Config raise {
  let runs = @cli.parse_positive_int(@cli.value(matches, "runs"), "--runs")
  let min_successes = @cli.parse_positive_int(
    @cli.value(matches, "min-successes"),
    "--min-successes",
  )
  guard min_successes <= runs else { fail("--min-successes must be <= --runs") }
  // An empty --api-key is allowed: the harness falls back to the provider's
  // environment variable (DEEPSEEK/KIMI/GLM), which is the only way a
  // cross-provider run authenticates each model with its own key.
  let api_key = @cli.value(matches, "api-key")
  Config(
    api_key~,
    model=@deepseek.Model::parse(
      @cli.value(matches, "model"),
      context_window?=@options.context_window(),
    ),
    problem_id="toml_parser_cli",
    runs~,
    concurrency=@cli.parse_positive_int(
      @cli.value(matches, "concurrency"),
      "--concurrency",
    ),
    min_successes~,
    max_steps=@cli.parse_positive_int(
      @cli.value(matches, "max-steps"),
      "--max-steps",
    ),
    out_dir=@cli.value(matches, "out"),
    repo_root=@cli.value(matches, "repo-root"),
    engine=@cli.value(matches, "engine"),
    prompt_label=@cli.value(matches, "prompt-label"),
    task_file=@cli.value(matches, "task-file"),
    validation_probes=@harness.default_toml_validation_probes(),
    system_prompt_file=@cli.value(matches, "system-prompt-file"),
    system_prompt_addendum_file=@cli.value(
      matches, "system-prompt-addendum-file",
    ),
  )
}

///|
async fn suite_config_from_matches(
  matches : @argparse.Matches,
) -> @harness.SuiteConfig {
  // Empty --api-key means "inherit each model's provider key from the
  // environment"; run_suite validates every listed provider up front.
  let api_key = @cli.value(matches, "api-key")
  @harness.suite_config_from_file(
    @cli.value(matches, "suite-file"),
    api_key~,
    out_dir=@cli.value(matches, "out"),
    repo_root=@cli.value(matches, "repo-root"),
    engine=@cli.value(matches, "engine"),
    system_prompt_file=@cli.value(matches, "system-prompt-file"),
    system_prompt_addendum_file=@cli.value(
      matches, "system-prompt-addendum-file",
    ),
  )
}

///|
fn flag(matches : @argparse.Matches, name : String) -> Bool {
  matches.flags.get(name).unwrap_or(false)
}
