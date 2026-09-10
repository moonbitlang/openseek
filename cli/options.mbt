///|
/// Options shared by the agent-running mains (`cmd/openseek` here and the
/// `openseek_tui` binary in `moonbitlang/openseek_tui`): `--api-key`,
/// `--model`, `--api-url`, `--retry-attempts`, `--retry-backoff-ms`,
/// `--max-steps`, `--thinking`, `--session`, `--session-root`, plus the
/// provider-specific key options.
///
/// `cmd/openseek` installs these on its root command with `global=true`, so
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
  global? : Bool = false,
) -> Array[@argparse.OptionArg] {
  [
    OptionArg(
      "api-key",
      long="api-key",
      default_values=[""],
      global~,
      about="API key for the selected chat provider.",
    ),
    OptionArg(
      "deepseek-api-key",
      long="deepseek-api-key",
      env="DEEPSEEK",
      default_values=[""],
      global~,
      hidden=true,
    ),
    OptionArg(
      "kimi-api-key",
      long="kimi-api-key",
      env="KIMI",
      default_values=[""],
      global~,
      hidden=true,
    ),
    OptionArg(
      "glm-api-key",
      long="glm-api-key",
      env="GLM",
      default_values=[""],
      global~,
      hidden=true,
    ),
    OptionArg(
      "model",
      long="model",
      env="OPENSEEK_MODEL",
      default_values=[@deepseek.Deepseek(V4Flash).to_string()],
      global~,
      about="Chat model: deepseek-flash, deepseek-v4-flash, deepseek-v4-pro, kimi-k2.7-code, kimi-k2.7-code-highspeed, glm-5.3, or glm-5.3-flash.",
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
