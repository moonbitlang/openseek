# Write Tool

`write` creates or overwrites `arguments.path` with `arguments.content`.
Existing files are truncated and missing parent directories are created, so a
`write` to `dir/sub/moon.pkg` works without a separate `mkdir`. When the path
already exists the success message flags the overwrite, so the model can tell it
replaced content it may not have read — prefer `edit` for targeted changes, and
read an existing file before overwriting it.

## Design Rationale

`write` is intentionally a full-file operation. It is best for creating new
files, replacing generated artifacts, or rewriting a small file whose complete
contents are known. That makes the operation easy to explain in the transcript:
the model supplied the whole desired file body, and the host wrote exactly that
body.

Missing parent directories are created so a single `write` can lay down a file
in a fresh package directory without a separate `mkdir` step; the created path
stays inside the resolved workspace root.

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

New syncheck inputs (`.mbt`, `.mbt.md`, `moon.mod`, `moon.pkg`) get a pre-write
syntax gate: the content is parsed standalone (`moonc syncheck` in a scratch
file, no project context needed), and content with lex/parse errors is rejected
before anything — parent directories included — is created on disk. The call
fails with the errors and numbered excerpts synthesized from the rejected
content. A non-parsing file is never a valid intermediate state, and `write`
refuses to overwrite existing source, so the natural retry is another `write`
with corrected content. Three or more parse errors switch the retry hint to
writing a smaller skeleton first and growing it with `edit`. Type errors never
trigger the gate — they can be a legitimate transient state during multi-file
work; in `.mbt.md` only the checked (`mbt check` / `moonbit check`) fenced blocks
are parsed. `revert_on_parse_errors=false` opts out for deliberately non-parsing
fixtures.

## Arguments

| Name      | Type   | Required | Notes |
| --------- | ------ | -------- | ----- |
| `path`    | string | yes | Filesystem path. Relative paths resolve against the agent process's current working directory. |
| `content` | string | yes | Full file body. Empty strings are accepted and produce a zero-byte file. |
| `revert_on_parse_errors` | boolean | no (default `true`) | Reject new syncheck-input content (`.mbt`, `.mbt.md`, `moon.mod`, `moon.pkg`) that fails to lex/parse before anything is written, returning the errors with excerpts. In `.mbt.md` only the checked fenced blocks are parsed. Set `false` only to intentionally create a non-parsing file (e.g. a fixture). |

## Action

The action is always `Respond(ToolOutput(...))` — the agent loop forwards
`ToolOutput.content` to the model as a tool-call response. `is_error` is
`false` on success and `true` for write or argument failures. The string body
has one of these shapes:

- `"ok: wrote <n> line(s) (<m> chars) to <path>"` when a new file is created —
  `n` is the line count (matching what the read workflow reports for the same file: empty
  content is 0 lines, a trailing newline counts a final empty segment) and `m`
  the character count of the written content. When the path already existed the
  line ends with ` (overwrote existing file)` so the model can tell it clobbered
  prior content.
  If the target is `moon.mod`, `moon.pkg`, `.mbt`, or `.mbt.md` inside a
  MoonBit module, the response may append bounded raw compiler feedback from
  module-root `moon check --diagnostic-limit 1`, starting with
  `"moon check:"` after the success line. Failed checks include `exit=<code>`
  or `exit=cancelled`.
- `"rejected: the content for <path> has <n> parse error(s); nothing was written."`
  with `is_error=true` — the pre-write syntax gate refused the content; the body
  excerpts the rejected content at each error and says how to retry.
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
    @vfs.FileSystem({ "note.txt": "old note" }).write_to(dir)

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
    // The note already existed, so the result flags the overwrite.
    assert_eq(
      output.content,
      "ok: wrote 1 line (11 chars) to \{path} (overwrote existing file)",
    )
    assert_false(output.is_error)
    assert_eq(@fs.read_file(path).text(), "tests green")
  })
}
```
