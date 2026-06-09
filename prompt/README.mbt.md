# OpenSeek Prompt

This package owns OpenSeek's built-in system prompt text and prompt-selection
policy. Prompt Markdown files are converted to generated MoonBit string
functions through the module-level `md_to_mbt_string` dev-build rule.

## Prompt Sources

- `base_prompt.mbt.md`: the default built-in prompt used by DeepSeek V4 Pro.
- `flash_prompt.mbt.md`: the built-in prompt tuned for DeepSeek V4 Flash.

## API Shape

- `system_prompt_for_model(model)`: select the built-in prompt for a DeepSeek
  model.

The agent package depends on this package for its default prompt, while the CLI
can still override or append prompt files for A/B experiments.
