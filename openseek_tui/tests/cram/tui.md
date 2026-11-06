# Verified OpenSeek TUI CLI Documentation

Run these examples from the repository root with
`moon -C openseek_tui testcli test tests/cram`. Simple cases invoke the local
`cmd/openseek_tui` package directly. The [MoonBit fixtures](fixtures/)
create temporary sessions and launch the UI through `moon run`, using the default
Wasm backend. They remove their temporary directories after each case.

`openseek_tui` is the dedicated interactive terminal UI; an initial prompt is
passed with `--prompt` (there is no free-form positional). The engine it spawns
is, by default, the pinned `moonbitlang/openseek` release run through `moonx`.
These commands are offline: they exercise argument validation, missing-engine
errors, and existing-session constraints before the terminal UI starts. They run
the real local CLI, require no API key or TTY, and make no model API calls.

## Help Banner

`openseek_tui --help` prints the UI's options and exits successfully.

```mooncram moonbitlang/openseek_tui
$ moonx moonbitlang/openseek_tui/cmd/openseek_tui --help
Usage: openseek_tui [options]

OpenSeek terminal UI.

Options:
  -h, --help                                                   Show help information.
  --continue                                                   Resume the most recently active session in --session-root.
  --api-key <api-key>                                          API key for the selected chat provider. [default: ]
  --model <model>                                              Chat model: deepseek-flash, deepseek-v4-pro, kimi-k2.7-code, kimi-k2.7-code-highspeed, glm-5.3, or glm-5.3-flash. [env: OPENSEEK_MODEL] [default: deepseek-flash]
  --api-url <api-url>                                          OpenAI-compatible chat completions endpoint. [env: OPENSEEK_API_URL] [default: ]
  --retry-attempts <retry-attempts>                            Total tries per model request before giving up on a retryable failure (429, 5xx, or a transport error); 1 disables retrying. Omit for the client default. [env: OPENSEEK_RETRY_ATTEMPTS]
  --retry-backoff-ms <retry-backoff-ms>                        Delay before the first model-request retry; it doubles per attempt, capped at 60s. Omit for the client default. [env: OPENSEEK_RETRY_BACKOFF_MS]
  --max-steps <max-steps>                                      Maximum agent steps per turn; omit to bound turns by the model's context window instead (a checkpoint summary carries each turn into the next). [env: OPENSEEK_MAX_STEPS]
  --thinking <thinking>                                        Model thinking mode: no, high, or max; GLM maps no to low effort. [env: OPENSEEK_THINKING] [default: high]
  --session <session>                                          Create or resume this durable session id.
  --session-root <session-root>                                Directory containing durable OpenSeek sessions. [default: .openseek]
  --engine <engine>                                            Agent engine command to spawn instead of the default (moonx running the pinned moonbitlang/openseek release); it must speak the serve JSONL protocol.
  --prompt <prompt>                                            Initial prompt to send once the UI opens.
  --system-prompt-file <system-prompt-file>                    Read the system prompt of the session this launch creates from this file instead of the built-in prompt; a session that already exists keeps the prompt it stored.
  --system-prompt-addendum-file <system-prompt-addendum-file>  Append this file to the system prompt of the session this launch creates; a session that already exists keeps the prompt it stored.
  -C, --change-directory <change-directory>                    Run as if started in this directory: it becomes the workspace, and a relative --session-root or --engine path resolves against it.
```

## API Key Is Required

With no `--api-key` flag and no `DEEPSEEK` in the environment, the UI reports the
missing key on stderr and exits non-zero — before the terminal UI ever starts.
(The key is validated in the UI path rather than via argparse `required`, so the
engine can stay key-optional for offline subcommands like `sessions list`.) The
message names the model that wanted a key, not the variable that would have
supplied one; see the root CLI guide for which variable that is.

```mooncram moonbitlang/openseek_tui
$ DEEPSEEK= KIMI= OPENSEEK_MODEL=deepseek-flash moonx moonbitlang/openseek_tui/cmd/openseek_tui
@STDOUT (empty)
@STDERR
error: an API key is required for deepseek-flash: pass --api-key
[1]
```

## Unknown Options Are Rejected

Option-looking tokens are validated by the parser before the UI starts.

