///|
/// Tool definition for `read`: returns text from `arguments.path`, optionally
/// restricted to a line range and capped to avoid flooding the agent context.
/// When several known independent files are needed, prefer batching several
/// single-file `read` tool calls in one assistant response.
///
/// ## Arguments
/// - `path` (string): filesystem path to read. Required. Directories are not
///   supported; use `ls` or `tree` first, then read specific files.
/// - `start_line` (number, optional): 1-based first line to return. Defaults
///   to 1. Single-file calls only.
/// - `max_lines` (number, optional): maximum number of lines to return.
///   Single-file calls only.
/// - `max_output_chars` (number, optional): maximum rendered content size for
///   the whole call, counted in UTF-16 code units (`String::length`, an O(1)
///   soft budget) and including line-number gutters when present. Defaults to
///   12000 and is capped at 50000. Truncation never splits a surrogate pair.
///
/// ## Result
/// - `Respond(ToolOutput(<numbered lines> + "\n" + <footer>))` on success.
///   Every read has the same shape regardless of range or cap: `<line-number>\t
///   <content>` lines followed by a single
///   `<system>start_line=.. shown_lines=.. total_lines=.. truncated=..</system>`
///   footer (footer only when the body is empty). `is_error` is `true` only when
///   the `max_output_chars` budget cut the body (`truncated=true`).
/// - `Respond(ToolOutput("error reading <path>: <error>", is_error=true))`
///   if a single-file read fails (missing file, permission denied, invalid
///   UTF-8, directory path, etc.).
/// - `Respond(ToolOutput("error: read requires ...", is_error=true))` for
///   invalid arguments.
pub fn definition(
  workspace_root? : String = ".",
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="read",
    description="Read arguments.path as text. For several known independent files, batch separate read tool calls in one assistant response when possible. Do not use read for directories: inspect them with `ls` or `tree`, then read specific files. Supports optional start_line, max_lines, and max_output_chars for focused single-file reads. Output is `<line-number>\\t<content>` numbered lines followed by a `<system>` status footer.",
    schema=JsonSchema({
      "type": "object",
      "required": ["path"],
      "properties": {
        "path": {
          "type": "string",
          "description": "Text file path to read. Directories are not supported; use `ls` or `tree` first, then read specific files.",
        },
        "start_line": { "type": "number" },
        "max_lines": { "type": "number" },
        "max_output_chars": { "type": "number" },
      },
    }),
    execute=Async(arguments => execute_with_workspace(workspace_root, arguments)),
  )
}

///|
async fn execute(arguments : Json) -> @agent_tool.ToolAction {
  execute_with_workspace(".", arguments)
}

///|
async fn execute_with_workspace(
  workspace_root : String,
  arguments : Json,
) -> @agent_tool.ToolAction {
  let input = @decode.decode(arguments) catch {
    error => {
      let message = @tool_error.failure_message("\{error}")
      return @agent_tool.ToolAction::respond(
        "error: read requires \{message}",
        is_error=true,
      )
    }
  }
  read_file(input, path=@workspace_path.resolve(workspace_root, input.path))
}

///|
priv struct ReadSelection {
  content : String
  start_line : Int
  total_lines : Int
  shown_lines : Int
}

///|
priv struct RenderedSelection {
  content : String
  shown_lines : Int
  truncated : Bool
}

///|
async fn read_file(
  input : @decode.ReadInput,
  path~ : String,
) -> @agent_tool.ToolAction {
  let brief = "read \{@agent_tool.brief_basename(path)}"
  match directory_read_error(path) {
    Some(message) =>
      return @agent_tool.ToolAction::respond(message, is_error=true, brief~)
    None => ()
  }
  let content = @fs.read_file(path).text() catch {
    error =>
      return @agent_tool.ToolAction::respond(
        "error reading \{path}: \{error}",
        is_error=true,
        brief~,
      )
  }
  let selection = select_lines(content, input.start_line, input.max_lines)
  let rendered = render_numbered_content(selection, input.max_output_chars)
  // Every read has the same shape: numbered lines followed by a single status
  // footer. When the body is empty (start past EOF, or a zero budget) only the
  // footer is returned, so the model still learns what it asked for.
  let footer = read_footer(selection, rendered)
  let output = if rendered.content == "" {
    footer
  } else {
    "\{rendered.content}\n\{footer}"
  }
  @agent_tool.ToolAction::respond(output, is_error=rendered.truncated, brief~)
}

