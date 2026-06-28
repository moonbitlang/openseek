///|
/// Tool definition for `multi_edit`: applies many exact line-anchored
/// replacements across one or more files after validating every edit against
/// the original file content.
///
/// `multi_edit` is the efficient path for compiler-feedback repair loops: when
/// diagnostics identify several known locations, batch every fix into one call
/// instead of many separate `edit` calls. Each edit names its own `file`, so a
/// single batch can span multiple files; all edits for a given file must be
/// listed contiguously.
pub fn definition(
  workspace_root? : String = ".",
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="multi_edit",
    description="Apply many exact line-anchored replacements across one or more files in a single validated batch. This is the efficient path for compiler-feedback repair loops: when `moon check` (or another analyzer) reports several known locations, batch all the fixes into one multi_edit call instead of many separate edit calls. Each edit names its `file` plus old_string, new_string, and start_line; optional end_line bounds the search. List all edits for a given file contiguously — a file may not reappear after another file's edits. Because each edit is line-anchored, old_string can be the small exact span to replace instead of a large context block, and each edit replaces the first matching span in its selected region. To INSERT new code instead of replacing, set old_string to the empty string: new_string is inserted at the start of start_line (use start_line = last line + 1 to append at end of file). Do not emit separate edits for changes that fall on the same line or in one tight span: combine them into a single edit whose old_string covers the whole span, because adjacent or overlapping edits collide and the whole batch is rejected. Every edit is validated against the original file before anything is written, and if any edit fails no files are changed.",
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "edits": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "file": { "type": "string" },
              "old_string": { "type": "string" },
              "new_string": { "type": "string" },
              "start_line": { "type": "integer" },
              "end_line": { "type": "integer" },
            },
            "required": ["file", "old_string", "new_string", "start_line"],
          },
        },
      },
      "required": ["edits"],
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
  multi_edit_files(workspace_root, input.edits)
}

///|
/// A file's edits already validated and rendered, ready to write. Built only
/// after the whole batch has passed validation, so a write is the last step.
priv struct PreparedWrite {
  path : String
  new_content : String
  edit_count : Int
}

///|
/// Apply a validated batch across one or more files. Validation runs over every
/// file first; if any edit fails (or any file can't be read or is write-guarded)
/// nothing is written. Writes happen only once the entire batch is clean, which
/// keeps partial application limited to a raw filesystem write error.
async fn multi_edit_files(
  workspace_root : String,
  edits : Array[@decode.MultiEditItem],
) -> @agent_tool.ToolAction {
  let brief = "multi_edit"
  // A file's edits must form one contiguous block so each file is read,
  // validated, and written exactly once.
  match check_contiguity(edits) {
    Some(message) =>
      return @agent_tool.ToolAction::respond(message, is_error=true, brief~)
    None => ()
  }
  let groups = group_contiguous(edits)
  let failures : Array[EditFailure] = []
  let prepared : Array[(String, String, Array[PlannedEdit])] = []
  for group in groups {
    let path = @workspace_path.resolve(workspace_root, group.file)
    let content = @fs.read_file(path).text() catch {
      error if @async.is_being_cancelled() => raise error
      error => {
        failures.push({
          file: group.file,
          index: None,
          range: "",
          message: "error reading file: \{error}",
        })
        continue
      }
    }
    let plans : Array[PlannedEdit] = []
    for indexed in group.items {
      match validate_edit(content, indexed.item, indexed.index, file=group.file) {
        Valid(plan) => plans.push(plan)
        Invalid(failure) => failures.push(failure)
      }
    }
    collect_overlap_failures(group.file, plans, failures)
    prepared.push((group.file, content, plans))
  }
  if failures.length() > 0 {
    return @agent_tool.ToolAction::respond(
      failure_report(failures),
      is_error=true,
      brief~,
    )
  }
  // Render each file and run the write guard before touching disk, so a guarded
  // path aborts the whole batch instead of leaving earlier files written.
  let writes : Array[PreparedWrite] = []
  for entry in prepared {
    let (file, content, plans) = entry
    let path = @workspace_path.resolve(workspace_root, file)
    let new_content = apply_plans(content, plans)
    match @manifest_error.write_error(path, new_content) {
      Some(message) =>
        failures.push({ file, index: None, range: "", message })
      None => writes.push({ path, new_content, edit_count: plans.length() })
    }
  }
  if failures.length() > 0 {
    return @agent_tool.ToolAction::respond(
      failure_report(failures),
      is_error=true,
      brief~,
    )
  }
  for write in writes {
    @fs.write_file(write.path, write.new_content, create_mode=CreateOrTruncate) catch {
      error if @async.is_being_cancelled() => raise error
      error =>
        return @agent_tool.ToolAction::respond(
          "error multi_editing \{write.path}: error writing file: \{error}; earlier files in the batch may already be written",
          is_error=true,
          brief~,
        )
    }
  }
  let response = @auto_check.append_summary(writes[0].path, success_summary(writes))
  @agent_tool.ToolAction::respond(response, brief=success_brief(writes))
}

