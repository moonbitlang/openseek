# Read Tool

`read` returns text from a file at `arguments.path`. By default it returns whole
files when they fit within the output cap. For larger files, or when the agent
only needs a focused region, pass `start_line`, `max_lines`, or
`max_output_chars`.

When the agent needs several known independent files, prefer batching separate
single-file `read` tool calls in one assistant response. The tool accepts one
file per call so ranges, errors, and output budgets stay tied to a specific
file.

Do not use `read` for directories. Inspect directories with `ls` or `tree`, then
read specific files.

## Design Rationale

Every read has the **same shape** regardless of whether it is a whole-file read,
a line range, or a capped read: `<line-number>\t<content>` lines (the common
`cat -n` style used by other coding agents) followed by a single
`<system>...</system>` status footer. The optional range and output-cap
arguments exist for the failure mode seen in longer evaluations: large generated
files and dependency sources can flood the transcript and push useful context
out of the model window.

A uniform shape means the model never has to branch on "was this a full or a
partial read" — line numbers are always present (so it can cite `path:line`
afterward), and the footer always reports the range it saw (`start_line`,
`shown_lines`), the file's `total_lines` (so it can tell whether more lines
follow), and whether the budget cut the body (`truncated`). This matches the
lean, content-first convention used by Claude Code and the kimi agents, which
keep status metadata in a small footer rather than a verbose header.
Automatic output truncation is marked as a tool error even when the file was
read successfully; that makes lossy context visible to the loop instead of
silently pretending the returned prefix is complete.

For several known independent files, issue several independent `read` calls in
the same assistant response. That avoids extra model round trips while
preserving single-file ranges and independent output budgets.

## API Style

Use `path` alone when the file is known to be small or the full file is needed:

```json
{ "path": "agent/prompt.mbt" }
```

Use `start_line` and `max_lines` for generated files, logs, or dependency
source where the agent has already identified the relevant region:

```json
{ "path": "agent/prompt.mbt", "start_line": 40, "max_lines": 80 }
```

Use `max_output_chars` to protect the transcript when file size is uncertain.
The cap applies to the numbered body after line-number gutters are rendered (the
trailing footer is always appended). Prefer a range plus a cap over reading a
large file and relying on truncation.

## Arguments

| Name | Type | Required | Notes |
| ---- | ---- | -------- | ----- |
| `path` | string | yes | Filesystem path. Relative paths resolve against the agent process's current working directory. |
| `start_line` | number | no | 1-based first line to return. Defaults to `1`. |
| `max_lines` | number | no | Maximum number of lines to return. |
| `max_output_chars` | number | no | Maximum rendered content size to return, counted in UTF-16 code units (`String::length`) and including line-number gutters when present. Defaults to `12000` and is capped at `50000`. Truncation snaps down to a character boundary, so a surrogate pair is never split. |

## Action

The action is always `Respond(ToolOutput(...))` — the agent loop forwards
`ToolOutput.content` to the model as a tool-call response. `is_error` is
`false` on success and `true` for read failures, argument failures, or automatic
output truncation. The string body has one of these shapes:

- On success: `<line-number>\t<content>` lines, then a newline, then the footer
  `<system>start_line=<n> shown_lines=<k> total_lines=<t> truncated=<bool></system>`.
  When the selected body is empty (the range starts past EOF, or the budget is
  zero) only the footer is returned. `truncated=true` — set when
  `max_output_chars` cut the numbered body — is the one case that flips
  `is_error` to `true`.
- `"error reading <path>: <error>"` — a single-file read failed. Common
  causes: the file is missing, the agent doesn't have read permissions, or
  the bytes aren't valid UTF-8.
- `"error: read requires arguments.path"` — payload was an object but named no
  file.
- `"error: read requires object arguments"` — payload was not a JSON object.

## Example

```moonbit check
///|
test "read tool advertises the expected schema" {
  let tool = @read.definition()
  debug_inspect(
    tool,
    content=(
      #|{
      #|  name: "read",
      #|  description: "Read arguments.path as text. For several known independent files, batch separate read tool calls in one assistant response when possible. Do not use read for directories: inspect them with `ls` or `tree`, then read specific files. Supports optional start_line, max_lines, and max_output_chars for focused single-file reads. Output is `<line-number>\\t<content>` numbered lines followed by a `<system>` status footer.",
      #|  schema: JsonSchema(
      #|    Object(
      #|      {
      #|        "type": String("object"),
      #|        "required": Array([String("path")]),
      #|        "properties": Object(
      #|          {
      #|            "path": Object(
      #|              {
      #|                "type": String("string"),
      #|                "description": String("Text file path to read. Directories are not supported; use `ls` or `tree` first, then read specific files."),
      #|              },
      #|            ),
      #|            "start_line": Object({ "type": String("number") }),
      #|            "max_lines": Object({ "type": String("number") }),
      #|            "max_output_chars": Object({ "type": String("number") }),
      #|          },
      #|        ),
      #|      },
      #|    ),
      #|  ),
      #|  execute: ...,
      #|}
    ),
  )
}
```

```moonbit check
///|
async test "read tool reads a workspace note through the registry" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/task.txt"
    let content = "Task: summarize test failures\nStatus: investigating\n"
    @fs.write_file(path, content, create_mode=CreateOrTruncate)

    let tools = @agent_tool.Tools([@read.definition()])
    // Stringify a JSON object so a Windows temp path (`C:\Users\...`) survives
    // round-tripping instead of becoming an invalid `\U` escape.
    let arguments : Json = { "path": path }
    let call = @agent_tool.AgentToolCall(
      ToolCall(
        id="call_read_note",
        name="read",
        arguments=arguments.stringify(),
      ),
    )
    let result = @agent_tool.execute_tool_call(call, tools)
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    guard output.brief is Some("read task.txt") else {
      fail("unexpected brief")
    }
    // Numbered body (the trailing newline makes line 3 an empty line) then the
    // status footer.
    assert_eq(
      output.content,
      [
        "1\tTask: summarize test failures", "2\tStatus: investigating", "3\t", "<system>start_line=1 shown_lines=3 total_lines=3 truncated=false</system>",
      ].join("\n"),
    )
  })
}
```

```moonbit check
///|
async test "read tool supports focused range reads" {
  @vfs.with_tmpdir(prefix="openseek-read-readme-", dir => {
    let path = "\{dir}/range.txt"
    @fs.write_file(
      path,
      "alpha\nbeta\ngamma\ndelta",
      create_mode=CreateOrTruncate,
    )

    let tools = @agent_tool.Tools([@read.definition()])
    let arguments : Json = { "path": path, "start_line": 2, "max_lines": 2 }
    let call = @agent_tool.AgentToolCall(
      ToolCall(
        id="call_read_range",
        name="read",
        arguments=arguments.stringify(),
      ),
    )
    let result = @agent_tool.execute_tool_call(call, tools)
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(
      output.content,
      [
        "2\tbeta", "3\tgamma", "<system>start_line=2 shown_lines=2 total_lines=4 truncated=false</system>",
      ].join("\n"),
    )
  })
}
```
