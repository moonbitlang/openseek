///|
/// Tool definition for `read`: returns text from `arguments.path` (or several
/// files via `arguments.paths`), optionally restricted to a line range and
/// capped to avoid flooding the agent context.
///
/// ## Arguments
/// - `path` (string): filesystem path to read. Exactly one of `path`/`paths`
///   is required.
/// - `paths` (string array): several files in one call; per-file read errors
///   report inline while the other files still return.
/// - `start_line` (number, optional): 1-based first line to return. Defaults
///   to 1. Single-file calls only.
/// - `max_lines` (number, optional): maximum number of lines to return.
///   Single-file calls only.
/// - `max_output_chars` (number, optional): maximum returned content chars
///   for the whole call. Defaults to 12000 and is capped at 50000.
///
/// ## Result
/// - `Respond(ToolOutput(<file contents>))` on success for uncapped whole-file
///   single reads.
/// - `Respond(ToolOutput(<metadata header + content>))` for ranged reads or
///   capped reads, and per file for multi-file reads (blocks separated by a
///   blank line; a failed file contributes an inline `error reading ...`
///   block and only flips `is_error` when every file failed).
/// - `Respond(ToolOutput("error reading <path>: <error>", is_error=true))`
///   if a single-file read fails (missing file, permission denied, invalid
///   UTF-8, etc.).
/// - `Respond(ToolOutput("error: read requires ...", is_error=true))` for
///   invalid arguments.
pub fn definition() -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="read",
    description="Read arguments.path as text — or several independent files in ONE call via arguments.paths (per-file errors report inline; cheaper than one call per file). Supports optional start_line, max_lines, and max_output_chars for focused single-file reads.",
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "path": { "type": "string" },
        "paths": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Read several files in one call instead of one call per file. Exactly one of path/paths is required.",
        },
        "start_line": { "type": "number" },
        "max_lines": { "type": "number" },
        "max_output_chars": { "type": "number" },
      },
    }),
    execute=Async(execute),
  )
}

///|
async fn execute(arguments : Json) -> @agent_tool.ToolAction {
  let input = @decode.decode(arguments) catch {
    error => {
      let message = @tool_error.failure_message("\{error}")
      return @agent_tool.ToolAction::respond(
        "error: read requires \{message}",
        is_error=true,
      )
    }
  }
  if input.paths.length() == 1 {
    read_file(input)
  } else {
    read_files(input)
  }
}

///|
priv struct ReadSelection {
  content : String
  start_line : Int
  end_line : Int
  total_lines : Int
  shown_lines : Int
  line_limited : Bool
}

///|
async fn read_file(input : @decode.ReadInput) -> @agent_tool.ToolAction {
  let path = input.paths[0]
  let content = @fs.read_file(path).text() catch {
    error =>
      return @agent_tool.ToolAction::respond(
        "error reading \{path}: \{error}",
        is_error=true,
      )
  }
  let selection = select_lines(content, input.start_line, input.max_lines)
  let capped = cap_text(selection.content, input.max_output_chars)
  let char_truncated = selection.content.length() > input.max_output_chars
  let include_header = input.start_line != 1 ||
    input.max_lines is Some(_) ||
    char_truncated
  let output = if include_header {
    read_header(path, content, selection, capped, char_truncated) + capped
  } else {
    capped
  }
  @agent_tool.ToolAction::respond(output, is_error=char_truncated)
}

