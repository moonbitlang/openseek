# Multi Edit Decode

`bobzhang/openseek/agent_tool/multi_edit/internal/decode` converts raw JSON
tool arguments into the typed `MultiEditInput` record consumed by `multi_edit`.

## API Shape

- `MultiEditItem(file, old_string, new_string, start_line, end_line)`: one exact
  line-anchored replacement against `file`; `end_line` is optional.
- `EditSource`: either `Inline(edits)` (the inline `edits` array) or
  `FromFile(path)` (the `edits_file` path, read and parsed by the tool).
- `decode_source(arguments)`: accepts a JSON object, enforces that exactly one
  of `edits` / `edits_file` is present, and raises focused errors for malformed
  payloads.
- `decode_edits_json(json)`: parses the bare array read from an `edits_file`
  into edit items.

## Arguments

Exactly one of `edits` or `edits_file` must be present.

| Name | Type | Required | Decoder behavior |
| --- | --- | --- | --- |
| `edits` | array | one-of | Must be non-empty; entries are decoded in order. |
| `edits_file` | string | one-of | Path to a JSON file holding the same array of edit objects. |
| `edits[i].file` | string | yes | Missing or non-string values raise `arguments.edits[i].file`. |
| `edits[i].old_string` | string | yes | Missing or non-string values raise `arguments.edits[i].old_string`. |
| `edits[i].new_string` | string | yes | Missing or non-string values raise `arguments.edits[i].new_string`. |
| `edits[i].start_line` | integer | yes | Positive 1-based inclusive search start. |
| `edits[i].end_line` | integer | no | Optional positive 1-based inclusive range end; when present, it must be greater than or equal to `start_line`. |

The decoder does not check whether `old_string` occurs in the file, nor that a
file's edits are contiguous. The parent tool validates all edit entries against
the original file content and writes only after all entries are valid.

```moonbit check
///|
test "decode multi_edit input from tool arguments" {
  let source = @decode.decode_source({
    "edits": [
      {
        "file": "lib/parser.mbt",
        "old_string": "parse_expr",
        "new_string": "parse_expression",
        "start_line": 10,
      },
    ],
  })
  guard source is Inline(edits) else { fail("expected an inline source") }
  assert_eq(edits.length(), 1)
  assert_eq(edits[0].file, "lib/parser.mbt")
  assert_eq(edits[0].start_line, 10)
  assert_true(edits[0].end_line is None)
}
```
