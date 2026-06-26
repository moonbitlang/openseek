# Edit Tool

`edit` replaces exact text in `arguments.path`. It is intended for targeted
code changes where overwriting the whole file would be unnecessarily broad.

## Design Rationale

`edit` uses exact `old_string` replacement instead of a patch language because
the host can validate the change with simple, deterministic rules. `start_line`
anchors the edit near the caller's intended location, then the first matching
`old_string` at or after that line is replaced. Optional `end_line` narrows the
search when the caller wants a tighter inclusive 1-based line range. Because
the line anchor carries the location, `old_string` can be the small exact span
to replace instead of a large surrounding block.

Rejecting empty `old_string` and identical replacements protects against
no-op or explosive edits. The tool is designed for small surgical changes; if a
file needs a complete rewrite, `write` is the clearer API.

MoonBit manifests get the same safety check as `write`: edits that would create
legacy `moon.mod.json`, JSON-style `moon.mod` or `moon.pkg`, or `moon.pkg` with
`#` comments are rejected before the original file is overwritten.

## API Style

Use a focused exact string near the starting line:

```json
{
  "path": "agent/prompt.mbt",
  "old_string": "Use moon check before moon test.",
  "new_string": "Use moon check before moon test, and inspect failures before editing.",
  "start_line": 42
}
```

Use `end_line` when the same text appears shortly after the intended location
and the edit should stay inside a tighter range:

```json
{
  "path": "agent/prompt.mbt",
  "old_string": "moon check",
  "new_string": "moon check --diagnostic-limit 1",
  "start_line": 120,
  "end_line": 140
}
```

## Arguments

| Name          | Type    | Required | Notes |
| ------------- | ------- | -------- | ----- |
| `path`        | string  | yes | Filesystem path. Relative paths resolve against the agent process's current working directory. |
| `old_string`  | string  | yes | Exact text to replace. Empty strings are rejected. |
| `new_string`  | string  | yes | Replacement text. It must differ from `old_string`. |
| `start_line`  | integer | yes | 1-based first line of the search/replace range. The first match at or after this line is replaced. |
| `end_line`    | integer | no  | 1-based last line of the search/replace range. Defaults to the file end. |

Legacy calls with `replace_all=false` are tolerated, but `replace_all=true` is
rejected. Use `multi_edit` when a compiler diagnostic suggests several known
locations in one file should be fixed efficiently.

## Action

The action is always `Respond(ToolOutput(...))` — the agent loop forwards
`ToolOutput.content` to the model as a tool-call response. `is_error` is
`false` on success and `true` for edit or argument failures. The string body
has one of these shapes:

- `"ok: replaced <n> occurrence(s) at line <line> in <path>"` on success.
  If the target is `moon.mod`, `moon.pkg`, `.mbt`, or `.mbt.md` inside a
  MoonBit module, the response may append bounded raw compiler feedback from
  module-root `moon check --diagnostic-limit 1`, starting with
  `"moon check:"` after the success line. Failed checks include `exit=<code>`
  or `exit=cancelled`.
- `"error editing <path>: old_string not found"` — no exact match was found in the selected range.
- `"error editing <path>: replace_all=true is no longer supported; use multi_edit with explicit line-anchored edits"` — the call requested a global replacement.
- `"error editing <path>: moon.pkg use // for comment syntax, not #"` or similar
  manifest-guard messages — the replacement would likely break MoonBit package
  discovery.
- `"error editing <path>: <error>"` — reading or writing failed.
- `"error: edit requires arguments.<field>"` — payload was an object but missed a required field.
- `"error: edit requires object arguments"` — payload was not a JSON object.

## Example

```moonbit check
///|
test "edit tool advertises the expected schema" {
  let tool = @edit.definition()
  assert_eq(tool.name, "edit")
  let JsonSchema(schema) = tool.schema
  let text = schema.stringify()
  assert_true(text.contains("\"path\""))
  assert_true(text.contains("\"old_string\""))
  assert_true(text.contains("\"new_string\""))
  assert_false(text.contains("\"replace_all\""))
  assert_true(text.contains("\"start_line\""))
  assert_true(text.contains("\"end_line\""))
  assert_true(text.contains("\"required\""))
}
```

```moonbit check
///|
async test "edit tool applies a focused code change through the registry" {
  @vfs.with_tmpdir(tmpdir => {
    let path = "\{tmpdir}/openseek-edit-readme-example.mbt"
    @fs.write_file(
      path,
      "fn greet() -> String {\n  \"hello\"\n}\n",
      create_mode=CreateOrTruncate,
    )

    let tools = @agent_tool.Tools([@edit.definition()])
    let arguments : Json = {
      "path": "\{tmpdir}/openseek-edit-readme-example.mbt",
      "old_string": "  \"hello\"",
      "new_string": "  \"hello, MoonBit\"",
      "start_line": 2,
    }

    let call = @agent_tool.AgentToolCall(
      ToolCall(
        id="call_edit_greeting",
        name="edit",
        arguments=arguments.stringify(),
      ),
    )
    let result = @agent_tool.execute_tool_call(call, tools)
    guard result is Respond(output) else { fail("expected Respond") }
    assert_eq(
      output.content,
      "ok: replaced 1 occurrence(s) at line 2 in \{path}",
    )
    assert_false(output.is_error)
    assert_eq(
      @fs.read_file(path).text(),
      "fn greet() -> String {\n  \"hello, MoonBit\"\n}\n",
    )
  })
}
```