```mooncram moonbitlang/openseek_tui
$ DEEPSEEK=test-key moonx moonbitlang/openseek_tui/cmd/openseek_tui --xxy he
@STDOUT (empty)
@STDERR
error: unexpected argument '--xxy' found

Usage: openseek_tui [options]

OpenSeek terminal UI.

Options:
  -h, --help                                                   Show help information.
  --continue                                                   Resume the most recently active session in --session-root.
  --api-key <api-key>                                          API key for the selected chat provider. [default: ]
  --model <model>                                              Chat model: deepseek-flash, deepseek-v4-pro, kimi-k2.7-code, kimi-k2.7-code-highspeed, glm-5.3, or glm-5.3-flash. [env: OPENSEEK_MODEL] [default: deepseek-flash]
  --api-url <api-url>                                          OpenAI-compatible chat completions endpoint. [env: OPENSEEK_API_URL] [default: ]
  --retry-attempts <retry-attempts>                            Total tries per model request before giving up on a retryable failure (429, 5xx, or a transport error); 1 disables retrying. Omit for the client default. [env: OPENSEEK_RETRY_ATTEMPTS]
  --retry-backoff-ms <retry-backoff-ms>                        Delay before the first model-request retry; it doubles per attempt, capped at 60s. Omit for the client default. [env: OPENSEEK_RETRY_BACKOFF_MS]
  --max-steps <max-steps>                                      Maximum agent steps per turn; omit to bound turns by the model's context window instead (a checkpoint summary carries each turn into the next). [env: OPENSEEK_MAX_STEPS]
  --thinking <thinking>                                        Model thinking mode: no, high, or max; GLM maps no to low effort. [env: OPENSEEK_THINKING] [default: high]
  --session <session>                                          Create or resume this durable session id.
  --session-root <session-root>                                Directory containing durable OpenSeek sessions. [default: .openseek]
  --engine <engine>                                            Agent engine command to spawn instead of the default (moonx running the pinned moonbitlang/openseek release); it must speak the serve JSONL protocol.
  --prompt <prompt>                                            Initial prompt to send once the UI opens.
  --system-prompt-file <system-prompt-file>                    Read the system prompt of the session this launch creates from this file instead of the built-in prompt; a session that already exists keeps the prompt it stored.
  --system-prompt-addendum-file <system-prompt-addendum-file>  Append this file to the system prompt of the session this launch creates; a session that already exists keeps the prompt it stored.
  -C, --change-directory <change-directory>                    Run as if started in this directory: it becomes the workspace, and a relative --session-root or --engine path resolves against it.
"" (escaped)
[1]
```

## The Engine Is Probed Before The UI Starts

The UI spawns its engine in `serve` mode and probes it with `--help` first. A
missing engine fails fast, before the UI takes over the terminal.

```mooncram moonbitlang/openseek_tui
$ DEEPSEEK=test-key moonx moonbitlang/openseek_tui/cmd/openseek_tui --engine openseek-not-a-real-binary
error: engine 'openseek-not-a-real-binary' is not usable: it must be on PATH, executable, and accept `--help` (exit 0) the way openseek does.
Pass --engine <path> to a working openseek binary, or omit --engine to run the pinned release through moonx.
[1]
```

## The Default Engine Is The Pinned Release Under `moonx`

With no `--engine`, `openseek_tui` selects the pinned
`moonbitlang/openseek@<version>` release. The existing
[version-binding test](../../cmd/tui/engine_version_wbtest.mbt) checks that this
version matches the module and its engine dependency.

Without `moonx` on `PATH` (no MoonBit toolchain), the preflight says so.

```mooncram moonbitlang/openseek_tui
$ PATH= DEEPSEEK=test-key OPENSEEK_MODEL=deepseek-flash moonx moonbitlang/openseek_tui/cmd/openseek_tui
error: engine 'moonx moonbitlang/openseek@0.7.5' is not usable: `moonx` was not found on PATH.
The default engine runs through moonx, part of the MoonBit toolchain; its first launch downloads the pinned openseek release, so it needs network access to mooncakes.io.
Install MoonBit, or pass --engine <path> to an openseek binary.
[1]
```

## An Initial Prompt Comes From `--prompt`

`--prompt` supplies the first message. It parses and reaches the engine preflight
(shown here failing deterministically on a missing engine), which proves the
prompt path is wired — there is no free-form positional.

```mooncram moonbitlang/openseek_tui
$ DEEPSEEK=test-key moonx moonbitlang/openseek_tui/cmd/openseek_tui --engine does-not-exist --prompt "inspect project"
error: engine 'does-not-exist' is not usable: it must be on PATH, executable, and accept `--help` (exit 0) the way openseek does.
Pass --engine <path> to a working openseek binary, or omit --engine to run the pinned release through moonx.
[1]
```

## A Custom System Prompt Comes From The Prompt File Flags

`--system-prompt-file` replaces the built-in prompt and
`--system-prompt-addendum-file` appends to it, for the session this launch
creates. Both parse and reach the engine preflight here, which fails
deterministically on a missing engine.

```mooncram moonbitlang/openseek_tui
$ DEEPSEEK=test-key moonx moonbitlang/openseek_tui/cmd/openseek_tui --engine does-not-exist --system-prompt-file prompt.md --system-prompt-addendum-file addendum.md
error: engine 'does-not-exist' is not usable: it must be on PATH, executable, and accept `--help` (exit 0) the way openseek does.
Pass --engine <path> to a working openseek binary, or omit --engine to run the pinned release through moonx.
[1]
```

The prompt is written into a new session's header, so a session that already
exists keeps the one it stored. Naming one with an existing `--session` is
refused before the engine runs, pointing at the fork that changes it. The
paths inside that hint are this machine's, so they are normalized here.

```mooncram
$ moonx fixtures/existing-session-prompt.mbtx
error: --system-prompt-file applies only when this launch creates the session, and session demo already exists with the system prompt it stored. Fork it to change the prompt:
  openseek sessions fork demo --as <new-id> --dir <workspace> --session-root <root> --system-prompt-file <file>
status=1
```

`--continue` resolves to the same stored session and is refused the same way;
the hint repeats the addendum flag when that is what was given.

```mooncram
$ moonx fixtures/continued-session-prompt.mbtx
error: --system-prompt-addendum-file applies only when this launch creates the session, and session demo already exists with the system prompt it stored. Fork it to change the prompt:
  openseek sessions fork demo --as <new-id> --dir <workspace> --session-root <root> --system-prompt-addendum-file <file>
status=1
```
