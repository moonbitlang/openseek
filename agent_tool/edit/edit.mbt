///|
/// Tool definition for `edit`: replaces exact text in `arguments.path`.
///
/// ## Arguments
/// - `path` (string, required): filesystem path to edit.
/// - `old_string` (string, required): exact text to replace. It must be
///   non-empty.
/// - `new_string` (string, required): replacement text. It must differ from
///   `old_string`.
/// - `replace_all` (bool, optional): replace every occurrence. Defaults to
///   `false`; when false, `old_string` must occur exactly once.
///
/// ## Result
/// - `Respond(ToolOutput("ok: replaced <n> occurrence(s) in <path>"))` on
///   success.
/// - `Respond(ToolOutput("error editing <path>: ...", is_error=true))` for
///   filesystem failures, empty/no-op edits, missing matches, or ambiguous
///   matches. Ambiguous-match errors include the first matching line numbers; a
///   not-found error points at the closest actual line in the file (or nudges a
///   re-read) so the model can correct `old_string`.
/// - `Respond(ToolOutput("error: edit requires ...", is_error=true))` for
///   invalid arguments.
pub fn definition(
  workspace_root? : String = ".",
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="edit",
    description="Replace exact text in arguments.path with arguments.new_string. old_string must match the file's current text exactly — read the file first if you are unsure — and must be unique unless replace_all is set.",
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "path": { "type": "string" },
        "old_string": { "type": "string" },
        "new_string": { "type": "string" },
        "replace_all": { "type": "boolean" },
      },
      "required": ["path", "old_string", "new_string"],
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
  let parts = content
    .split(input.old_string)
    .map(part => part.to_owned())
    .collect()
  let occurrences = parts.length() - 1
  if occurrences == 0 {
    return @agent_tool.ToolAction::respond(
      "error editing \{path}: old_string not found.\{not_found_hint(content, input.old_string)}",
      is_error=true,
      brief=fail_brief,
    )
  }
  if occurrences > 1 && !input.replace_all {
    return @agent_tool.ToolAction::respond(
      ambiguous_match_message(path, occurrences, parts, input.old_string),
      is_error=true,
      brief=fail_brief,
    )
  }
  let replacement_count = if input.replace_all { occurrences } else { 1 }
  let new_content = if input.replace_all {
    parts.join(input.new_string)
  } else {
    content.replace(old=input.old_string, new=input.new_string)
  }
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
    let content = @auto_check.append_summary(
      path,
      "ok: replaced \{replacement_count} occurrence(s) in \{path}",
    )
    @agent_tool.ToolAction::respond(
      content,
      brief="edited \{@agent_tool.brief_basename(path)} (\{replacement_count}×)",
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
/// Diagnostic appended when `old_string` is not found, so the model has more to
/// recover from than a bare "not found" — its top failure mode is an
/// `old_string` that no longer matches the file (misremembered text or a stale
/// view). Anchors on the most distinctive line of `old_string` — longest, and
/// containing a letter or digit — that also appears in the file (exact once
/// trimmed, else a substring overlap) and reports it with its 1-based line
/// number. Falls back to a read-first nudge when nothing distinctive matches.
fn not_found_hint(content : String, old_string : String) -> String {
  let file_lines = [ for line in content.split("\n") => line.to_owned() ]
  // Longest lines first: they are the most distinctive and least likely to
  // anchor on the wrong place.
  let anchors = [ for line in old_string.split("\n") => line.to_owned() ]
  anchors.sort_by((a, b) => b.trim().length() - a.trim().length())
  for anchor in anchors {
    let needle = anchor.trim()
    if needle.length() < 4 || !has_alnum(needle) {
      continue
    }
    // A line equal once trimmed: same text, most likely different indentation.
    for index, line in file_lines {
      if line.trim() == needle {
        return closest_text_hint(index + 1, line)
      }
    }
    // A line that overlaps the anchor as a substring either way.
    for index, line in file_lines {
      let trimmed = line.trim()
      if line.contains(needle) ||
        (
          trimmed.length() >= 4 &&
          has_alnum(trimmed) &&
          needle.contains(trimmed)
        ) {
        return closest_text_hint(index + 1, line)
      }
    }
  }
  " Read the file first, then copy old_string exactly from its current contents."
}

///|
fn closest_text_hint(line_number : Int, line : String) -> String {
  " The closest text in the file is line \{line_number}: \{cap_chars(line.trim(), 120)} — re-read the file and copy old_string exactly from its current contents."
}

///|
/// First `max` characters of `s`, Unicode-safe (never splitting a code point),
/// with a trailing ellipsis when it was longer.
fn cap_chars(s : StringView, max : Int) -> String {
  let buf = StringBuilder::new()
  let mut count = 0
  for c in s {
    if count >= max {
      buf.write_string("…")
      break
    }
    buf.write_char(c)
    count = count + 1
  }
  buf.to_string()
}

///|
/// Whether `s` contains an ASCII letter or digit. Used to skip structural lines
/// (`///|`, `{`, `}`) that make poor, ambiguous match anchors.
fn has_alnum(s : StringView) -> Bool {
  for c in s {
    if c is ('0'..='9' | 'a'..='z' | 'A'..='Z') {
      return true
    }
  }
  false
}

///|
fn ambiguous_match_message(
  path : String,
  occurrences : Int,
  parts : Array[String],
  old_string : String,
) -> String {
  let lines = occurrence_line_labels(parts, old_string, 5)
  let line_detail = if lines.length() == 0 {
    ""
  } else if occurrences > lines.length() {
    " on lines \{lines.join(", ")}, ..."
  } else {
    " on lines \{lines.join(", ")}"
  }
  "error editing \{path}: old_string matched \{occurrences} times\{line_detail}; set replace_all=true to replace all occurrences"
}

///|
fn occurrence_line_labels(
  parts : Array[String],
  old_string : String,
  max : Int,
) -> Array[String] {
  let labels : Array[String] = []
  let mut current_line = 1
  let occurrence_count = parts.length() - 1
  for index in 0..<occurrence_count {
    current_line = current_line + newline_count(parts[index])
    if labels.length() < max {
      labels.push("\{current_line}")
    }
    current_line = current_line + newline_count(old_string)
  }
  labels
}

///|
fn newline_count(text : String) -> Int {
  text.split("\n").count() - 1
}
