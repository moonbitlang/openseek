# Write Tool

`write` overwrites `arguments.path` with `arguments.content`. Existing files
are truncated; missing parent directories are **not** created — the agent
should `shell` a `mkdir -p` first when it needs nested directories.

## Design Rationale

`write` is intentionally a full-file operation. It is best for creating new
files, replacing generated artifacts, or rewriting a small file whose complete
contents are known. That makes the operation easy to explain in the transcript:
the model supplied the whole desired file body, and the host wrote exactly that
body.

Parent directories are not created implicitly because directory creation is a
separate workspace mutation. Keeping it explicit makes broad filesystem changes
visible in the log and lets the agent choose whether to create a directory,
reuse an existing package, or fix an incorrect path.

## API Style

Pass the complete target content. Empty content is allowed and deliberately
creates a zero-byte file:

```json
{
  "path": "notes/result.txt",
  "content": "tests green\n"
}
```

Prefer `edit` when changing a small region in an existing user-authored file.
Prefer `write` when the file is new, generated, or easier to reason about as a
complete replacement.

MoonBit manifests get a small extra guardrail because bad manifests poison every
later compiler diagnostic. New projects should write `moon.mod`, not legacy
`moon.mod.json`; `moon.mod` rewrites that look empty or JSON-style are rejected,
as are `moon.pkg` rewrites that use JSON-style syntax or `#` comments. Generated
`*.generated.mbti` interface files are rejected too; refresh them with `moon info`
instead.

## Arguments

| Name      | Type   | Required | Notes |
| --------- | ------ | -------- | ----- |
| `path`    | string | yes | Filesystem path. Relative paths resolve against the agent process's current working directory. |
| `content` | string | yes | Full file body. Empty strings are accepted and produce a zero-byte file. |

## Action

The action is always `Respond(ToolOutput(...))` — the agent loop forwards
`ToolOutput.content` to the model as a tool-call response. `is_error` is
`false` on success and `true` for write or argument failures. The string body
has one of these shapes:

- `"ok: wrote <n> chars to <path>"` on success — `n` is the character count
  of the written content.
  If the target is `moon.mod`, `moon.pkg`, `.mbt`, or `.mbt.md` inside a
  MoonBit module, the response may append bounded raw compiler feedback from
  module-root `moon check --diagnostic-limit 1`, starting with
  `"moon check:"` after the success line. Failed checks include `exit=<code>`
  or `exit=cancelled`.
- `"error writing <path>: <error>"` — the write failed. Common causes:
  permission denied, missing parent directory, read-only filesystem.
- `"error writing <path>: moon.mod.json is legacy; create moon.mod ..."` or
  similar manifest-guard messages — the requested manifest rewrite looked like a
  likely agent mistake.
- `"error: write requires arguments.content"` — payload had `path` but no
  `content` (or `content` was not a string).
- `"error: write requires arguments.path"` — payload was an object missing
  `path`.
- `"error: write requires object arguments"` — payload was not a JSON object.

## Example

```moonbit check
///|
test "write tool advertises the expected schema" {
  let tool = @write.definition()
  assert_eq(tool.name, "write")
  let JsonSchema(schema) = tool.schema
  let text = schema.stringify()
  assert_true(text.contains("\"path\""))
  assert_true(text.contains("\"content\""))
  assert_true(text.contains("\"required\""))
}
```

```moonbit check
///|
async test "write tool updates an implementation note through the registry" {
  @vfs.with_tmpdir(prefix="openseek-write-readme-", dir => {
    let path = "\{dir}/note.txt"
    @fs.write_file(path, "old note", create_mode=CreateOrTruncate)

    let tools = @agent_tool.Tools([@write.definition()])
    // Build the arguments as JSON and stringify them, rather than embedding the
    // path in a JSON string literal: a Windows temp path like `C:\Users\...`
    // would otherwise become an invalid `\U` escape when parsed.
    let arguments : Json = { "path": path, "content": "tests green" }
    let call = @agent_tool.AgentToolCall(
      ToolCall(
        id="call_write_note",
        name="write",
        arguments=arguments.stringify(),
      ),
    )
    let result = @agent_tool.execute_tool_call(call, tools)
    guard result is Respond(output) else { fail("expected Respond") }
    assert_eq(output.content, "ok: wrote 11 chars to \{path}")
    assert_false(output.is_error)
    assert_eq(@fs.read_file(path).text(), "tests green")
  })
}
```
