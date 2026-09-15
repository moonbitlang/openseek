# Headless CLI implementation

`cmd/openseek` owns the executable entry point, error reporting, and exit status.
This internal package exports only `dispatch`, which parses arguments and calls
the selected handler. The executable path and command-line interface stay stable
as the implementation grows.

| Package | Owns |
| --- | --- |
| `options` | The argparse command tree, option definitions, and value validation. |
| `setup` | Workspace preparation, prompt assembly, session initialization, child IDs and launch paths, and goal baseline capture. |
| `execution` | JSONL event draining, approval requests, extra tools and MCP connections, and review gates. |
| `run` | One-shot turns and fleet attempts in independent workspaces. |
| `serve` | The persistent command loop, scheduling state, cancellation, and goal continuation. |
| `commands` | Session management, standalone review, child subruns, and MCP inspection. |

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

Tests live in the owning packages' `*_wbtest.mbt` files. Test-only parser helpers
stay local to those tests, so they do not add production APIs. The command tree
lives in `options` so handler tests can parse real arguments without importing
the dispatcher.

For a focused check from the repository root, run:

```sh
moon test internal/openseek/options internal/openseek/setup internal/openseek/execution internal/openseek/run internal/openseek/serve internal/openseek/commands --target native
```

Before completing a change, run `just check`, `just test`, and `just build`;
the offline CLI tests cover the unchanged executable entry point.
