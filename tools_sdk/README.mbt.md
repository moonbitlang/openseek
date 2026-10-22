# OpenSeek tools SDK

An ordinary MoonBit package for calling tools exposed by the current OpenSeek
`mbtx` invocation. This module has no dependency on the agent, editor, or host
implementation. The published SDK `moonbitlang/openseek_tools@0.2.0` speaks
PTC protocol version 1. Runnable examples use this version explicitly.

```mbtx
import {
  "moonbitlang/openseek_tools@0.2.0" @tools,
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
125-second deadline for ordinary calls, covering the host's 120-second tool
deadline. Approval-capable calls use the wait behavior described below.

MoonBit async calls suspend directly; no `await` keyword is needed. Complete
all calls and join spawned tasks before exiting. Only printed output enters
the next model request; preserve selected source URLs and relevant failures.

## MCP tools

The `moonbitlang/openseek_tools/mcp` package reaches the tools of the MCP
servers the host has connected. **`@mcp.search(query?, server?, limit?,
offset?)`** finds them and **`@mcp.call(server, tool, arguments)`** calls one by
the server's own names. They talk to the host's MCP host, a service of its own
beside PTC, whose capability the host provides in `OPENSEEK_MCP` to every
sandboxed `mbtx` run, with or without `ptc=true`.

```mbtx
import {
  "moonbitlang/openseek_tools@0.3.0/mcp" @mcp,
  "moonbitlang/async",
}

async fn main {
  // Print the page so the next model request sees the tools and schemas.
  let page = @mcp.search(query="list issues", server="github")
  println(page.text)
  guard page.tools is [tool, ..] else { return }
  let result = @mcp.call(tool.server, tool.name, { "repo": "moonbitlang/openseek" })
  if result.is_error { fail(result.content) }
  println(result.content)
}
```

`search` runs in the script. The first search downloads the host's catalog of
servers and tools, and later searches in the same script reuse it. `server`
alone lists that server's tools in order; `query` ranks tools with BM25 over
their server, name, description, and the property names and descriptions in
their schemas, within `server` when both are given; neither lists every tool.
A blank string is the same as leaving the argument out. Pages hold at most
`limit` tools (default 8) from `offset` (default 0), whose entries fit within
40,000 characters of text; a server's instructions and the list of unavailable
servers come on top.

The returned `SearchPage` has the same tools twice:
- `text`, rendered for the model once the script prints it: each tool's
  description and the JSON Schemas of its arguments and result `data`;
- `tools`, records of `server`, `name`, `description`, `input_schema : Json`,
  and `output_schema : Json?` (the raw JSON Schemas) for the script to select
  from.

`total` counts every match, `next_offset` continues the listing, and
`instructions` holds the named server's instructions on a first page. No match
is a page with no tools. A search naming an unavailable server is a page with
its error, and a listing of every tool ends with the servers that are
unavailable.

An unknown server, a `limit` below 1, a negative or past-the-end `offset`, and a
catalog that could not be downloaded (no MCP host, a transport failure) raise
`SearchError` with the reason. A search changes nothing, so a script may simply
run it again.

`call` returns the `mcp` package's own `CallResult`: `content`, `is_error`,
`data`, and `images`. A tool failure is a result with `is_error`, and a
connection/protocol failure raises the `mcp` package's own `TransportError`.
The SDK never retries it. MCP calls never wait for approval, so each keeps the
ordinary 125-second deadline. A run without `OPENSEEK_MCP` (an older host, or
no MCP server configured) raises `TransportError` from `call` and `SearchError`
from `search`, and sends nothing.

A reply is JSON, so a tool's images do not travel in it: the host saves each
in a file, names the file in `content`, and lists the paths in `images`. Pass
a path to `@openseek_tools.call("read_image", { "path": path })` to show the
image to the model.

Both use the v1 result envelope. `call` sends
`{"version":1,"call":{"server","tool","arguments"}}`, answered with an added
`"images"` when it saved any. The catalog download sends
`{"version":1,"list":{"cursor"?}}` until a reply has no `next_cursor`; each
reply's `data` is `{"items":[...],"next_cursor"?}`, with each server
(`{"server","instructions"?,"error"?}`) followed by its tools
(`{"server","tool":{"name","description","input_schema","output_schema"?}}`) in
configuration order.

## Standalone tests

Run `moon -C tools_sdk test --target native` and
`moon -C tools_sdk test --target wasm`; no OpenSeek host or SDK publication is
needed. The public-API test sets `OPENSEEK_PTC` to a temporary loopback HTTP
server, calls the dynamic entry point with built-in and extension tool names,
and checks authentication, unchanged JSON arguments (including both multi_edit forms), and typed results. It restores
the environment and joins the server on exit. Separate transport tests cover
invalid capabilities/responses, errors, no retries, and cancellation.

The `mcp` tests do the same with `OPENSEEK_MCP` for MCP calls and the catalog
download: exact request bodies, saved images, a catalog over several replies,
one download serving later searches, empty catalogs and unavailable servers,
refused and malformed listings, transport failures, and a run with no MCP
host. The catalog tests cover ranking, paging, and rendering on their own, and
the `mcp` transport tests cover its handoff, envelopes, no retries, and
cancellation.

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

Versions 0.1.0 and 0.2.0 are published; 0.3.0 is prepared here and is not
published yet. All of them speak wire protocol v1. Keep SDK and wire versions separate. Documentation and host tool additions do not require changing the SDK
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
`revert_if_warning_delta_greater_or_equal`: `edit` defaults both guards off and reports the post-write check without reverting.
Enabling either guard adds a pre-write baseline check. `multi_edit` defaults to
an error threshold of `10`; its warning guard is off. For warning fixes,
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

## Approval waits

The host may list `approval_tools` in the capability. This SDK implementation
waits for these calls without its ordinary 125-second deadline; caller
cancellation still propagates. Other calls, and calls to hosts without that
metadata, retain the deadline. Clients without this support still time out
after 125 seconds, so long approval waits require publication and adoption of
the updated SDK.
