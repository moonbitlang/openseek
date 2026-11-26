///|
fn config_from_matches(matches : @argparse.Matches) -> @harness.Config raise {
  let runs = @cli.parse_positive_int(@cli.value(matches, "runs"), "--runs")
  let min_successes = @cli.parse_positive_int(
    @cli.value(matches, "min-successes"),
    "--min-successes",
  )
  guard min_successes <= runs else { fail("--min-successes must be <= --runs") }
  Config(
    api_key=@cli.value(matches, "api-key"),
    model=@deepseek.Model::parse(
      @cli.value(matches, "model"),
      context_window?=@options.context_window(),
    ),
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
    prompt_label=@cli.value(matches, "prompt-label"),
    system_prompt_file=@cli.value(matches, "system-prompt-file"),
    system_prompt_addendum_file=@cli.value(
      matches, "system-prompt-addendum-file",
    ),
  )
}
