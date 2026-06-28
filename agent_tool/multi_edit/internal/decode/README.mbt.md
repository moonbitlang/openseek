# Multi Edit Decode

`bobzhang/openseek/agent_tool/multi_edit/internal/decode` converts raw JSON
tool arguments into the typed `EditSource` consumed by `multi_edit`.

## API Shape

- `MultiEditItem(file, old_string, new_string, start_line, end_line)`: one exact
  line-anchored replacement against `file`; `end_line` is optional.
- `EditSource`: either `Inline(edits)` (the `edits` argument was an inline array)
  or `FromFile(path)` (the `edits` argument was a string path to a response file,
  read and parsed by the tool).
- `decode_source(arguments)`: accepts a JSON object whose single `edits` field is
  either an array or a string path, and raises focused errors for malformed
  payloads.
- `decode_edits_json(json)`: parses the bare array read from a response file into
  edit items.

## Arguments

The single `edits` field is either an array (inline) or a string (a response-file
path); both forms carry the same edit-object shape.

| Name | Type | Required | Decoder behavior |
| --- | --- | --- | --- |
| `edits` | array \| string | yes | An array of edit objects (decoded in order; must be non-empty), or a path string to a JSON file holding that array. |
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
