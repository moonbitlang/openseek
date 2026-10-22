# Verified OpenSeek TUI CLI Documentation

These examples are executed by `moon cram test tests/cram`. The Moon wrapper
builds the native package at `cmd/openseek_tui` and exposes its executable on
`PATH` as `openseek_tui.exe`. `openseek_tui` is the dedicated interactive
terminal UI binary; an initial prompt is passed with `--prompt` (there is no
free-form positional). The engine it spawns is, by default, the pinned
`moonbitlang/openseek` release run through `moonx`; these examples stand in a
stub for it and never launch a real engine.

These commands are offline: they exercise only the argument parser and the
engine-usability preflight, which run before the terminal UI starts, so the
suite needs no API key, no TTY, and makes no network calls.

## Help Banner

`openseek_tui --help` prints the UI's options and exits successfully.

```mooncram
$ openseek_tui.exe --help
Usage: openseek_tui [options]

OpenSeek terminal UI.

Options:
  -h, --help                                 Show help information.
  --continue                                 Resume the most recently active session in --session-root.
  --api-key <api-key>                        API key for the selected chat provider. [default: ]
  --model <model>                            Chat model: deepseek-flash, deepseek-v4-pro, kimi-k2.7-code, kimi-k2.7-code-highspeed, glm-5.3, or glm-5.3-flash. [env: OPENSEEK_MODEL] [default: deepseek-flash]
  --api-url <api-url>                        OpenAI-compatible chat completions endpoint. [env: OPENSEEK_API_URL] [default: ]
  --retry-attempts <retry-attempts>          Total tries per model request before giving up on a retryable failure (429, 5xx, or a transport error); 1 disables retrying. Omit for the client default. [env: OPENSEEK_RETRY_ATTEMPTS]
  --retry-backoff-ms <retry-backoff-ms>      Delay before the first model-request retry; it doubles per attempt, capped at 60s. Omit for the client default. [env: OPENSEEK_RETRY_BACKOFF_MS]
  --max-steps <max-steps>                    Maximum agent steps per turn; omit to bound turns by the model's context window instead (a checkpoint summary carries each turn into the next). [env: OPENSEEK_MAX_STEPS]
  --thinking <thinking>                      Model thinking mode: no, high, or max; GLM maps no to low effort. [env: OPENSEEK_THINKING] [default: high]
  --session <session>                        Create or resume this durable session id.
  --session-root <session-root>              Directory containing durable OpenSeek sessions. [default: .openseek]
  --engine <engine>                          Agent engine command to spawn instead of the default (moonx running the pinned moonbitlang/openseek release); it must speak the serve JSONL protocol.
  --prompt <prompt>                          Initial prompt to send once the UI opens.
  -C, --change-directory <change-directory>  Run as if started in this directory: it becomes the workspace, and a relative --session-root or --engine path resolves against it.
```

## API Key Is Required

With no `--api-key` flag and no `DEEPSEEK` in the environment, the UI reports the
missing key on stderr and exits non-zero — before the terminal UI ever starts.
(The key is validated in the UI path rather than via argparse `required`, so the
engine can stay key-optional for offline subcommands like `sessions list`.) The
message names the model that wanted a key, not the variable that would have
supplied one; see [`cli.md`](cli.md) for which variable that is.

```mooncram
$ sh <<'EOF'
> stdout=$(mktemp)
> stderr=$(mktemp)
> if env -u DEEPSEEK -u KIMI -u OPENSEEK_MODEL openseek_tui.exe > "$stdout" 2> "$stderr"; then echo exit-zero; else echo exit-non-zero; fi
> sed -n '1p' "$stderr"
> if test -s "$stdout"; then echo stdout-not-empty; else echo stdout-empty; fi
> rm -f "$stdout" "$stderr"
> EOF
exit-non-zero
error: an API key is required for deepseek-flash: pass --api-key
stdout-empty
```

## Unknown Options Are Rejected

Option-looking tokens are validated by the parser before the UI starts.

