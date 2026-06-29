# Multi Edit Decode

`bobzhang/openseek/agent_tool/multi_edit/internal/decode` converts raw JSON
tool arguments into the typed `MultiEditArgs` consumed by `multi_edit`.

## API Shape

- `MultiEditItem(file, old_string, new_string, start_line, end_line)`: one exact
  line-anchored replacement against `file`; `end_line` is optional.
- `MultiEditArgs(inline, edits_file)`: the inline `edits` array (possibly empty)
  plus an optional `edits_file` path. The tool concatenates the inline edits with
  the file's edits and rejects only the combined-empty batch.
- `decode_args(arguments)`: accepts a JSON object with optional `edits` (array)
  and `edits_file` (string) fields — two independent mono-typed fields, no
  `oneOf` — and raises focused errors for malformed payloads.
- `decode_edits_json(json)`: parses the bare array read from a response file into
  edit items.

## Arguments

`edits` and `edits_file` are independent and both optional; the tool uses
whichever are present (concatenated). The combined-empty case is rejected by the
tool, not the decoder.

| Name | Type | Required | Decoder behavior |
| --- | --- | --- | --- |
| `edits` | array | no | Array of edit objects, decoded in order. A non-array raises `arguments.edits to be an array of edit objects`. |
| `edits_file` | string | no | Path to a JSON file holding an array of the same objects. A non-string raises `arguments.edits_file to be a string path`. |
| `edits[i].file` | string | yes | Absent raises `arguments.edits[i] to include file (present keys: …)`; non-string raises `arguments.edits[i].file to be a string`. |
| `edits[i].old_string` | string | yes | Same missing/wrong-type behavior as `file`. |
| `edits[i].new_string` | string | yes | Same missing/wrong-type behavior as `file`. |
| `edits[i].start_line` | integer | yes | Positive 1-based inclusive search start; absent lists the present keys so a misnamed key (e.g. `line`) is obvious. |
| `edits[i].end_line` | integer | no | Optional positive 1-based inclusive range end; when present, it must be greater than or equal to `start_line`. |

The decoder does not check whether `old_string` occurs in the file, nor that a
file's edits are contiguous. The parent tool validates all edit entries against
the original file content and writes only after all entries are valid.

```moonbit check
///|
test "decode multi_edit input from tool arguments" {
  let args = @decode.decode_args({
    "edits": [
      {
        "file": "lib/parser.mbt",
        "old_string": "parse_expr",
        "new_string": "parse_expression",
        "start_line": 10,
      },
    ],
  })
  assert_true(args.edits_file is None)
  let edits = args.inline
  assert_eq(edits.length(), 1)
  assert_eq(edits[0].file, "lib/parser.mbt")
  assert_eq(edits[0].start_line, 10)
  assert_true(edits[0].end_line is None)
}
```
