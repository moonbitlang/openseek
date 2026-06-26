///|
/// Tool definition for `edit`: replaces exact text in `arguments.path`.
///
/// ## Arguments
/// - `path` (string, required): filesystem path to edit.
/// - `old_string` (string, required): exact text to replace. It must be
///   non-empty.
/// - `new_string` (string, required): replacement text. It must differ from
///   `old_string`.
/// - `start_line` (integer, required): 1-based inclusive first line to search.
/// - `end_line` (integer, optional): 1-based inclusive last line to search.
/// - `replace_all=true` is rejected. Use `multi_edit` for multiple explicit
///   line-anchored replacements.
///
/// ## Result
/// - `Respond(ToolOutput("ok: replaced <n> occurrence(s) at line <line> in <path>"))`
///   on success.
/// - `Respond(ToolOutput("error editing <path>: ...", is_error=true))` for
///   filesystem failures, empty/no-op edits, or missing matches.
/// - `Respond(ToolOutput("error: edit requires ...", is_error=true))` for
///   invalid arguments.
pub fn definition(
  workspace_root? : String = ".",
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="edit",
    description="Replace the first exact text span at or after arguments.start_line in arguments.path with arguments.new_string. Optional end_line restricts the search to a 1-based inclusive line range. Because start_line anchors the location, old_string can be a small exact span instead of a large context block. For multiple compiler-feedback fixes in one file, use multi_edit with explicit line-anchored edits.",
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "path": { "type": "string" },
        "old_string": { "type": "string" },
        "new_string": { "type": "string" },
        "start_line": { "type": "integer" },
        "end_line": { "type": "integer" },
      },
      "required": ["path", "old_string", "new_string", "start_line"],
    }),
    execute=Async(arguments => execute_with_workspace(workspace_root, arguments)),
  )
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
        "error: edit requires \{message}",
        is_error=true,
      )
    }
  }
  let path = @workspace_path.resolve(workspace_root, input.path)
  edit_file(input, path~)
}

///|
async fn edit_file(
  input : @decode.EditInput,
  path~ : String,
) -> @agent_tool.ToolAction {
  // Every failure names the file it tried to edit so the viz can show
  // `→ edit · edit <file> 🚩` on the folded call line.
  let fail_brief = "edit \{@agent_tool.brief_basename(path)}"
  if input.replace_all {
    return @agent_tool.ToolAction::respond(
      "error editing \{path}: replace_all=true is no longer supported; use multi_edit with explicit line-anchored edits",
      is_error=true,
      brief=fail_brief,
    )
  }
  if input.old_string == "" {
    return @agent_tool.ToolAction::respond(
      "error editing \{path}: old_string must be non-empty",
      is_error=true,
      brief=fail_brief,
    )
  }
  if input.old_string == input.new_string {
    return @agent_tool.ToolAction::respond(
      "error editing \{path}: old_string and new_string are identical",
      is_error=true,
      brief=fail_brief,
    )
  }
  let content = @fs.read_file(path).text() catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      return @agent_tool.ToolAction::respond(
        "error editing \{path}: error reading file: \{error}",
        is_error=true,
        brief=fail_brief,
      )
  }
  let region = select_edit_region(content, input)
  let parts = region.body
    .split(input.old_string)
    .map(part => part.to_owned())
    .collect()
  if parts.length() <= 1 {
    return @agent_tool.ToolAction::respond(
      "error editing \{path}: old_string not found\{range_detail(input)}",
      is_error=true,
      brief=fail_brief,
    )
  }
  let replacement_count = 1
  let match_start = parts[0].length()
  let match_end = match_start + input.old_string.length()
  let match_line = line_number_at_offset(
    content,
    region.prefix.length() + match_start,
  )
  let new_body = "\{parts[0]}\{input.new_string}\{region.body.unsafe_substring(start=match_end, end=region.body.length())}"
  let new_content = "\{region.prefix}\{new_body}\{region.suffix}"
  match @manifest_error.write_error(path, new_content) {
    Some(message) =>
      return @agent_tool.ToolAction::respond(
        "error editing \{path}: \{message}",
        is_error=true,
        brief=fail_brief,
      )
    None => ()
  }
  try {
    @fs.write_file(path, new_content, create_mode=CreateOrTruncate)
    let summary = "ok: replaced \{replacement_count} occurrence(s) at line \{match_line} in \{path}"
    let content = @auto_check.append_summary(path, summary)
    @agent_tool.ToolAction::respond(
      content,
      brief="edited \{@agent_tool.brief_basename(path)}:\{match_line} (\{replacement_count}×)",
    )
  } catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      @agent_tool.ToolAction::respond(
        "error editing \{path}: error writing file: \{error}",
        is_error=true,
        brief=fail_brief,
      )
  }
}

///|
priv struct EditRegion {
  prefix : String
  body : String
  suffix : String
}

///|
fn select_edit_region(
  content : String,
  input : @decode.EditInput,
) -> EditRegion {
  let start_line = input.start_line
  let start = line_start_offset(content, start_line)
  let end = match input.end_line {
    Some(line) => line_end_offset(content, line)
    None => content.length()
  }
  // `decode` guarantees end_line >= start_line when both are present. These
  // clamps make ranges beyond EOF select an empty suffix without panicking.
  let start = start.clamp(min=0, max=content.length())
  let end = end.clamp(min=start, max=content.length())
  {
    prefix: content.unsafe_substring(start=0, end=start),
    body: content.unsafe_substring(start~, end~),
    suffix: content.unsafe_substring(start=end, end=content.length()),
  }
}

///|
fn line_start_offset(content : String, line : Int) -> Int {
  if line <= 1 {
    0
  } else {
    let len = content.length()
    let mut current_line = 1
    for cursor = 0; cursor < len; cursor = cursor + 1 {
      if content[cursor] == '\n' {
        current_line = current_line + 1
        if current_line == line {
          break cursor + 1
        }
      }
    } nobreak {
      len
    }
  }
}

///|
fn line_end_offset(content : String, line : Int) -> Int {
  let len = content.length()
  let mut current_line = 1
  for cursor = 0; cursor < len; cursor = cursor + 1 {
    if content[cursor] == '\n' {
      if current_line == line {
        break cursor + 1
      }
      current_line = current_line + 1
    }
  } nobreak {
    len
  }
}

///|
fn line_number_at_offset(content : String, offset : Int) -> Int {
  let bounded_offset = offset.clamp(min=0, max=content.length())
  let mut line = 1
  for cursor = 0; cursor < bounded_offset; cursor = cursor + 1 {
    if content[cursor] == '\n' {
      line = line + 1
    }
  }
  line
}

///|
fn range_detail(input : @decode.EditInput) -> String {
  match input.end_line {
    Some(end) => " in line range \{input.start_line}-\{end}"
    None => " from line \{input.start_line}"
  }
}
