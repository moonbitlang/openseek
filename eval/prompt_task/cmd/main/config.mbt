///|
fn config_from_matches(matches : @argparse.Matches) -> @harness.Config raise {
  let runs = parse_positive_int(value(matches, "runs"), "--runs")
  let min_successes = parse_positive_int(
    value(matches, "min-successes"),
    "--min-successes",
  )
  guard min_successes <= runs else { fail("--min-successes must be <= --runs") }
  let api_key = value(matches, "api-key")
  guard api_key != "" else { fail("--api-key is required for running trials") }
  Config(
    api_key~,
    model=@deepseek.Model::parse(value(matches, "model")),
    problem_id="toml_parser_cli",
    runs~,
    concurrency=parse_positive_int(
      value(matches, "concurrency"),
      "--concurrency",
    ),
    min_successes~,
    max_steps=parse_positive_int(value(matches, "max-steps"), "--max-steps"),
    out_dir=value(matches, "out"),
    repo_root=value(matches, "repo-root"),
    engine=value(matches, "engine"),
    prompt_label=value(matches, "prompt-label"),
    task_file=value(matches, "task-file"),
    validation_probes=@harness.default_toml_validation_probes(),
    system_prompt_file=value(matches, "system-prompt-file"),
    system_prompt_addendum_file=value(matches, "system-prompt-addendum-file"),
  )
}

///|
async fn suite_config_from_matches(
  matches : @argparse.Matches,
) -> @harness.SuiteConfig {
  let api_key = value(matches, "api-key")
  guard api_key != "" else { fail("--api-key is required for running trials") }
  @harness.suite_config_from_file(
    value(matches, "suite-file"),
    api_key~,
    out_dir=value(matches, "out"),
    repo_root=value(matches, "repo-root"),
    engine=value(matches, "engine"),
    system_prompt_file=value(matches, "system-prompt-file"),
    system_prompt_addendum_file=value(matches, "system-prompt-addendum-file"),
  )
}

///|
fn flag(matches : @argparse.Matches, name : String) -> Bool {
  match matches.flags.get(name) {
    Some(value) => value
    None => false
  }
}

///|
fn value(matches : @argparse.Matches, name : String) -> String raise {
  match matches.values.get(name) {
    Some([value]) => value
    Some(values) if values.length() > 0 => values[0]
    _ => fail("missing parsed argument: \{name}")
  }
}

///|
fn parse_positive_int(input : String, label : String) -> Int raise {
  let parsed = @string.parse_int(input) catch {
    _ => fail("\{label} must be a positive integer, got: \{input}")
  }
  guard parsed > 0 else {
    fail("\{label} must be a positive integer, got: \{input}")
  }
  parsed
}