///|
/// Render a multi-file read: one headered block per file, separated by blank
/// lines, sharing the call's `max_output_chars` budget in argument order. A
/// file that fails to read contributes an inline error block — the other
/// files still return, mirroring how `moon ide doc` reports per-query misses
/// — and `is_error` only flips when every file failed or the budget cut
/// content (so the model knows to re-read the tail individually).
///
/// Every emitted block — header, error text, separators — counts against the
/// budget, not just file content: otherwise a long paths list of headers or
/// missing-file errors would outgrow the cap that exists to protect the
/// context (Codex review). Once the budget is exhausted the unread tail
/// collapses into a single skipped-files marker, so output stays bounded no
/// matter how many paths the call names.
async fn read_files(input : @decode.ReadInput) -> @agent_tool.ToolAction {
  let blocks : Array[String] = []
  let mut remaining = input.max_output_chars
  let mut failures = 0
  let mut truncated_any = false
  let skipped : Array[String] = []
  for path in input.paths {
    if remaining <= 0 {
      skipped.push(path)
      continue
    }
    let content = @fs.read_file(path).text() catch {
      error => {
        failures = failures + 1
        let block = "error reading \{path}: \{error}"
        remaining = remaining - block.length() - 2
        blocks.push(block)
        continue
      }
    }
    let selection = select_lines(content, 1, None)
    let capped = cap_text(selection.content, remaining)
    let char_truncated = selection.content.length() > remaining
    if char_truncated {
      truncated_any = true
    }
    let block = read_header(path, content, selection, capped, char_truncated) +
      capped
    remaining = remaining - block.length() - 2
    blocks.push(block)
  }
  if skipped.length() > 0 {
    truncated_any = true
    // Preview only a handful of names: the marker itself must stay bounded
    // or a thousand-path call would flood the context through its skip list.
    let preview_count = if skipped.length() < 5 { skipped.length() } else { 5 }
    let preview = skipped[0:preview_count].join(", ")
    let rest = if skipped.length() > 5 {
      " and \{skipped.length() - 5} more"
    } else {
      ""
    }
    blocks.push(
      "skipped \{skipped.length()} file(s), max_output_chars budget exhausted — read them individually: \{preview}\{rest}",
    )
  }
  @agent_tool.ToolAction::respond(
    blocks.join("\n\n"),
    is_error=failures == input.paths.length() || truncated_any,
  )
}

///|
fn select_lines(
  content : String,
  start_line : Int,
  max_lines : Int?,
) -> ReadSelection {
  let lines = [ for line in content.split("\n") => line.to_owned() ]
  let total_lines = lines.length()
  // Clamp both bounds into [0, total_lines] so the slice below is always
  // ascending and in range — a start past the last line selects nothing.
  let start_index = (start_line - 1).clamp(min=0, max=total_lines)
  let end_exclusive = match max_lines {
    // Clamp the count BEFORE adding: a huge max_lines (e.g. Int max) must
    // not overflow past start_index (Codex review). Such a request now
    // returns the remaining lines, where the old post-add clamp overflowed
    // negative and accidentally selected nothing.
    Some(count) =>
      start_index + count.clamp(min=0, max=total_lines - start_index)
    None => total_lines
  }
  let selected = lines[start_index:end_exclusive].to_owned()
  let shown_lines = selected.length()
  let end_line = if shown_lines == 0 {
    start_line - 1
  } else {
    start_line + shown_lines - 1
  }
  let line_limited = match max_lines {
    Some(_) => end_exclusive < total_lines
    None => false
  }
  {
    content: selected.join("\n"),
    start_line,
    end_line,
    total_lines,
    shown_lines,
    line_limited,
  }
}

///|
fn cap_text(content : String, max_chars : Int) -> String {
  if content.length() <= max_chars {
    content
  } else {
    content[:max_chars].to_owned()
  }
}

///|
fn read_header(
  path : String,
  original : String,
  selection : ReadSelection,
  capped : String,
  char_truncated : Bool,
) -> String {
  [
    "path=\{path}",
    "start_line=\{selection.start_line}",
    "end_line=\{selection.end_line}",
    "total_lines=\{selection.total_lines}",
    "shown_lines=\{selection.shown_lines}",
    "file_chars=\{original.length()}",
    "selected_chars=\{selection.content.length()}",
    "shown_chars=\{capped.length()}",
    "line_limited=\{selection.line_limited}",
    "truncated=\{char_truncated}",
    "---",
    "",
  ].join("\n")
}

///|
async test "read returns file contents" {
  let path = "/tmp/openseek-read-test.txt"
  @fs.write_file(path, "hello read", create_mode=CreateOrTruncate)
  let result = execute({ "path": path })
  guard result is Respond(output) else { fail("expected Respond") }
  assert_eq(output.content, "hello read")
  assert_false(output.is_error)
}

