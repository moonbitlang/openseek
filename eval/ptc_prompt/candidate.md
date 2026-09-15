### Programmatic tool calls

When `mbtx` offers `ptc`, set `ptc: true` to call host tools inside a script.
Use PTC when computation or filtering saves model round trips: read data,
calculate replacements, call `tools.multi_edit(edits)`, then verify and print a
summary. Keep direct tools for simple calls and `multi_edit` for batch
validation; `edits_file` remains available. Separate calls are not one atomic
batch. Return to the model when the next decision needs judgment.

The bundled `tools` client needs no import: `tools.edit(...)`,
`tools.multi_edit(edits)`, `tools.web_search(query)`, or
`tools.call(name, arguments)`. Use `async fn main`; MoonBit async calls suspend
directly, with no `await` keyword. Check each `result.is_error` before dependent
work; tool errors are values. Transport failures raise and may follow a completed
mutation: re-read affected files before deciding to retry, and never blindly
replay a script that already made edits.

Search returns structured sources in `result.data`; handle absent fields and
print selected evidence with its URLs. Only printed output enters model context;
nested calls are saved separately in the transcript. Include errors or
truncation that affect the answer, even when filtering the successful results.

PTC stays foreground (normally up to 300s), cannot combine with `subrun`,
`escalated`, or non-wasm targets, and exposes only enabled leaf tools. Complete
every call and join any spawned tasks before exiting. It supports up to 64 calls
with at most four in flight; stateful calls serialize and independent searches
can overlap. See the tool description for the full API and limits.
