# OpenSeek tools SDK

An ordinary MoonBit package for calling tools exposed by the current OpenSeek
`mbtx` invocation. This module has no dependency on the agent, editor, or host
implementation. SDK 0.2.0 (unreleased, `moonbitlang/openseek_tools`) speaks PTC
protocol version 1.

The dynamic API also works with the published 0.1.0, which still lives under the
old owner, so the runnable examples pin `bobzhang/openseek_tools@0.1.0` until
0.2.0 is published under `moonbitlang`:

```mbtx
import {
  "bobzhang/openseek_tools@0.1.0" @tools,
  "moonbitlang/async",
}

async fn main {
  let result = @tools.call("edit", {
    "path": "note.txt", "start_line": 1,
    "old_string": "before", "new_string": "after",
  })
  if result.is_error { fail(result.content) }
  println(result.content)
}
```

Run the script with `mbtx(ptc=true)`. The host provides a run-scoped connection
capability in `OPENSEEK_PTC`; importing this package does not grant permission or
start a server. Script source is not rewritten. Outside a compatible host,
calling the SDK raises `TransportError`.

## API

Use **`@tools.call(name, arguments)`** for every host-enabled tool. `arguments`
is the same `Json` object used by the direct tool. The SDK forwards it unchanged;
validation, defaults, and callable-tool permissions stay in the host. Adding a
host tool needs no SDK release. Use the current host tool descriptions for names
and schemas; the SDK does not carry a second tool catalog.

```mbt nocheck
///|
let batch = @tools.call("multi_edit", { "edits": edits })

///|
let search = @tools.call("web_search", { "query": "MoonBit async" })
```

The SDK exposes only `call(name, arguments)`, `CallResult`, and `TransportError`.
Version 0.2.0 removes the tool-specific wrappers from 0.1.0. Replace
`@tools.edit(args)` with `@tools.call("edit", args)` (likewise for `multi_edit`
and `web_search`). The wire protocol and JSON arguments are unchanged.

`CallResult` contains `content : String`, `is_error : Bool`, and `data : Json?`.
A host tool error is a result. Connection/protocol failures raise
`TransportError`; a mutation may already have executed, so the SDK never retries.
Caller cancellation propagates. The complete request and response body have a
125-second deadline, covering the host's 120-second tool deadline.

MoonBit async calls suspend directly; no `await` keyword is needed. Complete
all calls and join spawned tasks before exiting. Only printed output enters
the next model request; preserve selected source URLs and relevant failures.

## Standalone tests

Run `moon -C tools_sdk test --target native` and
`moon -C tools_sdk test --target wasm`; no OpenSeek host or SDK publication is
needed. The public-API test sets `OPENSEEK_PTC` to a temporary loopback HTTP
server, calls the dynamic entry point with built-in and extension tool names,
and checks authentication, unchanged JSON arguments (including both multi_edit forms), and typed results. It restores
the environment and joins the server on exit. Separate transport tests cover
invalid capabilities/responses, errors, no retries, and cancellation.

## Complete example: fix deprecation warnings

The host [PR #1532](https://github.com/moonbitlang/openseek/pull/1532) includes a
complete deprecation migration example. It reads real compiler
diagnostics, prepares line-anchored edits for a known API migration, calls
`@tools.call("multi_edit", { "edits": edits })`, then verifies the project with
`moon check --deny-warn` and `moon test`. Its integration test runs the script
through the published SDK and verifies that a second run performs no edits.
The example needs a PTC-enabled OpenSeek build; the SDK tests above remain
independent of the host PR.

## Development and releases

Version 0.1.0 is published; 0.2.0 is prepared here and is not published yet. Both
speak wire protocol v1. Keep SDK and wire versions separate. Documentation and host tool additions do not require changing the SDK
API. For a future SDK release, check and test the independent module first:

```sh
moon -C tools_sdk check --target native --deny-warn
moon -C tools_sdk test --target native
moon -C tools_sdk test --target wasm
moon -C tools_sdk info
moon -C tools_sdk fmt
moon -C tools_sdk package
# Release action after review:
moon -C tools_sdk publish
```

SDK and wire protocol versions are distinct. A future host must reject an
unsupported wire version explicitly. Publish a new SDK version for API changes;
never depend on an unpinned latest version in generated examples.

## Warning-fix loop

The host's `edit` and `multi_edit` tools accept `revert_if_error_delta_greater_or_equal` and
`revert_if_warning_delta_greater_or_equal`: `moon check` runs before and after
the write. The error default is `5` for `edit` and `10` for `multi_edit`; warnings are unguarded by default. For warning fixes,
at `1`, the error guard rejects an increased error total; at `0`, the
warning guard requires a net decrease in warning count (`after - before < 0`).
Errors can change which packages the compiler reaches, so a lower reported count
does not guarantee no new problems. Review diagnostics when the baseline has errors.
Every result's `data` names the
`outcome` and, for a guarded edit, `introduced_count` and `removed_count` per
severity, so a script can fix diagnostics one at a time and keep what the
host accepted. The script finds its targets by running `moon check
--output-json` itself (the sandbox admits `moon check`); one line per
diagnostic, with `level`, `error_code`, `path`, `loc` (`line:col-line:col`,
1-based, end exclusive, columns in code points) and `message`.

```mbt nocheck
///|
let result = @tools.call("edit", {
  "path": site.path,
  "start_line": site.line,
  "end_line": site.line,
  "old_string": line_prefix_through_span,
  "new_string": line_prefix_before_span + replacement,
  "revert_if_error_delta_greater_or_equal": 1,
  "revert_if_warning_delta_greater_or_equal": 0,
})
match result.data {
  Some({ "outcome": "applied", .. }) => fixed += 1
  Some({ "outcome": "reverted", "reason": String(reason), .. }) =>
    leftovers.push("\{site.path}:\{site.line}: \{reason}")
  _ => leftovers.push(result.content)
}
```

Anchoring `old_string` on the whole line prefix through the diagnosed span
makes the first match at `start_line` exactly that occurrence, and working
bottom-up per file and right to left per line keeps every remaining span
valid without a second check. `share/workflow/fix-deprecations.mbtx` is this
loop for deprecation warnings that name a bare replacement.
