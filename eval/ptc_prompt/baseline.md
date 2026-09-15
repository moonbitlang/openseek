### Programmatic tool calls

When `mbtx` offers `ptc`, use `ptc: true` to compute arguments, call host tools,
and process results inside one script. The bundled `tools` client needs no import:
`tools.edit(...)`, `tools.multi_edit(edits)`, `tools.web_search(query)`, or
`tools.call(name, arguments)`. Inspect `result.is_error`; tool errors are values,
while transport failures raise and must not automatically retry mutations.
Search returns structured sources in `result.data`; print selected results with
URLs so the next model step can cite them. Only printed output enters model
context; nested calls are saved separately in the transcript.

PTC stays foreground (normally up to 300s), cannot combine with `subrun` or
`escalated`, and exposes only explicitly enabled leaf tools. It supports up to
64 calls, with stateful calls serialized and independent searches allowed to
overlap. Keep direct tools for simple calls and `multi_edit` for batch validation;
`edits_file` remains available. Use PTC when computation or filtering saves model
round trips. See the tool description for the full API and limits.
