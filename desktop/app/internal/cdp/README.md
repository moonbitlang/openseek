# CDP client

A native MoonBit package for the CDP subset used by Desktop's browser picker.
It depends on async HTTP/WebSocket and core codecs, not Proton or Desktop's
commands, protocol, frontend, or mention types.

`list_targets(port)` returns targets with a `target.connect()` method. Targets
keep their debugger endpoint private and validate it against the discovery port.

`Connection` exposes typed methods such as `resolve_node(BackendNodeId) ->
RemoteObject` and `call_function_on(CallFunction) -> Evaluation`. Their signatures
reject mismatched parameters or reply types at compile time. Raw request dispatch,
wire method names, and JSON codecs stay private. `commands.mbt` contains these
methods; `protocol.mbt` defines handles, results, and events; `overlay.mbt` contains
the typed highlight configuration and the existing DevTools color preset.

`evaluate` and `call_function_on` return by value. Their `Evaluation.decode_value`
decodes the JavaScript value into the caller's type, distinguishing a JSON null,
a missing value, a script exception, and a CDP command error. They do not await
Promises. This is a bounded subset, not a complete generated CDP SDK.

`accessibility_tree` returns the main frame's accessibility tree as `AxNode`s,
keeping only each `AXValue`'s own value; frames' documents are not included.
`input.mbt` locates an element (`scroll_into_view`, and `content_quads` and
`viewport_size` in CSS pixels of the viewport) and gives the page trusted
input:
`dispatch_mouse_event` for the primary button, `dispatch_key_event` for the
keys the browser tools press, and `insert_text`.

The owner serializes commands and event reads and closes the connection.
Overlapping reads are rejected. Events received before a command reply are
queued, and unknown events are ignored. Existing limits remain: five seconds
per command, two MiB per received message (32 MiB for an accessibility tree,
which runs to several megabytes on a long page), and sixteen queued relevant
events.
Interrupted reads or writes (including cancellation and timeout) close the
connection because a partially consumed WebSocket frame cannot safely be resumed;
the caller must reconnect. A fully received CDP command error keeps it usable.
Native-view matching, CEF startup configuration, selection lifecycle, and element
snapshots belong to the host integration, added separately in PR #1910.

Protocol references: [Runtime](https://chromedevtools.github.io/devtools-protocol/tot/Runtime/),
[DOM](https://chromedevtools.github.io/devtools-protocol/tot/DOM/),
[Accessibility](https://chromedevtools.github.io/devtools-protocol/tot/Accessibility/),
[Input](https://chromedevtools.github.io/devtools-protocol/tot/Input/),
and [Overlay](https://chromedevtools.github.io/devtools-protocol/tot/Overlay/).
