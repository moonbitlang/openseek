///|
/// Tool definition for `multi_edit`: applies several exact line-anchored
/// replacements to one file after validating every edit against the original
/// file.
///
/// `multi_edit` is primarily for efficient compiler-feedback repair loops where
/// diagnostics identify several known locations in one file. It avoids a batch
/// of separate `edit` calls while still requiring an explicit start line for
/// each replacement.
pub fn definition(
  workspace_root? : String = ".",
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="multi_edit",
    description="Apply multiple exact line-anchored replacements to one file. Use this when compiler feedback identifies several known locations in the same file. Every edit must include old_string, new_string, and start_line; optional end_line bounds the search. Because each edit is line-anchored, old_string can be the small exact span to replace instead of a large context block. Each edit replaces the first matching span in its selected region. All edits are validated against the original file and no changes are written if any edit fails.",
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "path": { "type": "string" },
        "edits": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "old_string": { "type": "string" },
              "new_string": { "type": "string" },
              "start_line": { "type": "integer" },
              "end_line": { "type": "integer" },
            },
            "required": ["old_string", "new_string", "start_line"],
          },
        },
      },
      "required": ["path", "edits"],
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
        "error: multi_edit requires \{message}",
        is_error=true,
      )
    }
  }
  let path = @workspace_path.resolve(workspace_root, input.path)
  multi_edit_file(input, path~)
}

///|
async fn multi_edit_file(
  input : @decode.MultiEditInput,
  path~ : String,
) -> @agent_tool.ToolAction {
  let fail_brief = "multi_edit \{@agent_tool.brief_basename(path)}"
  let content = @fs.read_file(path).text() catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      return @agent_tool.ToolAction::respond(
        "error multi_editing \{path}: error reading file: \{error}",
        is_error=true,
        brief=fail_brief,
      )
  }
  let plans : Array[PlannedEdit] = []
  let failures : Array[EditFailure] = []
  for index, item in input.edits {
    match validate_edit(content, item, index) {
      Valid(plan) => plans.push(plan)
      Invalid(failure) => failures.push(failure)
    }
  }
  collect_overlap_failures(plans, failures)
  if failures.length() > 0 {
    return @agent_tool.ToolAction::respond(
      failure_report(path, failures),
      is_error=true,
      brief=fail_brief,
    )
  }
  let new_content = apply_plans(content, plans)
  match @manifest_error.write_error(path, new_content) {
    Some(message) =>
      return @agent_tool.ToolAction::respond(
        "error multi_editing \{path}: \{message}; no changes applied",
        is_error=true,
        brief=fail_brief,
      )
    None => ()
  }
  try {
    @fs.write_file(path, new_content, create_mode=CreateOrTruncate)
    let summary = "ok: applied \{plans.length()} edit(s) in \{path}"
    let response = @auto_check.append_summary(path, summary)
    @agent_tool.ToolAction::respond(
      response,
      brief="multi_edit \{@agent_tool.brief_basename(path)} (\{plans.length()}×)",
    )
  } catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      @agent_tool.ToolAction::respond(
        "error multi_editing \{path}: error writing file: \{error}",
        is_error=true,
        brief=fail_brief,
      )
  }
}

///|
priv enum EditValidation {
  Valid(PlannedEdit)
  Invalid(EditFailure)
}

///|
priv struct PlannedEdit {
  index : Int
  start : Int
  end : Int
  new_string : String
  range : String
}

///|
priv struct EditFailure {
  index : Int
  range : String
  message : String
}

///|
fn validate_edit(
  content : String,
  item : @decode.MultiEditItem,
  index : Int,
) -> EditValidation {
  let range = line_range_label(item.start_line, item.end_line)
  if item.old_string == "" {
    return Invalid({ index, range, message: "old_string must be non-empty" })
  }
  if item.old_string == item.new_string {
    return Invalid({
      index,
      range,
      message: "old_string and new_string are identical",
    })
  }
  let region = select_edit_region(content, item.start_line, item.end_line)
  let parts = region.body
    .split(item.old_string)
    .map(part => part.to_owned())
    .collect()
  let occurrences = parts.length() - 1
  if occurrences == 0 {
    return Invalid({ index, range, message: "old_string not found" })
  }
  let start = region.start_offset + parts[0].length()
  Valid({
    index,
    start,
    end: start + item.old_string.length(),
    new_string: item.new_string,
    range,
  })
}

///|
fn collect_overlap_failures(
  plans : Array[PlannedEdit],
  failures : Array[EditFailure],
) -> Unit {
  let ordered = [ for plan in plans => plan ]
  ordered.sort_by(compare_plan_ascending)
  let mut previous_end = -1
  let mut previous_index = -1
  for plan in ordered {
    if plan.start < previous_end {
      failures.push({
        index: plan.index,
        range: plan.range,
        message: "replacement overlaps edit[\{previous_index}]",
      })
    }
    if plan.end > previous_end {
      previous_end = plan.end
      previous_index = plan.index
    }
  }
}

///|
fn compare_plan_ascending(a : PlannedEdit, b : PlannedEdit) -> Int {
  if a.start < b.start {
    -1
  } else if a.start > b.start {
    1
  } else if a.end < b.end {
    -1
  } else if a.end > b.end {
    1
  } else {
    compare_int(a.index, b.index)
  }
}

///|
fn compare_plan_descending(a : PlannedEdit, b : PlannedEdit) -> Int {
  -compare_plan_ascending(a, b)
}

///|
fn compare_int(a : Int, b : Int) -> Int {
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

///|
fn apply_plans(content : String, plans : Array[PlannedEdit]) -> String {
  let ordered = [ for plan in plans => plan ]
  ordered.sort_by(compare_plan_descending)
  let mut output = content
  for plan in ordered {
    output = "\{output.unsafe_substring(start=0, end=plan.start)}\{plan.new_string}\{output.unsafe_substring(start=plan.end, end=output.length())}"
  }
  output
}

///|
fn failure_report(path : String, failures : Array[EditFailure]) -> String {
  let lines = [
    for failure in failures => {
      "edit[\{failure.index}] \{failure.range}: \{failure.message}"
    }
  ]
  "error multi_editing \{path}: \{failures.length()} edit(s) failed; no changes applied\n\{lines.join("\n")}"
}

///|
priv struct EditRegion {
  body : String
  start_offset : Int
}

///|
fn select_edit_region(
  content : String,
  start_line : Int,
  end_line : Int?,
) -> EditRegion {
  let start = line_start_offset(content, start_line)
  let end = match end_line {
    Some(line) => line_end_offset(content, line)
    None => content.length()
  }
  let start = start.clamp(min=0, max=content.length())
  let end = end.clamp(min=start, max=content.length())
  { body: content.unsafe_substring(start~, end~), start_offset: start }
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
fn line_range_label(start_line : Int, end_line : Int?) -> String {
  match end_line {
    Some(end) => "line range \{start_line}-\{end}"
    None => "from line \{start_line}"
  }
}