///|
async test "read returns empty string for an empty file" {
  let path = "/tmp/openseek-read-empty.txt"
  @fs.write_file(path, "", create_mode=CreateOrTruncate)
  let result = execute({ "path": path })
  guard result is Respond(output) else { fail("expected Respond") }
  assert_eq(output.content, "")
  assert_false(output.is_error)
}

///|
async test "read preserves multiline content" {
  let path = "/tmp/openseek-read-multiline.txt"
  let content = "line one\nline two\nline three\n"
  @fs.write_file(path, content, create_mode=CreateOrTruncate)
  let result = execute({ "path": path })
  guard result is Respond(output) else { fail("expected Respond") }
  assert_eq(output.content, content)
  assert_false(output.is_error)
}

///|
async test "read returns a requested line range with metadata" {
  let path = "/tmp/openseek-read-range.txt"
  let content = "line one\nline two\nline three\nline four"
  @fs.write_file(path, content, create_mode=CreateOrTruncate)
  let result = execute({ "path": path, "start_line": 2, "max_lines": 2 })
  guard result is Respond(output) else { fail("expected Respond") }
  assert_false(output.is_error)
  inspect(
    output.content,
    content=(
      #|path=/tmp/openseek-read-range.txt
      #|start_line=2
      #|end_line=3
      #|total_lines=4
      #|shown_lines=2
      #|file_chars=38
      #|selected_chars=19
      #|shown_chars=19
      #|line_limited=true
      #|truncated=false
      #|---
      #|line two
      #|line three
    ),
  )
}

///|
async test "read caps oversized output and marks it as an error" {
  let path = "/tmp/openseek-read-capped.txt"
  @fs.write_file(path, "abcdef", create_mode=CreateOrTruncate)
  let result = execute({ "path": path, "max_output_chars": 3 })
  guard result is Respond(output) else { fail("expected Respond") }
  assert_true(output.is_error)
  inspect(
    output.content,
    content=(
      #|path=/tmp/openseek-read-capped.txt
      #|start_line=1
      #|end_line=1
      #|total_lines=1
      #|shown_lines=1
      #|file_chars=6
      #|selected_chars=6
      #|shown_chars=3
      #|line_limited=false
      #|truncated=true
      #|---
      #|abc
    ),
  )
}

///|
test "read parses and caps optional limits" {
  let input = @decode.decode({
    "path": "file.mbt",
    "start_line": 3,
    "max_lines": 4,
    "max_output_chars": 999999,
  })
  assert_eq(input.paths.length(), 1)
  assert_eq(input.paths[0], "file.mbt")
  assert_eq(input.start_line, 3)
  guard input.max_lines is Some(max_lines) else { fail("missing max_lines") }
  assert_eq(max_lines, 4)
  assert_eq(input.max_output_chars, @decode.hard_max_output_chars)
}

///|
async test "read returns several files as headered blocks" {
  let a = "/tmp/openseek-read-multi-a.txt"
  let b = "/tmp/openseek-read-multi-b.txt"
  @fs.write_file(a, "alpha", create_mode=CreateOrTruncate)
  @fs.write_file(b, "beta", create_mode=CreateOrTruncate)
  let result = execute({ "paths": [a, b] })
  guard result is Respond(output) else { fail("expected Respond") }
  assert_false(output.is_error)
  assert_true(output.content.contains("path=\{a}"))
  assert_true(output.content.contains("alpha"))
  assert_true(output.content.contains("path=\{b}"))
  assert_true(output.content.contains("beta"))
}

///|
async test "a missing file reports inline while the others return" {
  let a = "/tmp/openseek-read-multi-ok.txt"
  @fs.write_file(a, "still here", create_mode=CreateOrTruncate)
  let result = execute({ "paths": [a, "/tmp/openseek-read-multi-missing.txt"] })
  guard result is Respond(output) else { fail("expected Respond") }
  // Partial failure is not a tool error: the good file landed and the bad
  // path's error block tells the model exactly which read to fix.
  assert_false(output.is_error)
  assert_true(output.content.contains("still here"))
  assert_true(
    output.content.contains(
      "error reading /tmp/openseek-read-multi-missing.txt",
    ),
  )
}

///|
async test "every file missing is a tool error" {
  let result = execute({
    "paths": ["/tmp/openseek-read-none-1", "/tmp/openseek-read-none-2"],
  })
  guard result is Respond(output) else { fail("expected Respond") }
  assert_true(output.is_error)
}

