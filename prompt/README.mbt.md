# SeekMoon Prompt

This package owns SeekMoon's built-in system prompt text and prompt-selection
policy. Prompt Markdown files are converted to generated MoonBit string
functions through the module-level `md_to_mbt_string` dev-build rule.

The `{{BUNDLED_RESOURCES_LAYOUT}}` placeholder expands to a sorted,
directory-only tree of the repository's `share/` during generation. The
generated prompt contains the tree as static text; only the installation's
absolute `Bundled resources` path is appended at runtime. No `tree` executable
is required. `just prompt` refreshes this filesystem-derived content;
the documentation updater invokes it automatically. `just check-prompt` checks
freshness without writing and runs in CI before other build commands.
Direct `moon` commands also run the dev-build rule when its Markdown input changes,
but do not track directory-only changes under `share/`.

## Prompt Sources

- `default_prompt.mbt.md`: agent working instructions, tool contracts,
  development workflows, validation, and reference-document navigation.
- `moonbit_syntax_and_api.mbt.md`: MoonBit syntax and library API teaching,
  manifest examples, and complete programs illustrating the language and APIs.
  Verified examples live under `share/examples/`: a whole-line markdown link
  to a `.mbtx` file is expanded into a fenced block by `md_to_mbt_string`, so
  the prompt shows code that CI type-checks and runs.

Each source has its own dev-build rule and generated MoonBit string function.
The built-in prompt includes the working instructions first and, by default,
the language guide second. The guide can be omitted for a new session while
retaining the working instructions and tools. `just prompt`, `just check-prompt`, CI, and the
documentation updater generate or check both outputs.

## API Shape

- `system_prompt_for_model(model, moonbit_guide=true)`: return the built-in prompt
  for a supported chat model. Set `moonbit_guide=false` to omit the language guide.

The agent package depends on this package for its default prompt, while the CLI
can still override or append prompt files for A/B experiments.