```mooncram
$ sh <<'EOF'
> stdout=$(mktemp)
> stderr=$(mktemp)
> if env DEEPSEEK=test-key openseek_tui.exe --xxy he > "$stdout" 2> "$stderr"; then echo exit-zero; else echo exit-non-zero; fi
> sed -n '1p' "$stderr"
> if test -s "$stdout"; then echo stdout-not-empty; else echo stdout-empty; fi
> rm -f "$stdout" "$stderr"
> EOF
exit-non-zero
error: unexpected argument '--xxy' found
stdout-empty
```

## The Engine Is Probed Before The UI Starts

The UI spawns its engine in `serve` mode and probes it with `--help` first. A
missing engine fails fast, before the UI takes over the terminal.

```mooncram
$ env DEEPSEEK=test-key openseek_tui.exe --engine openseek-not-a-real-binary
error: engine 'openseek-not-a-real-binary' is not usable: it must be on PATH, executable, and accept `--help` (exit 0) the way openseek does.
Pass --engine <path> to a working openseek binary, or omit --engine to run the pinned release through moonx.
[1]
```

## The Default Engine Is The Pinned Release Under `moonx`

With no `--engine`, `openseek_tui` runs `moonx moonbitlang/openseek@<version>`,
the release this module is compiled against, so the engine always speaks the
protocol the UI expects. A stub `moonx` on `PATH` records its arguments: the
preflight passes the pinned coordinate plus `--help`, then the launch reaches
the non-TTY guard, proving the handoff.

```mooncram
$ sh <<'EOF'
> bin=$(mktemp -d)
> printf '#!/bin/sh\necho "$@" >> "%s/args"\nexit 0\n' "$bin" > "$bin/moonx"
> chmod +x "$bin/moonx"
> PATH="$bin:$PATH" env DEEPSEEK=test-key openseek_tui.exe 2>&1
> cat "$bin/args"
> rm -rf "$bin"
> EOF
error: the interactive UI needs a terminal; run a headless task with `openseek run "…"` (or `openseek serve` for the JSONL protocol).
moonbitlang/openseek@0.7.3 --help
```

Without `moonx` on `PATH` (no MoonBit toolchain), the preflight says so.

```mooncram
$ sh <<'EOF'
> ui=$(command -v openseek_tui.exe)
> env -i PATH=/usr/bin:/bin DEEPSEEK=test-key "$ui"
> EOF
error: engine 'moonx moonbitlang/openseek@0.7.3' is not usable: `moonx` was not found on PATH.
The default engine runs through moonx, part of the MoonBit toolchain; its first launch downloads the pinned openseek release, so it needs network access to mooncakes.io.
Install MoonBit, or pass --engine <path> to an openseek binary.
[1]
```

When `moonx` runs but cannot produce the engine (say, the first launch is
offline), the tail of its output is quoted so the cause is visible.

```mooncram
$ sh <<'EOF'
> bin=$(mktemp -d)
> printf '#!/bin/sh\necho "fetching moonbitlang/openseek@0.7.3"\necho "error: failed to download from mooncakes.io" >&2\nexit 1\n' > "$bin/moonx"
> chmod +x "$bin/moonx"
> PATH="$bin:$PATH" env DEEPSEEK=test-key openseek_tui.exe
> status=$?
> rm -rf "$bin"
> exit $status
> EOF
error: engine 'moonx moonbitlang/openseek@0.7.3' is not usable: `--help` exited with code 1.
Its output ended with:
  fetching moonbitlang/openseek@0.7.3
  error: failed to download from mooncakes.io
The default engine runs through moonx, part of the MoonBit toolchain; its first launch downloads the pinned openseek release, so it needs network access to mooncakes.io.
Install MoonBit, or pass --engine <path> to an openseek binary.
[1]
```

## An Initial Prompt Comes From `--prompt`

`--prompt` supplies the first message. It parses and reaches the engine preflight
(shown here failing deterministically on a missing engine), which proves the
prompt path is wired — there is no free-form positional.

```mooncram
$ env DEEPSEEK=test-key openseek_tui.exe --engine does-not-exist --prompt "inspect project"
error: engine 'does-not-exist' is not usable: it must be on PATH, executable, and accept `--help` (exit 0) the way openseek does.
Pass --engine <path> to a working openseek binary, or omit --engine to run the pinned release through moonx.
[1]
```
