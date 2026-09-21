# Headless CLI implementation

The root package and the deprecated `cmd/openseek` package both call `run_cli`,
which owns process-level diagnostics and exit status. `dispatch` parses
arguments and calls the selected handler. The legacy entry point adds a warning
to stderr before invoking the shared runner.

| Package | Owns |
| --- | --- |
| `options` | The argparse command tree, option definitions, and value validation — except `--approval`'s value, which `execution` parses into its policy. |
| `setup` | Workspace preparation, prompt assembly, session initialization, child IDs, launch paths and scratch labs, and goal baseline capture. |
| `execution` | JSONL event draining, the approval policy and its requests, extra tools and MCP connections, and review gates. |
| `run` | One-shot turns and fleet attempts in independent workspaces. |
| `serve` | The persistent command loop, scheduling state, cancellation, and goal continuation. |
| `commands` | Session management, standalone review, child subruns, and MCP inspection. |
| `testkit` | Test-only argv parsers (`run_matches`, `sessions_leaf_matches`), imported `for "wbtest"`. |

Production dependencies flow from the dispatcher to the command handlers, then
to shared setup, execution, and options. Shared packages do not import command
handlers. The existing agent, session, protocol, and MCP libraries remain below
these CLI adapters; `cli` retains only reusable argument and terminal helpers.

Keep command-specific behavior with its handler. Put shared functionality below
the handlers before adding a second caller: executable discovery and child ID
allocation, for example, belong to `setup`, even though child subruns also use
them. Export only what another package needs. Keep the serve loop's state and
approval desk's fields private.

`execution.with_jsonl_stdout` opens and fully drains the event sink around
`run`, `serve`, and `subrun`. Other commands leave the sink closed so their
stdout contains only their own report or listing. Keep this lifetime explicit:
in particular, a subrun's final report must follow all its queued events, and
process exit belongs outside the drain's scope.

There is no logger in this binary: nothing linked into either entry point logs, so
stdout carries only the event stream or the command's own output. The
`MOON_XLOG` case in `tests/cram/cli.md` guards this for `run`; keep it true
for every package here, since a logging import in any one of them would
corrupt fd 1 for every `run`, `serve`, and `subrun` consumer.

Tests live in the owning packages' `*_wbtest.mbt` files. The test-only parser
helpers live in `testkit`, imported `for "wbtest"` only, so they add no
production API. The command tree lives in `options` so handler tests can parse
real arguments without importing the dispatcher.

For a focused check from the repository root, run:

```sh
moon test internal/openseek/options internal/openseek/setup internal/openseek/execution internal/openseek/run internal/openseek/serve internal/openseek/commands --target native
```

Before completing a change, run `just check`, `just test`, and `just build`;
the offline CLI tests cover the unchanged executable entry point.
