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
///   Every read has the same shape regardless of range or cap:
///   `<line-number> |<content>` lines, with line numbers right-aligned to the
///   selected range, followed by a single
///   `<system>start_line=.. shown_lines=.. total_lines=.. truncated=..</system>`
///   footer (footer only when the body is empty, e.g. a range past EOF). A
///   zero-byte file returns just that footer with `total_lines=0 note=empty
///   file`. A body cut by the `max_output_chars` budget is still a successful
///   read, not a tool error: the footer's `truncated=true` tells the model the
///   prefix is incomplete, and the brief gains a `(truncated)` marker for the
///   human transcript.
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
    description=(
      #|Read arguments.path as text. For several known independent files, batch separate
      #|read tool calls in one assistant response when possible. Do not use read for
      #|directories: inspect them with `ls` or `tree`, then read specific files. Supports
      #|optional start_line, max_lines, and max_output_chars for focused single-file
      #|reads. Output is right-aligned `<line-number> |<content>` numbered lines followed
      #|by a `<system>` status footer.
    ),
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
    execute=Async(arguments => execute(workspace_root~, arguments)),
  )
}

///|
async fn execute(
  workspace_root? : String = ".",
  arguments : Json,
) -> @agent_tool.ToolAction {
  let input = @decode.decode(arguments) catch {
    error => {
      let message = @tool_error.failure_message("\{error}")
      return @agent_tool.respond(
        "error: read requires \{message}",
        is_error=true,
      )
    }
  }
  read_file(input, path=@workspace_path.resolve(workspace_root, input.path))
}

///|
async fn read_file(
  input : @decode.ReadInput,
  path~ : String,
) -> @agent_tool.ToolAction {
  let brief = "read \{@agent_tool.brief_basename(path)}"
  let is_directory = (@fs.kind(path, follow_symlink=true) is Directory) catch {
    _ => false
  }
  if is_directory {
    return @agent_tool.respond(
      "error reading \{path}: path is a directory; use the shell tool with `ls` or `tree` to inspect directories, then read specific files.",
      is_error=true,
      brief~,
    )
  }
  let content = @fs.read_file(path).text()
  // A zero-byte file would otherwise render as a phantom blank line `1 |`;
  // report it explicitly so the model doesn't read that as real content. A file
  // containing only a newline is not empty (it has blank lines) and renders
  // normally.
  if content == "" {
    return @agent_tool.respond(
      "<system>start_line=\{input.start_line} shown_lines=0 total_lines=0 truncated=false note=empty file</system>",
      is_error=false,
      brief~,
    )
  }
  let lines = [..content.split("\n")]
  let total_lines = lines.length()
  // Clamp both bounds into [0, total_lines] so the render loop only visits
  // valid lines — a start past the last line selects nothing.
  let start_index = (input.start_line - 1).clamp(min=0, max=total_lines)
  let end_exclusive = match input.max_lines {
    // Clamp the count BEFORE adding: a huge max_lines (e.g. Int max) must
    // not overflow past start_index. Such a request returns the remaining
    // lines, where a post-add clamp could overflow and select nothing.
    Some(count) =>
      start_index + count.clamp(min=0, max=total_lines - start_index)
    None => total_lines
  }
  let line_number_width = if start_index < end_exclusive {
    (input.start_line + end_exclusive - start_index - 1).to_string().length()
  } else {
    input.start_line.to_string().length()
  }
  let output = StringBuilder()
  let mut shown_lines = 0
  let mut truncated = false
  if start_index < end_exclusive {
    if input.max_output_chars <= 0 {
      truncated = true
    } else {
      let mut remaining = input.max_output_chars
      for offset, line in lines[start_index:end_exclusive] {
        let separator_units = if output.is_empty() { 0 } else { 1 }
        let line_number = input.start_line + offset
        let prefix = "\{line_number.to_string().pad_start(line_number_width, ' ')} |"
        let prefix_budget = separator_units + prefix.length()
        if remaining < prefix_budget {
          truncated = true
          break
        }
        if separator_units == 1 {
          output <+ "\n"
        }
        let available = remaining - prefix_budget
        let line_units = line.length()
        if line_units <= available {
          output <+ "\{prefix}\{line}"
          remaining = remaining - prefix_budget - line_units
        } else {
          output <+ "\{prefix}\{line.clamped_view(end=available)}"
          remaining = 0
          truncated = true
          shown_lines += 1
          break
        }
        shown_lines += 1
      }
      if shown_lines < end_exclusive - start_index {
        truncated = true
      }
    }
  }
  // Every read has the same shape: numbered lines followed by a single status
  // footer. When the body is empty (start past EOF, or a zero budget) only the
  // footer is returned, so the model still learns what it asked for.
  if !output.is_empty() {
    output <+ "\n"
  }
  output <+
    "<system>start_line=\{input.start_line} shown_lines=\{shown_lines} total_lines=\{total_lines} truncated=\{truncated}</system>"
  // A truncated body is a successful read of a prefix, not a failure: the
  // model sees `truncated=true` in the footer, so treating it as a tool error
  // would only teach the loop to retry a read that worked. The brief carries
  // the marker so a human scanning the transcript sees the cut too.
  @agent_tool.respond(
    output.to_string(),
    is_error=false,
    brief=if truncated { "\{brief} (truncated)" } else { brief },
  )
}

