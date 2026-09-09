# SeekMoon Prompt

This package owns SeekMoon's built-in system prompt text and prompt-selection
policy. Prompt Markdown files are converted to generated MoonBit string
functions through the module-level `md_to_mbt_string` dev-build rule.

The `{{OPENSEEK_REFERENCES_LAYOUT}}` placeholder expands to a sorted,
directory-only tree of the repository's `share/` during generation. The
generated prompt contains the tree as static text; only the installation's
absolute `OPENSEEK_REFERENCES` path is appended at runtime. No `tree` executable
is required. `just prompt` refreshes this filesystem-derived content;
the documentation updater invokes it automatically. `just check-prompt` checks
freshness without writing and runs in CI before other build commands.
Direct `moon` commands also run the dev-build rule when its Markdown input changes,
but do not track directory-only changes under `share/`.

## Prompt Sources

- `default_prompt.mbt.md`: the default built-in prompt used by the supported
  DeepSeek, Kimi, and GLM model names.
- `base_prompt.mbt.md`: the older built-in prompt, retained for comparison and
  prompt experiments but not selected by default.

## API Shape

- `system_prompt_for_model(model)`: return the default built-in prompt for a
  supported chat model. All supported model names use `default_prompt.mbt.md`.

The agent package depends on this package for its default prompt, while the CLI
can still override or append prompt files for A/B experiments.
