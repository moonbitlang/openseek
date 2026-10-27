///|
/// The source of the optional instructions added to the working prompt.
pub(all) enum Prompt {
  BuiltinMoonBitGuide
  Custom(String)
} derive(Eq)

///|
#doc(hidden)
#deprecated
pub extend Prompt with Eq::{equal, not_equal}

///|
/// Assemble the complete base system prompt for the selected model.
/// Supported models currently share the same working and tool instructions.
/// Empty custom text retains those instructions without optional content.
pub fn system_prompt_for_model(
  _model : @deepseek.Model,
  prompt~ : Prompt = BuiltinMoonBitGuide,
) -> String {
  let additional = match prompt {
    BuiltinMoonBitGuide => moonbit_syntax_and_api()
    Custom(text) => text
  }
  if additional.is_empty() {
    default_prompt()
  } else {
    default_prompt() + "\n\n" + additional
  }
}

///|
/// Prompt *wording* is authored in the two Markdown sources and its quality is
/// exercised end-to-end by the `eval/prompt_task` suite. Asserting on
/// individual phrases of the generated prompt here only mirrors those documents
/// and breaks on every rewording, so this package pins just the selection
/// contract.
test "model-selected prompts include working instructions and language guide" {
  let expected = default_prompt() + "\n\n" + moonbit_syntax_and_api()
  assert_eq(system_prompt_for_model(Deepseek(V4Flash)), expected)
  assert_eq(system_prompt_for_model(Deepseek(V4Pro)), expected)
}

///|
test "custom prompts preserve working instructions and literal text" {
  for text in ["", "  Project instructions\n中文与 `code`\n"] {
    let expected = if text.is_empty() {
      default_prompt()
    } else {
      default_prompt() + "\n\n" + text
    }
    assert_eq(
      system_prompt_for_model(Deepseek(V4Pro), prompt=Custom(text)),
      expected,
    )
  }
}
