# SeekMoon Prompt

This package owns SeekMoon's built-in system prompt text and prompt-selection
policy. Prompt Markdown files are converted to generated MoonBit string
functions through the module-level `md_to_mbt_string` dev-build rule.

The prompt generator strips Markdown comments outside code blocks. When
resources are installed, the CLI appends their absolute `Bundled resources`
path and a sorted, directory-only tree to both built-in and custom base prompts. No `tree`
executable is required, and changes to the installed resources do not require
regenerating the prompt. Files passed through `--system-prompt-file` are read
literally, without template expansion or comment stripping.

`just prompt` refreshes the generated sources; the documentation updater also
invokes the generator. `just check-prompt` checks freshness without writing and
runs in CI before other build commands. Direct `moon` commands run the dev-build
rule when its Markdown input changes.

## Prompt Sources

- `default_prompt.mbt.md`: short always-on working rules and guide lookup
  instructions. Guide bodies under `prompt/guides/` are not expanded into this
  prompt or read at session startup.
- `moonbit_syntax_and_api.mbt.md`: MoonBit syntax and library API teaching,
  manifest examples, and complete programs illustrating the language and APIs.
  Prompt-only examples live under [`prompt/examples/`](examples/). The
  `md_to_mbt_string` generator inlines whole-line links to `.mbtx` files as
  code blocks, so the examples do not need to ship in `share/`. CI type-checks
  these scripts and runs the deterministic examples.

Each prompt source has its own dev-build rule and generated MoonBit string
function. The built-in prompt includes the core first and, by default,
the language guide second. The language guide can be omitted for a new session while
retaining the core. `just prompt`, `just check-prompt`, CI, and the
documentation updater generate or check both outputs.

## On-demand guides

A guide ID is the file's path relative to `prompt/guides/` without `.md`.
Write references as `guide:<id>` in prose and tables. For example,
`guide:diagrams/katex` is read with `args=["diagrams/katex"]` in
`@builtin/agent-guide.mbtx`; the prefix is not part of the ID.
Register the file in the `agent_guide` inputs in `agent_tool/mbtx/moon.pkg`.
Write its description in the first paragraph, then a blank line and the Markdown
body. A heading is optional.

`moon check --target wasm agent_tool/mbtx prompt` runs the build rules:
`scripts/agent_guide.mbtx` generates a self-contained `agent-guide.mbtx` and
`mbtx_bundle` embeds it alongside the other workflows. Commit the generated
`.mbt` files, not the intermediate `.mbtx`. The engine runs the
script through ordinary `mbtx` with `ptc=false`. With no arguments it returns
`{version: 1, guides: [{id, description}, ...]}`; with one ID it returns the
Markdown body. Neither response reads workspace or installed resources. References to official docs, templates and executable
assets still require the corresponding installed resources.

When maintaining instructions, put cross-task rules in the core, detailed
procedures in the owning guide, and describe its scope in its first paragraph. Keep tool
argument contracts in their tool definitions rather than duplicating them in
the core. Verify guide queries against the Markdown sources; exercise model
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
