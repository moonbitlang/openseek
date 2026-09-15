### Programmatic tool calls

Use `mbtx` with `ptc: true` when a script can compute tool arguments or filter
results without another model decision. For example, read data, calculate
replacements, call `tools.multi_edit(edits)`, and print a checked summary in one
script. For independent searches, call `tools.web_search(query)` and print only
relevant sources. A single edit or search usually needs only the direct tool.
Keep `multi_edit` for edits that need batch validation; `edits_file` is also
available. PTC does not make a sequence of separate edits one transaction.

The bundled `tools` client needs no import. Call it inside `async fn main`;
MoonBit async calls suspend directly, with no `await` keyword:

```mbtx
async fn main {
  let result = tools.edit(path="note.txt", start_line=1,
    old_string="before", new_string="after")
  if result.is_error { fail(result.content) }
  println(result.content)
}
```

`tools.multi_edit` takes an `Array[Json]` with `file`, `start_line`, `old_string`,
and `new_string` on each edit. `tools.call(name, arguments)` uses the direct
tool's schema. Normal read-before-edit, validation, and rollback rules apply.
Check every `result.is_error` before using its data or doing dependent work.
Tool errors are values; transport failures raise and may follow a completed
mutation. Re-read the affected files before deciding whether a mutation needs
retrying. Do not automatically replay a failed script that already made edits.

Search `result.data` has `{sources: [{url, title?, snippet?, published_at?}],
truncated: Bool}`. Handle absent data and fields explicitly. Only printed output
enters the next model request; nested calls are saved separately in the
transcript. Print the selected evidence with its URLs, plus errors or truncation
that affect the answer. Return to the model when a decision needs judgment.

PTC is available only when offered by `mbtx`. It stays foreground (normally up
to 300s), cannot combine with `subrun`, `escalated`, or non-wasm targets, and
exposes only enabled leaf tools, currently edit, multi_edit, and web_search.
Complete every call before exiting; join any spawned tasks. Keep batches small:
at most 64 calls and four in flight per script. Stateful calls serialize;
independent searches can overlap. See the tool description for the full API
and limits.
