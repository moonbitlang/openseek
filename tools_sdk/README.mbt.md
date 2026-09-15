# OpenSeek tools SDK

An ordinary MoonBit package for calling tools exposed by the current OpenSeek
`mbtx` invocation. This module has no dependency on the agent, editor, or host
implementation. Version 0.1.0 speaks PTC protocol version 1.

After this module is published, scripts can import a pinned version:

```mbtx
import {
  "bobzhang/openseek_tools@0.1.0" @tools,
}

async fn main {
  let result = @tools.edit({
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

Each named function accepts one `Json` object, using exactly the same arguments
as the direct host tool. The SDK forwards it unchanged; validation and defaults
stay in the host. There is no second argument schema to learn.

- `edit(arguments)` forwards to `edit`.
- `multi_edit(arguments)` forwards to `multi_edit`, including `edits` or `edits_file`.
- `web_search(arguments)` forwards to `web_search`.
- `call(name, arguments)` supports other explicitly enabled host tools.

For example, use `@tools.multi_edit({ "edits": edits })` and
`@tools.web_search({ "query": "MoonBit async" })`.

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
server, calls each exported entry point, and checks authentication, unchanged
JSON arguments (including both multi_edit forms), and typed results. It restores
the environment and joins the server on exit. Separate transport tests cover
invalid capabilities/responses, errors, no retries, and cancellation.

## Release order

1. Review and merge this independent SDK module.
2. Check, test, package, and publish version 0.1.0 from `tools_sdk/`.
3. Verify that a fresh `.mbtx` process resolves the pinned public import.
4. Merge the dependent host bridge after its real-script tests pass against
   that published version. Desktop and prompt changes follow the bridge.

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