///|
/// One-line status footer appended after the numbered content, replacing the
/// old multi-field header. The model gets the line range it actually saw
/// (`start_line` plus `shown_lines`), the file's `total_lines` (so it can tell
/// whether more lines follow), and whether the `max_output_chars` budget cut
/// the body (`truncated`).
fn read_footer(
  selection : ReadSelection,
  rendered : RenderedSelection,
) -> String {
  "<system>start_line=\{selection.start_line} shown_lines=\{rendered.shown_lines} total_lines=\{selection.total_lines} truncated=\{rendered.truncated}</system>"
}

///|
fn select_lines(
  content : String,
  start_line : Int,
  max_lines : Int?,
) -> ReadSelection {
  let lines = [ for line in content.split("\n") => line ]
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
  let selected = lines[start_index:end_exclusive]
  {
    content: selected.join("\n"),
    start_line,
    total_lines,
    shown_lines: selected.length(),
  }
}

///|
async fn directory_read_error(path : String) -> String? {
  match (@fs.kind(path, follow_symlink=true) catch { _ => return None }) {
    Directory =>
      Some(
        "error reading \{path}: path is a directory; use the shell tool with `ls` or `tree` to inspect directories, then read specific files.",
      )
    _ => None
  }
}

///|
/// Keep at most `max_units` leading UTF-16 code units of `content`. The budget
/// is a soft limit, so we count in code units (`String::length`, O(1)) rather
/// than Unicode code points, and only snap the cut down to a character boundary
/// so the result can never end in a lone surrogate.
fn code_unit_prefix(content : String, max_units : Int) -> String {
  if max_units <= 0 {
    ""
  } else if content.length() <= max_units {
    content
  } else {
    "\{content[:char_boundary_at_or_below(content, max_units)]}"
  }
}

///|
/// Largest code-unit offset `<= max_units` that is a valid character boundary.
/// A surrogate pair spans two code units; if `max_units` would land between them
/// (the unit at `max_units` is a trailing surrogate) step back one so the
/// leading surrogate is dropped too. Callers pass `max_units < content.length()`.
fn char_boundary_at_or_below(content : String, max_units : Int) -> Int {
  if is_low_surrogate(content.at(max_units)) {
    max_units - 1
  } else {
    max_units
  }
}

///|
fn is_low_surrogate(unit : UInt16) -> Bool {
  let code = unit.to_int()
  code >= 0xDC00 && code <= 0xDFFF
}

///|
fn render_numbered_content(
  selection : ReadSelection,
  max_chars : Int,
) -> RenderedSelection {
  if selection.shown_lines == 0 {
    return { content: "", shown_lines: 0, truncated: false }
  }
  if max_chars <= 0 {
    return { content: "", shown_lines: 0, truncated: true }
  }
  let lines = [ for line in selection.content.split("\n") => line.to_owned() ]
  let numbered : Array[String] = []
  let mut remaining = max_chars
  let mut truncated = false
  for index in 0..<lines.length() {
    let separator_units = if numbered.length() == 0 { 0 } else { 1 }
    let prefix = "\{selection.start_line + index}\t"
    let prefix_budget = separator_units + prefix.length()
    if remaining < prefix_budget {
      truncated = true
      break
    }
    let available = remaining - prefix_budget
    let line = lines[index]
    let line_units = line.length()
    if line_units <= available {
      numbered.push("\{prefix}\{line}")
      remaining = remaining - prefix_budget - line_units
    } else {
      numbered.push("\{prefix}\{code_unit_prefix(line, available)}")
      remaining = 0
      truncated = true
      break
    }
  }
  if numbered.length() < lines.length() {
    truncated = true
  }
  { content: numbered.join("\n"), shown_lines: numbered.length(), truncated }
}

///|
async test "read renders a whole file as numbered lines with a status footer" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/test.txt"
    @fs.write_file(path, "hello read", create_mode=CreateOrTruncate)
    let result = execute({ "path": path })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(
      output.content,
      [
        "1\thello read", "<system>start_line=1 shown_lines=1 total_lines=1 truncated=false</system>",
      ].join("\n"),
    )
  })
}

