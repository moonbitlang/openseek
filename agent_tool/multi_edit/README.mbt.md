# Multi Edit Tool

`multi_edit` applies several exact line-anchored replacements to one file. It is
intended for efficient compiler-feedback repair loops: when `moon check` points
at several known locations in the same file, the caller can fix them in one
validated tool call instead of issuing many separate `edit` calls.

## Design Rationale

Every edit carries its own `old_string`, `new_string`, and required
`start_line`; optional `end_line` bounds the search when useful. The tool
validates each replacement against the original file before writing anything.
If any edit fails, the response reports every failed edit index and no changes
are applied. This avoids half-mutated files while still making compiler-feedback
repair efficient.

The line anchor narrows intent; the exact `old_string` proves the file still has
the content the caller expects. Because each edit is line-anchored,
`old_string` can be the small exact span to replace instead of a large
surrounding block. Each edit replaces the first matching span at or after its
`start_line`, stopping at `end_line` when supplied. Replacement spans must not
overlap. The final file also passes the same MoonBit manifest guard used by the
other write tools, so generated `.mbti` files and known-bad manifest rewrites
are rejected before the original file is overwritten.

## API Style

```json
{
  "path": "lib/parser.mbt",
  "edits": [
    {
      "old_string": "parse_expr",
      "new_string": "parse_expression",
      "start_line": 20
    },
    {
      "old_string": "Expr::Old",
      "new_string": "Expr::New",
      "start_line": 68,
      "end_line": 70
    }
  ]
}
```

## Arguments

| Name | Type | Required | Notes |
| --- | --- | --- | --- |
| `path` | string | yes | Filesystem path. Relative paths resolve against the agent process's current working directory. |
| `edits` | array | yes | Non-empty list of explicit replacements. |
| `edits[i].old_string` | string | yes | Exact text to replace. Empty strings are rejected. |
| `edits[i].new_string` | string | yes | Replacement text. It must differ from `old_string`. |
| `edits[i].start_line` | integer | yes | 1-based first line of this edit's search range. The first match at or after this line is replaced. |
| `edits[i].end_line` | integer | no | Optional 1-based last line of this edit's search range. Defaults to the file end. |

## Action

The action is always `Respond(ToolOutput(...))`. On success the file is written
once and the response is:

- `"ok: applied <n> edit(s) in <path>"`

On failure, no changes are written. Failed edit reports use the original edit
indexes:

- `"error multi_editing <path>: <n> edit(s) failed; no changes applied\nedit[1] line range 10-12: old_string not found"`
- `"error: multi_edit requires arguments.edits[0].start_line to be an integer"`

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
      "path": path,
      "edits": [
        { "old_string": "old_a", "new_string": "new_a", "start_line": 1 },
        { "old_string": "old_b", "new_string": "new_b", "start_line": 2 },
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
    assert_eq(output.content, "ok: applied 2 edit(s) in \{path}")
    assert_false(output.is_error)
    assert_eq(@fs.read_file(path).text(), "let a = new_a\nlet b = new_b\n")
  })
}
```
