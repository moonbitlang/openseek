///|
/// Selects the built-in system prompt for a supported chat model.
///
/// Supported DeepSeek and Kimi model names currently share the default
/// prompt. The older base prompt remains in the package for comparison and
/// prompt experiments, but it is not selected by default.
pub fn system_prompt_for_model(_model : @deepseek.Model) -> String {
  default_prompt()
}

///|
/// The built-in system prompt is currently model-independent: every DeepSeek
/// model receives the default prompt. (The base prompt stays in the package
/// for prompt experiments but is not selected by default.)
///
/// Prompt *wording* is authored in `default_prompt.mbt.md` and its quality is
/// exercised end-to-end by the `eval/prompt_task` suite. Asserting on
/// individual phrases of the generated prompt here only mirrors that document
/// and breaks on every rewording, so this package pins just the selection
/// contract.
test "system_prompt_for_model returns the default prompt for every model" {
  assert_eq(system_prompt_for_model(Deepseek(V4Flash)), default_prompt())
  assert_eq(system_prompt_for_model(Deepseek(V4Pro)), default_prompt())
}