///|
async test "read resolves relative paths under the workspace root" {
  @vfs.with_tmpdir(prefix="openseek-read-workspace-", dir => {
    @fs.write_file(
      "\{dir}/note.txt",
      "workspace read",
      create_mode=CreateOrTruncate,
    )
    let tool = definition(workspace_root=dir)
    let result = match tool.execute {
      Async(execute) => execute({ "path": "note.txt" })
      Sync(_) => fail("read tool should be async")
    }
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(
      output.content,
      [
        "1\tworkspace read", "<system>start_line=1 shown_lines=1 total_lines=1 truncated=false</system>",
      ].join("\n"),
    )
  })
}

///|
async test "read renders an empty file as a single empty numbered line" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/empty.txt"
    @fs.write_file(path, "", create_mode=CreateOrTruncate)
    let result = execute({ "path": path })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(
      output.content,
      [
        "1\t", "<system>start_line=1 shown_lines=1 total_lines=1 truncated=false</system>",
      ].join("\n"),
    )
  })
}

///|
async test "read numbers every line including a trailing blank from a final newline" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/multiline.txt"
    @fs.write_file(
      path,
      "line one\nline two\nline three\n",
      create_mode=CreateOrTruncate,
    )
    let result = execute({ "path": path })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(
      output.content,
      [
        "1\tline one", "2\tline two", "3\tline three", "4\t", "<system>start_line=1 shown_lines=4 total_lines=4 truncated=false</system>",
      ].join("\n"),
    )
  })
}

///|
async test "read returns a requested line range and reports more lines remain" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/range.txt"
    @fs.write_file(
      path,
      "line one\nline two\nline three\nline four",
      create_mode=CreateOrTruncate,
    )
    let result = execute({ "path": path, "start_line": 2, "max_lines": 2 })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    // shown_lines (2) < total_lines (4) is how the model learns lines 4.. are
    // still unread; there is no separate `line_limited` flag.
    assert_eq(
      output.content,
      [
        "2\tline two", "3\tline three", "<system>start_line=2 shown_lines=2 total_lines=4 truncated=false</system>",
      ].join("\n"),
    )
  })
}

///|
async test "read returns a footer only when the range starts past EOF" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/short.txt"
    @fs.write_file(path, "a\nb", create_mode=CreateOrTruncate)
    let result = execute({ "path": path, "start_line": 10 })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(
      output.content,
      "<system>start_line=10 shown_lines=0 total_lines=2 truncated=false</system>",
    )
  })
}

///|
async test "read caps oversized output and marks it as an error" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/capped.txt"
    @fs.write_file(path, "abcdef", create_mode=CreateOrTruncate)
    let result = execute({ "path": path, "max_output_chars": 3 })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_eq(
      output.content,
      [
        "1\ta", "<system>start_line=1 shown_lines=1 total_lines=1 truncated=true</system>",
      ].join("\n"),
    )
  })
}

///|
async test "read counts the line-number gutter against the output budget" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/many-lines.txt"
    @fs.write_file(
      path,
      [ for _ in 0..<80 => "x" ].join("\n"),
      create_mode=CreateOrTruncate,
    )
    let result = execute({ "path": path, "max_output_chars": 20 })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    // 20 code units buys exactly five `N\tx` lines (gutters included); the
    // sixth gutter would overrun, so the body stops at line 5.
    assert_eq(
      output.content,
      [
        "1\tx", "2\tx", "3\tx", "4\tx", "5\tx", "<system>start_line=1 shown_lines=5 total_lines=80 truncated=true</system>",
      ].join("\n"),
    )
  })
}

