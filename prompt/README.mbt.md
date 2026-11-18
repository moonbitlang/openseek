# SeekMoon Prompt

This package owns SeekMoon's built-in system prompt text and prompt-selection
policy. Prompt Markdown files are converted to generated MoonBit string
functions through the module-level `md_to_mbt_string` dev-build rule.

The generator strips Markdown comments outside code blocks. The working
prompt has no resource-layout placeholders: at runtime, the CLI appends the
installation's absolute `Bundled resources` path and a sorted, directory-only
tree of that directory to both built-in and custom base prompts. No `tree`
executable is required, and changes to the installed resources do not require
regenerating the prompt. Files passed through `--system-prompt-file` are read
literally, without template expansion or comment stripping.

`just prompt` refreshes the generated sources; the documentation updater also
invokes the generator. `just check-prompt` checks freshness without writing and
runs in CI before other build commands. Direct `moon` commands run the dev-build
rule when its Markdown input changes.

## Prompt Sources

- `default_prompt.mbt.md`: short always-on working rules and a trigger-based
  guide index. Detailed workflows live in `share/agent-guides/`; presentation,
  artifact, diagram, and slide guidance lives in `share/visualization/`.
  Framework and search guides stay in their own `share/` directories. Only the core and index become system-prompt text;
  linked Markdown guides are not expanded or appended.
- `moonbit_syntax_and_api.mbt.md`: MoonBit syntax and library API teaching,
  manifest examples, and complete programs illustrating the language and APIs.
  Verified examples live under `share/examples/`: a whole-line markdown link
  to a `.mbtx` file is expanded into a fenced block by `md_to_mbt_string`, so
  the prompt shows code that CI type-checks and runs.

Each prompt source has its own dev-build rule and generated MoonBit string
function. The built-in prompt includes the core and index first and, by default,
the language guide second. The language guide can be omitted for a new session while
retaining the core and index. `just prompt`, `just check-prompt`, CI, and the
documentation updater generate or check both outputs.

The agent reads indexed guides before the matching work with the existing
`mbtx` tool and `@builtin/read.mbtx`. The index paths are relative to the
installation's `Bundled resources`, never the workspace. Both CLI and Desktop
packaging copy the `share/` tree, including these guides; no separate loader or
startup read of every guide is involved. Changes to guide contents need no prompt
regeneration unless the core or index also changes. Raw builds without installed
resources retain the core and tool contracts but cannot read the external guides.

When maintaining instructions, put cross-task rules in the core, detailed
procedures in the owning guide, and new task triggers in the index. Keep tool
argument contracts in their tool definitions rather than duplicating them in
the core. Validate that indexed paths survive resource staging; exercise model
routing and task quality with `eval/prompt_task` rather than assertions on prose.

## API Shape

- `Prompt`: `BuiltinMoonBitGuide | Custom(String)` selects the optional content.
- `system_prompt_for_model(model, prompt=BuiltinMoonBitGuide)`: the single
  entry point for assembling a complete base system prompt from the selected
  model, working/tool instructions, and optional content. Supported models
  currently share the same text. `Custom("")` retains the working/tool
  instructions without additional content.

This package owns all static prompt composition and retains its existing
`deepseek.Model` parameter. Desktop and native setup pass the selected typed
model directly. It has no UI, storage,
or process dependencies and supports native, wasm, and JS callers.
The Desktop editor lives in `desktop/frontend/prompt`. Desktop and browser
clients load the committed defaults from the connected host through
`settings.get`, save through `settings.set`, and receive `settings.changed`.
The source selection lives in the host's runtime `engine-settings.json`;
literal custom additional text lives in that host user's
`~/.openseek/system-prompt.md`. Text is saved explicitly, independently from
source selection. Switching to the built-in guide does not delete the text.
There is no prompt preference in localStorage and no cross-host synchronization.

A new draft captures its complete base prompt once its host settings are ready.
Already-captured drafts do not change when a client edits the shared default.
Unsaved editor text stays local to the current host's form and does not change
new-draft defaults; switching hosts discards that unsaved buffer. External file
edits are read on the next settings fetch; no filesystem watcher is installed.
Requests forward the captured string.

Desktop sends the complete base text as `system_prompt`. The host captures it
once in `sessions/<id>/system-prompt.md`, beside the durable transcript, and
forwards it through the existing `--system-prompt-file` option without composing
it again. Resuming a saved conversation does not overwrite this creation input.
Edits and forks inherit it while the engine rebuilds their runtime environment,
project instructions, and skills for the new session. Older sessions without
this file keep the existing default-generation behavior when edited or forked.
The CLI's `--system-prompt-addendum-file` still appends experiment instructions.
Saved sessions continue using their complete stored prompt.
