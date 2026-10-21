# moonbitlang/openseek_tui

The interactive terminal UI for [OpenSeek](https://github.com/moonbitlang/openseek):
the `openseek_tui` binary. It is a scrolling transcript with a live composer
that drives the headless `openseek` engine over its JSONL protocol — streamed
answer text appears live on the activity line, each turn's reasoning is kept as
a dim `✻` transcript aside above its answer, and tool results land as `⏺`
blocks. Pressing Enter while a task runs steers it mid-turn; Ctrl-C cancels the
turn.

The UI runs no agent code itself. The engine is the separate `openseek` binary
built from the root of this repository. This module imports
`moonbitlang/openseek` for the agent, session, and provider packages and
`moonbitlang/openseek_protocol` for the wire contract; it is a member of the
repository's `moon.work`, so it builds against this checkout's copies of both,
while the published package resolves them from mooncakes.

## Running it

You need the [MoonBit toolchain](https://www.moonbitlang.com/download), which
provides `moon` and `moonx`. The engine is not installed separately: the UI runs
the `moonbitlang/openseek` release it was built against through `moonx`.

```bash
git clone https://github.com/moonbitlang/openseek && cd openseek/openseek_tui
moon build --release cmd/openseek_tui
cp ../_build/native/release/build/moonbitlang/openseek_tui/cmd/openseek_tui/openseek_tui.exe ~/.moon/bin/openseek_tui

export DEEPSEEK=sk-...
openseek_tui
```

**The engine.** With no `--engine`, the UI spawns
`moonx moonbitlang/openseek@<version> serve …`, where `<version>` is the
`moonbitlang/openseek` release imported in `moon.mod` (a test keeps the two
equal), so the engine always speaks the protocol and session format the UI was
compiled against. The first launch downloads that release's published
linear-Wasm build from mooncakes.io (so it needs the network) and caches it;
later launches start from the cache. The engine is probed with `--help` before
the UI takes over the terminal, so a missing `moonx` or a failed download is
reported up front. Pass `--engine <path>` to run a different engine binary
instead, such as a local openseek build.

**Sessions.** Every launch converses in a durable session under
`--session-root` (default `.openseek/`), interoperable with the CLI's own
sessions:

- `openseek_tui --continue` resumes the most recently active session.
- `openseek_tui --session <id>` resumes (or creates) a specific one.
- `openseek_tui --prompt "…"` sends an initial prompt once the UI opens.
- `openseek sessions list` (the engine CLI) shows what is resumable.

The shared engine options (`--api-key`, `--model`, `--api-url`, `--max-steps`,
`--thinking`, `--session`, `--session-root`) are the same ones `openseek run`
takes; `openseek_tui --help` lists them all.

## Packages

| Package | Purpose | README |
| --- | --- | --- |
| `moonbitlang/openseek_tui/cmd/openseek_tui` | The executable: parses argv and hands the parsed matches to `cmd/tui`. | — |
| `moonbitlang/openseek_tui/cmd/tui` | The OpenSeek terminal UI: engine spawn and protocol handling, transcript model, slash commands, session resume. | [`cmd/tui/README.md`](cmd/tui/README.md) |
| `moonbitlang/openseek_tui/tui` (+ `core`, `doc`, `style`, `slash`, `completion`) | Reusable terminal-UI framework (transcript, composer, rendering) the OpenSeek UI is built on. Agent-agnostic. | [`tui/README.md`](tui/README.md) |

## Development

The repository's root gates (`just check`, `just test`) cover this module
along with the rest of the workspace. From the repository root, to work on the
UI alone:

```bash
moon check --target native --deny-warn
moon test --target native $(git ls-files -- 'openseek_tui/*moon.pkg' | xargs -n1 dirname)
moon cram test openseek_tui/tests/cram   # verified CLI docs: tests/cram/tui.md
moon fmt
moon info                                # regenerate pkg.generated.mbti after API changes
```

A plain `moon test` tests every workspace member, not just this module.

`tests/cram/tui.md` is executable documentation of the `openseek_tui` command
line (help banner, argument errors, the engine preflight). It runs offline and
needs no API key.

**Running the checkout's engine.** The workspace only changes what the UI
compiles against; on its own the UI still spawns the pinned release through
`moonx`, which may speak an older protocol than the one it was built against.
From the repository root, `just tui` builds both binaries and runs the UI with
`--engine` pointing at this checkout's `openseek` (flags pass through, e.g.
`just tui --continue`).

## Publishing

The module is published to mooncakes as `moonbitlang/openseek_tui` by the
repository's `publish-openseek-tui` workflow
(`.github/workflows/publish-openseek-tui.yml`, run manually via workflow
dispatch) using the organization's mooncakes token.

It is released in lockstep with the engine: `moonbitlang/openseek_tui@X`
imports and runs `moonbitlang/openseek@X`. The release PR that bumps the root
`moon.mod` to `X` also sets this module's `version`, its `moonbitlang/openseek`
import, `EngineModuleVersion` in `cmd/tui/main.mbt`, and the cram fixtures to
`X` (a test and a CI step fail until they agree). The workflow checks the
staged package against the registry, so dispatch it after
`publish-openseek-protocol` (when the protocol changed) and `publish-openseek`,
and check that the engine release has a published linear-Wasm build, since that
is what `moonx` downloads.

## History

The UI was extracted from this repository on 2026-09-03 into
[moonbitlang/openseek_tui](https://github.com/moonbitlang/openseek_tui) with
`git filter-repo`, keeping the history of `tui/`, `cmd/tui/`,
`cmd/openseek_tui/`, and `tests/cram/tui.md`. It was merged back into
`openseek_tui/` on 2026-10-21, again with its history, as a `moon.work` member
so that engine and protocol changes are built and tested against it in the same
change. PR numbers in its commit messages from that period refer to
moonbitlang/openseek_tui.

## License

Apache-2.0, see [LICENSE](LICENSE).