///|
async test "read caps unicode content on character boundaries" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/unicode.txt"
    // "😀" is one code point but two UTF-16 code units; "😀Z" has length 3.
    @fs.write_file(path, "😀Z", create_mode=CreateOrTruncate)
    // Budget 4 = "1\t" (2 units) + "😀" (2 units): the emoji fits whole, Z drops.
    let fits = execute({ "path": path, "max_lines": 1, "max_output_chars": 4 })
    guard fits is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_eq(
      output.content,
      [
        "1\t😀", "<system>start_line=1 shown_lines=1 total_lines=1 truncated=true</system>",
      ].join("\n"),
    )
    // Budget 3 leaves one unit after the gutter, which would split "😀". Rather
    // than emit a lone surrogate (a slice mid-pair actually panics), the whole
    // emoji is dropped.
    let splits = execute({ "path": path, "max_lines": 1, "max_output_chars": 3 })
    guard splits is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_false(output.content.contains("😀"))
    assert_eq(
      output.content,
      [
        "1\t", "<system>start_line=1 shown_lines=1 total_lines=1 truncated=true</system>",
      ].join("\n"),
    )
  })
}

///|
async test "read numbers lines cat-n style with no header block" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/aligned.txt"
    let content = [ for index in 1..<=111 => "line \{index}" ].join("\n")
    @fs.write_file(path, content, create_mode=CreateOrTruncate)
    let result = execute({ "path": path, "start_line": 9, "max_lines": 103 })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_true(output.content.contains("9\tline 9"))
    assert_true(output.content.contains("99\tline 99"))
    assert_true(output.content.contains("100\tline 100"))
    assert_true(output.content.contains("111\tline 111"))
    assert_true(
      output.content.has_suffix(
        "<system>start_line=9 shown_lines=103 total_lines=111 truncated=false</system>",
      ),
    )
    // The old header is gone: no padded arrows, no `path=`/`---`/`line_format`.
    assert_false(output.content.contains("| line"))
    assert_false(output.content.contains("path="))
    assert_false(output.content.contains("line_format"))
    assert_false(output.content.contains("---"))
  })
}

///|
test "read description encourages batched reads and directory inspection" {
  let tool = definition()
  assert_true(tool.description.contains("batch separate read tool calls"))
  assert_true(tool.description.contains("Do not use read for directories"))
  let JsonSchema(schema) = tool.schema
  let schema_text = schema.stringify()
  assert_true(schema_text.contains("\"path\""))
  assert_false(schema_text.contains("\"paths\""))
  assert_true(schema_text.contains("\"required\""))
  assert_true(schema_text.contains("Directories are not supported"))
}

///|
test "read parses and caps optional limits" {
  let input = @decode.decode({
    "path": "file.mbt",
    "start_line": 3,
    "max_lines": 4,
    "max_output_chars": 999999,
  })
  assert_eq(input.path, "file.mbt")
  assert_eq(input.start_line, 3)
  guard input.max_lines is Some(max_lines) else { fail("missing max_lines") }
  assert_eq(max_lines, 4)
  assert_eq(input.max_output_chars, @decode.hard_max_output_chars)
}

///|
async test "read rejects paths array and explains batching" {
  let result = execute({ "paths": ["a.mbt", "b.mbt"] })
  guard result is Respond(output) else { fail("expected Respond") }
  assert_true(output.is_error)
  assert_true(output.content.contains("arguments.paths is not supported"))
  assert_true(output.content.contains("batch separate read calls"))
}

///|
async test "read surfaces filesystem errors" {
  @vfs.with_tmpdir(dir => {
    let result = execute({ "path": "\{dir}/does-not-exist" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.content.contains("error reading"))
    assert_true(output.is_error)
  })
}

///|
async test "read reports directories with an actionable hint" {
  @vfs.with_tmpdir(dir => {
    let result = execute({ "path": dir })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("path is a directory"))
    assert_true(output.content.contains("`ls` or `tree`"))
  })
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
  @vfs.with_tmpdir(dir => {
    let result = execute({ "path": "\{dir}/test.txt", "max_lines": 0 })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.content.contains("error: read requires"))
    assert_true(
      output.content.contains("arguments.max_lines to be a positive number"),
    )
    assert_true(output.is_error)
  })
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
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/huge-max.txt"
    @fs.write_file(path, "a\nb\nc", create_mode=CreateOrTruncate)
    let result = execute({
      "path": path,
      "start_line": 2,
      "max_lines": 2147483647,
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(
      output.content,
      [
        "2\tb", "3\tc", "<system>start_line=2 shown_lines=2 total_lines=3 truncated=false</system>",
      ].join("\n"),
    )
  })
}
