///|
/// Whether the user supplied `name` on the command line rather than the
/// built-in default filling it in.
pub fn explicitly_provided(matches : @argparse.Matches, name : String) -> Bool {
  matches.sources.get(name) is Some(Argv)
}

///|
/// Resolve the model, thinking mode, and optional endpoint from parsed arguments.
pub fn agent_settings(
  matches : @argparse.Matches,
) -> (@deepseek.Model, @deepseek.ThinkingMode, String?) raise {
  match matches {
    {
      values: {
        "model": [model, ..],
        "thinking": [thinking, ..],
        "api-url": [api_url, ..],
        ..
      },
      ..
    } =>
      (
        @deepseek.Model::parse(model),
        @deepseek.ThinkingMode::parse(thinking),
        match api_url.trim() {
          "" => None
          url => Some("\{url}")
        },
      )
    _ => fail("missing parsed agent defaults")
  }
}

///|
/// `None` — no flag, no env — means turns bounded by the model's context
/// window (the engine's own default), not by a step count.
pub fn max_steps(matches : @argparse.Matches) -> Int? raise {
  optional_positive_int(matches, "max-steps")
}

///|
/// A positive-integer option, or `None` when no value was supplied for `name`.
/// The rejection message names the flag (`--<name>`), exactly as the
/// hand-written copies did.
fn optional_positive_int(
  matches : @argparse.Matches,
  name : String,
) -> Int? raise {
  match matches.values.get(name) {
    Some([input, ..]) => Some(@cli.parse_positive_int(input, "--\{name}"))
    _ => None
  }
}

///|
/// Model-request retry overrides. `None` for either half means the DeepSeek
/// client keeps its own default, so the defaults live in exactly one place
/// (`@client.Client`) and are never restated here.
///
/// The pair is forwarded as `retry_attempts?, retry_backoff_ms?` down to every
/// in-process `@client.Client`; `export_retry_overrides` carries it to child
/// processes.
pub fn retry_overrides(matches : @argparse.Matches) -> (Int?, Int?) raise {
  let attempts = optional_positive_int(matches, "retry-attempts")
  let backoff_ms = optional_positive_int(matches, "retry-backoff-ms")
  (attempts, backoff_ms)
}

///|
/// Write the resolved retry overrides back into this process's environment, so
/// that a child sees exactly what this process resolved.
///
/// `--retry-attempts 2` and `OPENSEEK_RETRY_ATTEMPTS=2` must mean the same
/// thing to a subagent, and before this a child got only the second: nothing
/// injects these on the child command line, and separate spawn sites
/// would each have to — the review gate and
/// the workflow scout and worker runners, the last two reachable only through
/// the `SubrunInjection` handoff an `mbtx` snippet receives. Children do
/// inherit the environment (`@process.spawn(inherit_env=true)`), so writing
/// the flag back covers them all at once. It is also the shape `--api-key`
/// already has: argv carries what a child cannot otherwise know, and the
/// environment carries the rest.
///
/// A value that arrived from the environment is rewritten unchanged.
pub fn export_retry_overrides(matches : @argparse.Matches) -> Unit raise {
  let (attempts, backoff_ms) = retry_overrides(matches)
  if attempts is Some(attempts) {
    @env.set_env_var("OPENSEEK_RETRY_ATTEMPTS", "\{attempts}")
  }
  if backoff_ms is Some(backoff_ms) {
    @env.set_env_var("OPENSEEK_RETRY_BACKOFF_MS", "\{backoff_ms}")
  }
}

///|
/// Join task arguments and reject an empty task.
pub fn task_text(matches : @argparse.Matches) -> String raise {
  let task = match matches {
    { values: { "task": words, .. }, .. } => words.join(" ").trim()
    _ => ""
  }
  if task.is_empty() {
    fail("task description is required for agent runs")
  }
  "\{task}"
}

///|
/// The dedicated `--deepseek-api-key`/`$DEEPSEEK` credential, trimmed, or
/// `None` when blank: what `web_search` uses on a non-DeepSeek model run.
pub fn deepseek_api_key(matches : @argparse.Matches) -> String? {
  match matches {
    { values: { "deepseek-api-key": [key, ..], .. }, .. } if !key.is_blank() =>
      Some(key.trim().to_owned())
    _ => None
  }
}

///|
/// The `--mcp-config` path, or `None` when unset.
pub fn mcp_config_path(matches : @argparse.Matches) -> String? {
  match matches {
    { values: { "mcp-config": [path, ..], .. }, .. } if !path.is_empty() =>
      Some(path)
    _ => None
  }
}