///|
async test "the output budget is shared and exhaustion is reported" {
  let a = "/tmp/openseek-read-budget-a.txt"
  let b = "/tmp/openseek-read-budget-b.txt"
  @fs.write_file(a, "0123456789", create_mode=CreateOrTruncate)
  @fs.write_file(b, "abcdefghij", create_mode=CreateOrTruncate)
  let result = execute({ "paths": [a, b], "max_output_chars": 10 })
  guard result is Respond(output) else { fail("expected Respond") }
  assert_true(output.is_error)
  assert_true(output.content.contains("0123456789"))
  assert_true(output.content.contains("skipped 1 file(s)"))
  assert_true(output.content.contains(b))
  assert_false(output.content.contains("abcdefghij"))
}

///|
async test "headers and error blocks count against the budget" {
  // 40 missing paths with a small budget: error blocks consume the budget,
  // the tail collapses into one bounded marker, and the total output stays
  // near the cap instead of growing per path (Codex review).
  let paths : Array[Json] = []
  for i in 0..<40 {
    paths.push(Json::string("/tmp/openseek-read-flood-\{i}"))
  }
  let result = execute({ "paths": Json::array(paths), "max_output_chars": 300 })
  guard result is Respond(output) else { fail("expected Respond") }
  assert_true(output.is_error)
  assert_true(output.content.contains("skipped"))
  assert_true(output.content.contains("and"))
  // Bounded: the budget plus one overshooting block plus the skip marker,
  // far below what 40 unbudgeted error blocks (~70 chars each) would emit.
  assert_true(output.content.length() < 1200)
}

///|
async test "read rejects path and paths together" {
  let result = execute({ "path": "/tmp/x", "paths": ["/tmp/y"] })
  guard result is Respond(output) else { fail("expected Respond") }
  assert_true(output.is_error)
  assert_true(output.content.contains("not both"))
}

///|
async test "read rejects line ranges on multi-file calls" {
  let result = execute({ "paths": ["/tmp/x", "/tmp/y"], "start_line": 2 })
  guard result is Respond(output) else { fail("expected Respond") }
  assert_true(output.is_error)
  assert_true(output.content.contains("single file"))
}

///|
async test "read rejects an empty paths array" {
  let result = execute({ "paths": [] })
  guard result is Respond(output) else { fail("expected Respond") }
  assert_true(output.is_error)
  assert_true(output.content.contains("non-empty array"))
}

///|
async test "read surfaces filesystem errors" {
  let result = execute({ "path": "/tmp/openseek-does-not-exist" })
  guard result is Respond(output) else { fail("expected Respond") }
  assert_true(output.content.contains("error reading"))
  assert_true(output.is_error)
}

///|
async test "read rejects missing path" {
  let result = execute({})
  guard result is Respond(output) else { fail("expected Respond") }
  assert_true(output.content.contains("error: read requires"))
  assert_true(output.content.contains("arguments.path"))
  assert_true(output.is_error)
}

///|
async test "read rejects invalid limits" {
  let result = execute({ "path": "/tmp/openseek-read-test.txt", "max_lines": 0 })
  guard result is Respond(output) else { fail("expected Respond") }
  assert_true(output.content.contains("error: read requires"))
  assert_true(
    output.content.contains("arguments.max_lines to be a positive number"),
  )
  assert_true(output.is_error)
}

///|
async test "read rejects non-object arguments" {
  let result = execute(Json::null())
  guard result is Respond(output) else { fail("expected Respond") }
  assert_eq(output.content, "error: read requires object arguments")
  assert_true(output.is_error)
}

///|
async test "a huge max_lines returns the remaining lines without overflow" {
  let path = "/tmp/openseek-read-huge-max.txt"
  @fs.write_file(path, "a\nb\nc", create_mode=CreateOrTruncate)
  let result = execute({
    "path": path,
    "start_line": 2,
    "max_lines": 2147483647,
  })
  guard result is Respond(output) else { fail("expected Respond") }
  assert_false(output.is_error)
  assert_true(output.content.contains("b\nc"))
  assert_true(output.content.contains("shown_lines=2"))
}