///|
/// Reject a batch where a file's edits are not contiguous: once a file's block
/// ends, that file must not reappear. Returns an error message, or `None` when
/// every file occupies a single run.
fn check_contiguity(edits : Array[@decode.MultiEditItem]) -> String? {
  let ended : Array[String] = []
  let mut current : String? = None
  for index, item in edits {
    let same = match current {
      Some(file) => file == item.file
      None => false
    }
    if !same {
      if ended.contains(item.file) {
        return Some(
          "error multi_editing: edits for \{item.file} must be contiguous; it reappears at edit[\{index}] after another file's edits; list all edits for a file together",
        )
      }
      match current {
        Some(file) => ended.push(file)
        None => ()
      }
      current = Some(item.file)
    }
  }
  None
}

///|
/// One decoded edit paired with its position in the original batch, so failures
/// can point the model back at `edit[index]`.
priv struct IndexedEdit {
  index : Int
  item : @decode.MultiEditItem
}

///|
/// A contiguous run of edits that all target the same file.
priv struct FileGroup {
  file : String
  items : Array[IndexedEdit]
}

///|
/// Group edits into per-file runs. Contiguity is already guaranteed by
/// `check_contiguity`, so a file extends only the most recent group.
fn group_contiguous(edits : Array[@decode.MultiEditItem]) -> Array[FileGroup] {
  let groups : Array[FileGroup] = []
  for index, item in edits {
    let count = groups.length()
    if count > 0 && groups[count - 1].file == item.file {
      groups[count - 1].items.push({ index, item })
    } else {
      groups.push({ file: item.file, items: [{ index, item }] })
    }
  }
  groups
}

///|
fn success_summary(writes : Array[PreparedWrite]) -> String {
  let mut total = 0
  for write in writes {
    total = total + write.edit_count
  }
  let lines = [ for write in writes => "\{write.path}: \{write.edit_count} edit(s)" ]
  "ok: applied \{total} edit(s) across \{writes.length()} file(s)\n\{lines.join("\n")}"
}

///|
fn success_brief(writes : Array[PreparedWrite]) -> String {
  let mut total = 0
  for write in writes {
    total = total + write.edit_count
  }
  if writes.length() == 1 {
    "multi_edit \{@agent_tool.brief_basename(writes[0].path)} (\{total}×)"
  } else {
    "multi_edit \{writes.length()} files (\{total}×)"
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
/// A rejected edit (or a file-level read/write-guard problem, when `index` is
/// `None`). `file` lets the report point at the right file in a multi-file batch.
priv struct EditFailure {
  file : String
  index : Int?
  range : String
  message : String
}

///|
fn validate_edit(
  content : String,
  item : @decode.MultiEditItem,
  index : Int,
  file~ : String,
) -> EditValidation {
  let range = line_range_label(item.start_line, item.end_line)
  if item.old_string == "" {
    // Insertion: an empty old_string inserts new_string at the start of
    // start_line (a zero-width edit). Use start_line = lastline + 1 to append at
    // end of file. end_line is ignored for insertion.
    if item.new_string == "" {
      return Invalid({
        file,
        index: Some(index),
        range,
        message: "old_string and new_string are both empty",
      })
    }
    let at = line_start_offset(content, item.start_line).clamp(
      min=0,
      max=content.length(),
    )
    return Valid({
      index,
      start: at,
      end: at,
      new_string: item.new_string,
      range,
    })
  }
  if item.old_string == item.new_string {
    return Invalid({
      file,
      index: Some(index),
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
    return Invalid({
      file,
      index: Some(index),
      range,
      message: "old_string not found",
    })
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
  file : String,
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
        file,
        index: Some(plan.index),
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
fn failure_report(failures : Array[EditFailure]) -> String {
  let lines = [ for failure in failures => format_failure(failure) ]
  "error multi_editing: \{failures.length()} edit(s) failed; no changes applied\n\{lines.join("\n")}"
}

///|
fn format_failure(failure : EditFailure) -> String {
  match failure.index {
    Some(index) =>
      "\{failure.file} edit[\{index}] \{failure.range}: \{failure.message}"
    None => "\{failure.file}: \{failure.message}"
  }
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
