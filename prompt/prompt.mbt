///|
/// Selects the built-in system prompt for a supported chat model.
///
/// Supported DeepSeek, Kimi, and GLM model names currently share the one
/// built-in prompt: the working instructions in `default_prompt.mbt.md`,
/// followed by the teaching material in `moonbit_syntax_and_api.mbt.md`.
pub fn system_prompt_for_model(_model : @deepseek.Model) -> String {
  default_prompt() + "\n\n" + moonbit_syntax_and_api()
}

///|
/// The built-in system prompt is currently model-independent: every DeepSeek
/// model receives the default prompt.
///
/// Prompt *wording* is authored in the two Markdown sources and its quality is
/// exercised end-to-end by the `eval/prompt_task` suite. Asserting on
/// individual phrases of the generated prompt here only mirrors those documents
/// and breaks on every rewording, so this package pins just the selection
/// contract.
test "system_prompt_for_model includes working instructions and language guide for every model" {
  let expected = default_prompt() + "\n\n" + moonbit_syntax_and_api()
  assert_eq(system_prompt_for_model(Deepseek(V4Flash)), expected)
  assert_eq(system_prompt_for_model(Deepseek(V4Pro)), expected)
}