///|
async test "read renders a whole file as numbered lines with a status footer" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/test.txt"
    @vfs.FileSystem({ "test.txt": "hello read" }).write_to(dir)
    let result = execute({ "path": path })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    // An untruncated read keeps the plain brief — no `(truncated)` marker.
    guard output.brief is Some(brief) else { fail("expected a brief") }
    assert_eq(brief, "read test.txt")
    assert_eq(
      output.content,
      (
        #|1 |hello read
        #|<system>start_line=1 shown_lines=1 total_lines=1 truncated=false</system>
      ),
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
      (
        #|1 |workspace read
        #|<system>start_line=1 shown_lines=1 total_lines=1 truncated=false</system>
      ),
    )
  })
}

///|
async test "read reports a zero-byte file explicitly" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/empty.txt"
    @vfs.FileSystem({ "empty.txt": "" }).write_to(dir)
    let result = execute({ "path": path })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(
      output.content,
      "<system>start_line=1 shown_lines=0 total_lines=0 truncated=false note=empty file</system>",
    )
  })
}

///|
async test "read treats a single-newline file as one blank line, not empty" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/newline.txt"
    @vfs.FileSystem({ "newline.txt": "\n" }).write_to(dir)
    let result = execute({ "path": path })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    // "\n" splits into two empty lines, so this is not the empty-file case.
    assert_eq(
      output.content,
      (
        #|1 |
        #|2 |
        #|<system>start_line=1 shown_lines=2 total_lines=2 truncated=false</system>
      ),
    )
  })
}

///|
async test "read numbers every line including a trailing blank from a final newline" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/multiline.txt"
    @vfs.FileSystem({ "multiline.txt": "line one\nline two\nline three\n" }).write_to(
      dir,
    )
    let result = execute({ "path": path })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(
      output.content,
      (
        #|1 |line one
        #|2 |line two
        #|3 |line three
        #|4 |
        #|<system>start_line=1 shown_lines=4 total_lines=4 truncated=false</system>
      ),
    )
  })
}

///|
async test "read returns a requested line range and reports more lines remain" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/range.txt"
    @vfs.FileSystem({ "range.txt": "line one\nline two\nline three\nline four" }).write_to(
      dir,
    )
    let result = execute({ "path": path, "start_line": 2, "max_lines": 2 })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    // shown_lines (2) < total_lines (4) is how the model learns lines 4.. are
    // still unread; there is no separate `line_limited` flag.
    assert_eq(
      output.content,
      (
        #|2 |line two
        #|3 |line three
        #|<system>start_line=2 shown_lines=2 total_lines=4 truncated=false</system>
      ),
    )
  })
}

