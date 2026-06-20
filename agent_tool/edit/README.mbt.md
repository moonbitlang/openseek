# Edit Tool

`edit` replaces exact text in `arguments.path`. It is intended for targeted
code changes where overwriting the whole file would be unnecessarily broad.

## Design Rationale

`edit` uses exact `old_string` replacement instead of a patch language because
the host can validate the change with simple, deterministic rules. The default
single-match requirement prevents ambiguous edits in files that contain repeated
snippets. `replace_all=true` is explicit so broad changes show up in the tool
call rather than being an accidental consequence of a loose match. When a
single-match edit is ambiguous, the error reports the first matching line
numbers so the caller can add enough surrounding context to make `old_string`
unique.

Rejecting empty `old_string` and identical replacements protects against
no-op or explosive edits. The tool is designed for small surgical changes; if a
file needs a complete rewrite, `write` is the clearer API.

MoonBit manifests get the same safety check as `write`: edits that would create
legacy `moon.mod.json`, JSON-style `moon.mod` or `moon.pkg`, or `moon.pkg` with
`#` comments are rejected before the original file is overwritten.

## API Style

Use a context-rich exact string that should occur once:

```json
{
  "path": "agent/prompt.mbt",
  "old_string": "Use moon check before moon test.",
  "new_string": "Use moon check before moon test, and inspect failures before editing."
}
```

Set `replace_all=true` only after deciding every occurrence is intentionally
part of the same change:

```json
{
  "path": "agent/prompt.mbt",
  "old_string": "moon.mod.json",
  "new_string": "moon.mod",
  "replace_all": true
}
```

## Arguments

| Name          | Type    | Required | Notes |
| ------------- | ------- | -------- | ----- |
| `path`        | string  | yes | Filesystem path. Relative paths resolve against the agent process's current working directory. |
| `old_string`  | string  | yes | Exact text to replace. Empty strings are rejected. |
| `new_string`  | string  | yes | Replacement text. It must differ from `old_string`. |
| `replace_all` | boolean | no  | Defaults to `false`. When false, `old_string` must occur exactly once. |

## Action

The action is always `Respond(ToolOutput(...))` — the agent loop forwards
`ToolOutput.content` to the model as a tool-call response. `is_error` is
`false` on success and `true` for edit or argument failures. The string body
has one of these shapes:

- `"ok: replaced <n> occurrence(s) in <path>"` on success.
  If the target is `moon.mod`, `moon.pkg`, `.mbt`, or `.mbt.md` inside a
  MoonBit module, the response may append bounded raw compiler feedback from
  module-root `moon check --diagnostic-limit 1`, starting with
  `"moon check:\nexit=<code>"` after the success line.
- `"error editing <path>: old_string not found"` — no exact match was found.
- `"error editing <path>: old_string matched <n> times on lines <line>, ...; set replace_all=true to replace all occurrences"` — the edit was ambiguous.
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
  assert_true(text.contains("\"replace_all\""))
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
    assert_eq(output.content, "ok: replaced 1 occurrence(s) in \{path}")
    assert_false(output.is_error)
    assert_eq(
      @fs.read_file(path).text(),
      "fn greet() -> String {\n  \"hello, MoonBit\"\n}\n",
    )
  })
}
```
