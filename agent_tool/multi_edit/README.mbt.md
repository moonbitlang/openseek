# Multi Edit Tool

`multi_edit` applies many exact line-anchored replacements across one or more
files in a single validated batch. It is intended for efficient
compiler-feedback repair loops: when `moon check` (or another analyzer) points
at several known locations, the caller can fix them all in one tool call instead
of issuing many separate `edit` calls.

## Design Rationale

Every edit carries its own `file`, `old_string`, `new_string`, and required
`start_line`; optional `end_line` bounds the search when useful. Because each
edit names its file, a single batch can span several files — but all edits for a
given file must be listed **contiguously**, so each file is read, validated, and
written exactly once. The tool validates every replacement against the original
content of its file before writing anything. If any edit fails, the response
reports every failed edit and **no files are changed**. Validation runs over the
whole batch first and writes happen only once it is entirely clean, so partial
application is limited to a raw filesystem write error.

The line anchor narrows intent; the exact `old_string` proves the file still has
the content the caller expects. Because each edit is line-anchored, `old_string`
can be the small exact span to replace instead of a large surrounding block.
Each edit replaces the first matching span at or after its `start_line`,
stopping at `end_line` when supplied. Replacement spans within a file must not
overlap — so when several changes fall on the same line (or in one tight span),
the caller should combine them into a single edit whose `old_string` covers the
whole span rather than emitting one edit per change, which would collide and fail
the batch. To insert new code rather than replace, set `old_string` to the empty
string: `new_string` is inserted at the start of `start_line` (use `start_line` =
last line + 1 to append at end of file). Each written file also passes the same
MoonBit manifest guard used by the other write tools, so generated `.mbti` files
and known-bad manifest rewrites are rejected before anything is overwritten.

## API Style

Edits come from two independent, optional fields — `edits` (inline array) and
`edits_file` (a path) — and the tool **concatenates** whatever is provided
(inline first). No `oneOf`: each field is plainly typed, set either or both.

**Inline** — an array of edit objects:

```json
{
  "edits": [
    {
      "file": "lib/parser.mbt",
      "old_string": "parse_expr",
      "new_string": "parse_expression",
      "start_line": 20
    },
    {
      "file": "lib/eval.mbt",
      "old_string": "parse_expr",
      "new_string": "parse_expression",
      "start_line": 12
    }
  ]
}
```

**Response file** — a path to a JSON file containing that same array. This is the
automation path: generate the file from `moon check --output-json` diagnostics
with a script, then apply the whole batch in one validated call.

```json
{ "edits_file": "fixes.json" }
```

where `fixes.json` holds `[{ "file": ..., "old_string": ..., "new_string": ..., "start_line": ... }, ...]`.
Both may be set at once; the inline edits and the file's edits are applied
together.

## Arguments

At least one of `edits` / `edits_file` must yield a non-empty batch.

| Name | Type | Required | Notes |
| --- | --- | --- | --- |
| `edits` | array | no | Edit objects applied inline. Concatenated with `edits_file` when both are given. All edits for a given file must be contiguous in the combined batch. |
| `edits_file` | string | no | Path to a JSON file holding an array of the same edit objects (a response file). Concatenated with inline `edits`. |
| `edits[i].file` | string | yes | Filesystem path the edit applies to. Relative paths resolve against the agent process's current working directory. |
| `edits[i].old_string` | string | yes | Exact text to replace. Empty strings request an insertion. |
| `edits[i].new_string` | string | yes | Replacement text. It must differ from `old_string`. |
| `edits[i].start_line` | integer | yes | 1-based first line of this edit's search range. The first match at or after this line is replaced. |
| `edits[i].end_line` | integer | no | Optional 1-based last line of this edit's search range. Defaults to the file end. |

## Action

The action is always `Respond(ToolOutput(...))`. On success every file is written
once and the response lists the per-file counts:

- `"ok: applied <n> edit(s) across <m> file(s)\n<path>: <k> edit(s)"`

On failure, no files are written. Failed-edit reports name the file and the
original edit index:

- `"error multi_editing: <n> problem(s); no changes applied\n<file> edit[1] line range 10-12: old_string not found"`
- `"error multi_editing: edits for <file> must be contiguous; it reappears at edit[2] after another file's edits; list all edits for a file together"`
- `"error: multi_edit requires arguments.edits[0].start_line to be an integer"` — a present field has the wrong type.
- `"error: multi_edit requires arguments.edits[0] to include start_line (present keys: file, line, new_string, old_string)"` — a required field is absent; the present keys are listed so a misnamed key (here `line` instead of `start_line`) is obvious.

```moonbit check
///|
async test "multi_edit applies fixes through the registry" {
  @vfs.with_tmpdir(tmpdir => {
    let path = "\{tmpdir}/multi-edit-readme-example.mbt"
    @fs.write_file(
      path,
      "let a = old_a\nlet b = old_b\n",
      create_mode=CreateOrTruncate,
    )

    let tools = @agent_tool.Tools([@multi_edit.definition()])
    let arguments : Json = {
      "edits": [
        {
          "file": path,
          "old_string": "old_a",
          "new_string": "new_a",
          "start_line": 1,
        },
        {
          "file": path,
          "old_string": "old_b",
          "new_string": "new_b",
          "start_line": 2,
        },
      ],
    }

    let call = @agent_tool.AgentToolCall(
      ToolCall(
        id="call_multi_edit",
        name="multi_edit",
        arguments=arguments.stringify(),
      ),
    )
    let result = @agent_tool.execute_tool_call(call, tools)
    guard result is Respond(output) else { fail("expected Respond") }
    assert_eq(
      output.content,
      "ok: applied 2 edit(s) across 1 file(s)\n\{path}: 2 edit(s)",
    )
    assert_false(output.is_error)
    assert_eq(@fs.read_file(path).text(), "let a = new_a\nlet b = new_b\n")
  })
}
```
