///|
let provider_api_key_options : Map[String, String] = {
  "DEEPSEEK": "deepseek-api-key",
  "KIMI": "kimi-api-key",
  "GLM": "glm-api-key",
}

///|
/// Resolve a nonblank chat key from the parsed options. An explicit
/// `--api-key` wins, followed by the selected provider's option or environment
/// variable, then `OPENSEEK_API_KEY`.
pub fn resolve_api_key(
  model : @deepseek.Model,
  matches : @argparse.Matches,
) -> String? {
  let generic_key = match matches.values.get("api-key") {
    Some([key, ..]) if !key.is_blank() => Some(key.trim().to_owned())
    _ => None
  }
  if matches.sources.get("api-key") is Some(Argv) && generic_key is Some(_) {
    return generic_key
  }
  if provider_api_key_options.get(model.api_key_env()) is Some(option) &&
    matches.values.get(option) is Some([key, ..]) &&
    !key.is_blank() {
    Some(key.trim().to_owned())
  } else {
    generic_key
  }
}

///|
/// Options shared by the agent-running mains (the root CLI here and the
/// `openseek_tui` binary in `moonbitlang/openseek_tui`): `--api-key`,
/// `--model`, `--api-url`, `--retry-attempts`, `--retry-backoff-ms`,
/// `--max-steps`, `--thinking`, `--session`, `--session-root`, plus the
/// provider-specific key options.
///
/// The root CLI installs these on its root command with `global=true`, so
/// they read the same value in any position — `openseek --api-key k run`,
/// `openseek run --api-key k` — and the engine subcommands inherit them rather
/// than redeclaring (redeclaring a global is a build error). `openseek_tui`
/// declares them non-global on its single command. `--api-key` is not
/// argparse-`required`: argparse enforces a parent's required options for
/// *every* subcommand, which would wrongly block key-free subcommands like
/// `sessions list`; presence is enforced where a key is actually needed.
/// `global` is a parameter so the TUI main can build a standalone (non-global)
/// command.
pub fn agent_shared_options(
  global~ : Bool = false,
) -> Array[@argparse.OptionArg] {
  [
    OptionArg(
      "api-key",
      long="api-key",
      env=@deepseek.CustomApiKeyEnv,
      default_values=[""],
      global~,
      about="API key for the selected chat provider.",
    ),
    ..[
      for env, name in provider_api_key_options => {
        @argparse.OptionArg(
          name,
          long=name,
          env~,
          default_values=[""],
          global~,
          hidden=true,
        )
      }
    ],
    OptionArg(
      "model",
      long="model",
      env="OPENSEEK_MODEL",
      default_values=[@deepseek.Deepseek(V4Flash).to_string()],
      global~,
      about="Chat model: deepseek-flash, deepseek-v4-pro, kimi-k2.7-code, kimi-k2.7-code-highspeed, glm-5.3, glm-5.3-flash, or any model id configured in Settings.",
    ),
    OptionArg(
      "api-url",
      long="api-url",
      env="OPENSEEK_API_URL",
      default_values=[""],
      global~,
      about="OpenAI-compatible chat completions endpoint.",
    ),
    OptionArg(
      "retry-attempts",
      long="retry-attempts",
      env="OPENSEEK_RETRY_ATTEMPTS",
      global~,
      about="Total tries per model request before giving up on a retryable failure (429, 5xx, or a transport error); 1 disables retrying. Omit for the client default.",
    ),
    OptionArg(
      "retry-backoff-ms",
      long="retry-backoff-ms",
      env="OPENSEEK_RETRY_BACKOFF_MS",
      global~,
      about="Delay before the first model-request retry; it doubles per attempt, capped at 60s. Omit for the client default.",
    ),
    OptionArg(
      "max-steps",
      long="max-steps",
      env="OPENSEEK_MAX_STEPS",
      global~,
      about="Maximum agent steps per turn; omit to bound turns by the model's context window instead (a checkpoint summary carries each turn into the next).",
    ),
    OptionArg(
      "thinking",
      long="thinking",
      env="OPENSEEK_THINKING",
      default_values=["high"],
      global~,
      about="Model thinking mode: no, high, or max; GLM maps no to low effort.",
    ),
    OptionArg(
      "session",
      long="session",
      global~,
      about="Create or resume this durable session id.",
    ),
    OptionArg(
      "session-root",
      long="session-root",
      default_values=[".openseek"],
      global~,
      about="Directory containing durable OpenSeek sessions.",
    ),
  ]
}
