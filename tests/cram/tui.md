# Verified OpenSeek TUI CLI Documentation

These examples are executed by `moon cram test tests/cram`. The Moon wrapper
builds the native package at `cmd/openseek` and exposes the executable on `PATH`
as `openseek.exe`. The interactive terminal UI is the **default** mode of that
single binary; `openseek tui` is the explicit form. An initial prompt is passed
with `--prompt` (there is no free-form positional).

These commands are offline: they exercise only the argument parser and the
engine-usability preflight, which run before the terminal UI starts, so the
suite needs no API key, no TTY, and makes no network calls. The live,
API-backed examples live in [`tests/live/deepseek.md`](../live/deepseek.md).

## Help Banner

`openseek tui --help` prints the UI's options and exits successfully.

```mooncram
$ openseek.exe tui --help
Usage: openseek tui [options]

OpenSeek terminal UI.

Options:
  -h, --help                     Show help information.
  --api-key <api-key>            API key for the selected chat provider. [default: ]
  --model <model>                Chat model: deepseek-v4-flash, deepseek-v4-pro, kimi-k2.7-code, kimi-k2.7-code-highspeed, glm-5.3, or glm-5.3-flash. [env: OPENSEEK_MODEL] [default: deepseek-v4-flash]
  --api-url <api-url>            OpenAI-compatible chat completions endpoint. [env: OPENSEEK_API_URL] [default: ]
  --max-steps <max-steps>        Maximum agent steps per turn; omit to bound turns by the model's context window instead (a checkpoint summary carries each turn into the next). [env: OPENSEEK_MAX_STEPS]
  --thinking <thinking>          Model thinking mode: no, high, or max; GLM maps no to low effort. [env: OPENSEEK_THINKING] [default: high]
  --session <session>            Create or resume this durable session id.
  --session-root <session-root>  Directory containing durable OpenSeek sessions. [default: .openseek]
  --continue                     Resume the most recently active session in --session-root.
  --engine <engine>              Agent engine to spawn (default: this openseek binary); reads its JSONL event stream from stdout.
  --engine-mode <engine-mode>    Engine protocol: serve (one persistent, steerable process) or oneshot (spawn per prompt, for replay engines). [default: serve]
  --prompt <prompt>              Initial prompt to send once the UI opens.
```

## API Key Is Required

With no `--api-key` flag and no `DEEPSEEK` in the environment, the UI reports the
missing key on stderr and exits non-zero — before the terminal UI ever starts.
(The key is validated in the UI path rather than via argparse `required`, so the
root command can stay key-optional for offline engine subcommands like
`sessions list`.) The message names the model that wanted a key, not the variable
that would have supplied one; see [`cli.md`](cli.md) for which variable that is.

```mooncram
$ sh <<'EOF'
> stdout=$(mktemp)
> stderr=$(mktemp)
> if env -u DEEPSEEK -u KIMI -u OPENSEEK_MODEL openseek.exe tui > "$stdout" 2> "$stderr"; then echo exit-zero; else echo exit-non-zero; fi
> sed -n '1p' "$stderr"
> if test -s "$stdout"; then echo stdout-not-empty; else echo stdout-empty; fi
> rm -f "$stdout" "$stderr"
> EOF
exit-non-zero
error: an API key is required for deepseek-v4-flash: pass --api-key
stdout-empty
```

## Unknown Options Are Rejected

Option-looking tokens are validated by the parser before the UI starts.

```mooncram
$ sh <<'EOF'
> stdout=$(mktemp)
> stderr=$(mktemp)
> if env DEEPSEEK=test-key openseek.exe tui --xxy he > "$stdout" 2> "$stderr"; then echo exit-zero; else echo exit-non-zero; fi
> sed -n '1p' "$stderr"
> if test -s "$stdout"; then echo stdout-not-empty; else echo stdout-empty; fi
> rm -f "$stdout" "$stderr"
> EOF
exit-non-zero
error: unexpected argument '--xxy' found
stdout-empty
```

## The Engine Is Probed Before The UI Starts

The UI spawns the `openseek` engine (by default this same binary, in `serve`
mode; override with `--engine`) and probes it with `--help`
first. A missing engine fails fast, before the UI takes over the terminal.

```mooncram
$ env DEEPSEEK=test-key openseek.exe tui --engine openseek-not-a-real-binary
error: engine 'openseek-not-a-real-binary' is not usable: it must be on PATH, executable, and accept `--help` (exit 0) the way openseek does.
Pass --engine <path> or install the openseek binary.
[1]
```

## An Initial Prompt Comes From `--prompt`

`--prompt` supplies the first message. It parses and reaches the engine preflight
(shown here failing deterministically on a missing engine), which proves the
prompt path is wired — there is no free-form positional.

```mooncram
$ env DEEPSEEK=test-key openseek.exe tui --engine does-not-exist --prompt "inspect project"
error: engine 'does-not-exist' is not usable: it must be on PATH, executable, and accept `--help` (exit 0) the way openseek does.
Pass --engine <path> or install the openseek binary.
[1]
```