///|
async test "read returns a footer only when the range starts past EOF" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/short.txt"
    @vfs.FileSystem({ "short.txt": "a\nb" }).write_to(dir)
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
async test "read caps oversized output without marking it as an error" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/capped.txt"
    @vfs.FileSystem({ "capped.txt": "abcdef" }).write_to(dir)
    let result = execute({ "path": path, "max_output_chars": 4 })
    guard result is Respond(output) else { fail("expected Respond") }
    // The prefix was read successfully; the footer (for the model) and the
    // brief (for the human transcript) carry the truncation, not is_error.
    assert_false(output.is_error)
    guard output.brief is Some(brief) else { fail("expected a brief") }
    assert_eq(brief, "read capped.txt (truncated)")
    assert_eq(
      output.content,
      (
        #|1 |a
        #|<system>start_line=1 shown_lines=1 total_lines=1 truncated=true</system>
      ),
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
    let result = execute({ "path": path, "max_output_chars": 24 })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    // 24 code units buys exactly four two-wide ` N |x` lines (gutters
    // included); the fifth gutter would overrun, so the body stops at line 4.
    assert_eq(
      output.content,
      (
        #| 1 |x
        #| 2 |x
        #| 3 |x
        #| 4 |x
        #|<system>start_line=1 shown_lines=4 total_lines=80 truncated=true</system>
      ),
    )
  })
}

///|
async test "read caps unicode content on character boundaries" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/unicode.txt"
    // "😀" is one code point but two UTF-16 code units; "😀Z" has length 3.
    @vfs.FileSystem({ "unicode.txt": "😀Z" }).write_to(dir)
    // Budget 5 = "1 |" (3 units) + "😀" (2 units): the emoji fits whole, Z drops.
    let fits = execute({ "path": path, "max_lines": 1, "max_output_chars": 5 })
    guard fits is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(
      output.content,
      (
        #|1 |😀
        #|<system>start_line=1 shown_lines=1 total_lines=1 truncated=true</system>
      ),
    )
    // Budget 4 leaves one unit after the gutter, which would split "😀". Rather
    // than emit a lone surrogate (a slice mid-pair actually panics), the whole
    // emoji is dropped.
    let splits = execute({ "path": path, "max_lines": 1, "max_output_chars": 4 })
    guard splits is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_false(output.content.contains("😀"))
    assert_eq(
      output.content,
      (
        #|1 |
        #|<system>start_line=1 shown_lines=1 total_lines=1 truncated=true</system>
      ),
    )
  })
}

///|
async test "read numbers lines with an aligned gutter and no header block" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/aligned.txt"
    let content = [ for index in 1..<=111 => "line \{index}" ].join("\n")
    @fs.write_file(path, content, create_mode=CreateOrTruncate)
    let result = execute({ "path": path, "start_line": 9, "max_lines": 103 })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_true(output.content.contains("  9 |line 9"))
    assert_true(output.content.contains(" 99 |line 99"))
    assert_true(output.content.contains("100 |line 100"))
    assert_true(output.content.contains("111 |line 111"))
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
  // The description is a wrapped `#|` block, so newlines fall mid-phrase;
  // normalize them to spaces before matching the guidance phrases.
  let desc = tool.description.replace_all(old="\n", new=" ")
  assert_true(desc.contains("batch separate read tool calls"))
  assert_true(desc.contains("Do not use read for directories"))
  let JsonSchema(schema) = tool.schema
  let schema_text = schema.stringify()
  assert_true(schema_text.contains("\"path\""))
  assert_false(schema_text.contains("\"paths\""))
  assert_true(schema_text.contains("\"required\""))
  assert_true(schema_text.contains("Directories are not supported"))
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
/// Filesystem faults raise out of the executor; the dispatch boundary in
/// `@agent_tool.execute_tool_call` converts them into recoverable error
/// results, so the contract is asserted through the registry.
async test "read surfaces filesystem errors through the dispatch boundary" {
  @vfs.with_tmpdir(dir => {
    let tools = @agent_tool.Tools([definition()])
    let call = @agent_tool.AgentToolCall(
      ToolCall(
        id="call_1",
        name="read",
        arguments=Json::stringify({ "path": "\{dir}/does-not-exist" }),
      ),
    )
    let result = @agent_tool.execute_tool_call(call, tools)
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("read failed"))
    assert_true(output.content.contains("does-not-exist"))
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
  let result = execute(Json::empty_object())
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
    @vfs.FileSystem({
      "huge-max.txt": (
        #|a
        #|b
        #|c
      ),
    }).write_to(dir)
    let result = execute({
      "path": path,
      "start_line": 2,
      "max_lines": 2147483647,
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_eq(
      output.content,
      (
        #|2 |b
        #|3 |c
        #|<system>start_line=2 shown_lines=2 total_lines=3 truncated=false</system>
      ),
    )
  })
}
