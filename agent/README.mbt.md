# OpenSeek Agent

This package contains the native-only agent loop for `bobzhang/openseek`. It
owns the local tool schemas, native DeepSeek tool-call handling, and dispatch
for workspace operations. The built-in prompt text and prompt selection live in
`bobzhang/openseek/prompt`.

The package depends on:

- `bobzhang/openseek/deepseek` for typed models, messages, roles, and tool
  definitions.
- `bobzhang/openseek/deepseek/client` for HTTP chat requests.
- `bobzhang/openseek/logger` for async stdout logging.
- `bobzhang/openseek/prompt` for built-in prompt text and model-aware prompt
  selection.
- `bobzhang/openseek/agent_tool` for tool registries, typed tool output,
  loop-control actions, and session-scoped background daemon events.
- `moonbitlang/async/fs` and `moonbitlang/async/process` for local tool
  execution.

## API Shape

- `default_system_prompt()`: return the base built-in prompt.
- `default_system_prompt_for_model(model)`: return the model-specific built-in
  prompt from the prompt package.
- `run(api_key, model, task, max_steps?, system_prompt_text?)`: run the agent
  loop for one natural-language task. `system_prompt_text` defaults to the
  model-specific built-in prompt so callers can run prompt experiments without
  rebuilding the package.

`run` creates a DeepSeek client, starts a conversation with a system prompt and
user task, sends native function tool definitions on each turn, executes any
returned tool calls, and sends `Respond(ToolOutput(...)).content` back with
`Tool(call.id())` messages. The loop stops when the model answers directly, a
tool returns `Control(Finish(...))` / `Control(Abort(...))`, or the step limit
is reached.

The agent client enables DeepSeek V4 thinking mode explicitly with
`thinking=max`. When DeepSeek returns
`reasoning_content` with tool calls, the agent preserves it in the assistant
tool-call message for the next request.

The base and Flash-specific prompt sources live in the `prompt` package. That
package uses the module-level `md_to_mbt_string` rule plus `dev_build` to
generate MoonBit multiline strings from Markdown. The generated files are
committed so downstream users can build without running local pre-build
commands.

## Tools

The agent exposes six local tools to DeepSeek by default:

- `shell`: runs `arguments.cmd` through `sh -c`, optionally in `arguments.cwd`,
  and returns exit code plus merged output.
- `read`: reads `arguments.path` as text.
- `edit`: replaces exact text in `arguments.path`.
- `write`: overwrites `arguments.path` with `arguments.content`.
- `moon_check`: starts or reuses a session-scoped
  `moon check --watch --diagnostic-limit 10` watcher, optionally
  in `arguments.cwd`, and injects later coalesced updates before model turns.
- `finish`: ends the task with `arguments.answer`.

Tool-call arguments are parsed from DeepSeek's raw JSON argument string and then
validated by the dispatcher before execution.

## Operational Notes

This package is intended for trusted local automation. The `shell` tool can run
arbitrary commands, while `edit` and `write` can modify files visible to the
process. Use the CLI package when invoking it as an application.

Run the package tests with:

```bash
moon test agent
```

## Real-World Run Notes

The DeepSeek V4-Pro TOML-parser trials showed useful cache behavior after the
stable prompt prefix, but also surfaced MoonBit-specific failure modes to keep
improving:

- The model needs concrete MoonBit examples, especially for package manifests,
  type aliases, mutable record fields, map construction, and error handling.
- The model repeatedly imported Rust habits. The prompt now calls out that
  MoonBit has no postfix `?` unwrapping for `Result`; generated code should
  match on `Ok`/`Err` or catch raising functions explicitly.
- Parser examples should include exact receiver annotations, string APIs, and
  unit syntax: `fn Parser::peek(self : Parser)`, `get_char`, `to_owned`, and
  `()` instead of `{}` for no-op branches.
- Long parser loops should avoid leaving `while` as the final expression of a
  function returning `Result`; put the final `Ok(...)`/`Err(...)` after the
  loop or return from explicit branches.
- The full-guide rerun improved API discovery and cache behavior, but still
  needed addendum guidance for native CLI imports, blackbox `Debug` tests,
  unqualified enum constructors under known types, and avoiding panicking
  `Map::at` when building nested tables.
- Long runs should be observable while they are running. The agent writes loop
  logs through `moonbitlang/async/stdio` instead of `println` so piped runs
  such as `2>&1 | tee run.log` receive step output promptly.
- Real workspace commands need a first-class working directory. The `shell`
  tool now accepts optional `cwd` to avoid repeated ad hoc `cd` command strings.
- The default step limit is 1000, and the CLI can override it with
  `--max-steps` or `OPENSEEK_MAX_STEPS`.
- Current MoonBit projects use `moon.mod`; `moon.mod.json` is legacy. New
  projects should create `moon.mod`, and manifest or package-import edits
  should be followed immediately by starting or inspecting `moon_check`.
- MoonBit validation should call `moon_check` once near the start of an
  iterative edit loop and then use background `[moon_check update]` messages for
  fresh compiler feedback. `moon_check` runs
  `moon check --watch --diagnostic-limit 10`, so broken intermediate states stay
  compact enough for the model to act on. Repeated `moon_check` calls are
  allowed and reuse the existing watcher for the same cwd/options tuple. If
  `moon --watch`
  crashes, the tool compacts the crash output and automatically starts a
  replacement watcher under a restart budget.
- Use `shell` for exact end-to-end MoonBit command validation beyond compiler
  feedback, especially `moon test`, `moon run`, `moon info`, `moon fmt`, and
  README command checks. Use shell for `moon ide doc`, `moon ide outline`,
  `moon ide peek-def`, `moon ide find-references`, and `moon ide hover`
  semantic navigation. Pass `cwd` instead of embedding `cd ... &&`.
- Before finishing user-facing CLI work, derive two or three acceptance probes
  from the task and run them with shell `moon run` commands. These probes should
  exercise real file arguments, stdin when promised, stdout shape, stderr
  cleanliness, and failure-mode output. This prompt guardrail is intentionally
  lightweight; future cram-style tests can encode the same probes as durable
  fixtures.
- For snapshot updates, run plain `moon test` first and only run
  `moon test --update` after deciding the failure is a stale snapshot or
  intentional output change, not a behavior bug.
- Use shell `moon ide doc` before unfamiliar MoonBit APIs and shell
  `moon ide outline`, `moon ide peek-def`, or `moon ide find-references` before
  editing existing packages.
- MoonBit packages are flat like Go packages: files in the same package share a
  namespace, and file names do not create importable modules. Split generated
  code into small cohesive files for reviewability, but never refer to those
  files as modules.
