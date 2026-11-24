///|
/// The program-only tool for atomically publishing a readable regular file.
pub fn definition(
  workspace_root~ : String = ".",
  file_state~ : @agent_tool.FileStateMap = FileStateMap(),
  write_scope? : @write_scope.WriteScope,
  approval? : @agent_runtime.ApprovalChannel,
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="copy",
    description="Copy a readable regular file from source to destination. Keep the source unchanged until the call completes. Relative paths resolve from the workspace. Creates missing parent directories and publishes the bytes atomically after destination validation.",
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "source": { "type": "string", "description": "Source file." },
        "destination": { "type": "string", "description": "Destination file." },
        "revert_on_parse_errors": {
          "type": "boolean",
          "description": "Check MoonBit syntax before publishing. Defaults to true.",
        },
      },
      "required": ["source", "destination"],
    }),
    program_callable=true,
    // Preparation can overlap with other PTC calls. The shared file gate
    // still protects target checks, publication, and provenance changes.
    concurrent_safe=true,
    owns_file_access=true,
    can_request_approval=write_scope is Some(_) && approval is Some(_),
    execute=Async(arguments => {
      execute_copy(
        workspace_root,
        file_state,
        arguments,
        write_scope?,
        approval?,
      )
    }),
  )
}

///|
priv struct CopyInput {
  source : String
  destination : String
  revert_on_parse_errors : Bool
}

///|
fn decode(arguments : Json) -> CopyInput raise {
  guard arguments is Object(fields) else { fail("object arguments") }
  guard fields.get("source") is Some(String(source)) && !source.is_empty() else {
    fail("arguments.source to be a non-empty string")
  }
  guard fields.get("destination") is Some(String(destination)) &&
    !destination.is_empty() else {
    fail("arguments.destination to be a non-empty string")
  }
  guard !source.contains("\u{0}") && !destination.contains("\u{0}") else {
    fail("arguments.source and arguments.destination to contain no NUL")
  }
  guard !fields.contains("content") && !fields.contains("encoding") else {
    fail("file paths without arguments.content or arguments.encoding")
  }
  let revert_on_parse_errors = match arguments {
    { "revert_on_parse_errors": false, .. } => false
    { "revert_on_parse_errors": true, .. }
    | { "revert_on_parse_errors": Null, .. } => true
    { "revert_on_parse_errors": _, .. } =>
      fail("arguments.revert_on_parse_errors to be a boolean")
    _ => true
  }
  { source, destination, revert_on_parse_errors, }
}

///|
async fn execute_copy(
  workspace_root : String,
  file_state : @agent_tool.FileStateMap,
  arguments : Json,
  write_scope? : @write_scope.WriteScope,
  approval? : @agent_runtime.ApprovalChannel,
) -> @agent_tool.ToolAction {
  let input = decode(arguments) catch {
    error => {
      let message = @tool_error.failure_message("\{error}")
      return @agent_tool.respond(
        "error: copy requires \{message}",
        is_error=true,
      )
    }
  }
  let path = @workspace_path.resolve(workspace_root, input.destination)
  try {
    let source_path = @workspace_path.resolve(workspace_root, input.source)
    guard @fs.kind(source_path) is Regular else {
      fail("source must name a regular file")
    }
    let destination = inspect_destination(path)
    copy_file(
      input,
      source_path,
      path,
      destination,
      file_state,
      write_scope?,
      approval?,
    )
  } catch {
    error => {
      let message = @tool_error.failure_message("\{error}")
      @agent_tool.respond(
        "error copying to \{path}: \{message}",
        is_error=true,
        brief="copy \{@agent_tool.brief_basename(path)}",
      )
    }
  }
}

///|
async fn copy_file(
  input : CopyInput,
  source_path : String,
  path : String,
  destination : CopyDestination,
  file_state : @agent_tool.FileStateMap,
  write_scope? : @write_scope.WriteScope,
  approval? : @agent_runtime.ApprovalChannel,
) -> @agent_tool.ToolAction {
  let target = destination.resolved_path
  let paths = if path == target { [path] } else { [path, target] }
  for checked_path in paths {
    if @manifest_error.path_error(checked_path) is Some(message) {
      fail(message)
    }
  }
  let text = paths.any(requires_text)
  if text && @manifest_error.file_error(paths, source_path) is Some(message) {
    fail(message)
  }

  let checks = if input.revert_on_parse_errors {
    @auto_check.gate_paths(path, target).filter_map(
      @auto_check.gate_scratch_name,
    )
  } else {
    []
  }
  let source_kind = @auto_check.gate_scratch_name(source_path)
  if source_kind is Some(name) &&
    checks.contains(name) &&
    syntax_rejection(source_path, path) is Some(result) {
    return result
  }
  let remaining_checks = checks.filter(name => Some(name) != source_kind)

  let dir = @path.Path(destination.staging_parent)
    .join(Path(".openseek-copy-\{@uuid.v7()}"))
    .to_string()
  @async.protect_from_cancel(() => @fs.mkdir(dir, permission=0o700))
  defer (@fs.remove(dir, recursive=true) catch { _ => () })
  let first_name = remaining_checks.get(0).unwrap_or("candidate")
  let mut staged = @path.Path(dir).join(Path(first_name)).to_string()
  let (size, digest) = {
    let source = @fs.open(source_path, mode=ReadOnly)
    defer source.close()
    let file = @fs.open(
      staged,
      mode=WriteOnly,
      create_mode=CreateNew,
      permission=if destination.existed { 0o600 } else { 0o644 },
    )
    defer file.close()
    let result = @file_content.transfer(source, destination=file)
    file.sync(only_data=true)
    result
  }
  // syncheck infers the kind from the input name. Rename inside the private
  // directory if the requested path and its target need different kinds.
  for name in remaining_checks {
    let checked_file = @path.Path(dir).join(Path(name)).to_string()
    if staged != checked_file {
      @fs.rename(staged, checked_file, replace=false)
      staged = checked_file
    }
    if syntax_rejection(staged, path) is Some(result) {
      return result
    }
  }

  let bytes = Json::number(size.to_double(), repr=size.to_string())
  let arguments : Map[String, Json] = {
    "destination": Json(path),
    "source": Json(input.source),
    "bytes": bytes,
    "sha256": Json(digest),
  }
  // Inline small text for scoped approval. Large files can be reviewed by
  // path, size and digest without materializing their entire contents.
  if text &&
    write_scope is Some(_) &&
    approval is Some(_) &&
    size <= CopyApprovalPreviewBytes {
    arguments["content"] = Json(@utf8.decode(@fs.read_binary(staged)))
  } else {
    arguments["content_omitted"] = Json(true)
  }
  file_state.with_access(() => {
    recheck_destination(path, destination)
    let authorization = @permission.authorize(
      [path],
      target_path=path,
      tool_name="copy",
      arguments=Json::object(arguments),
      file_state~,
      write_scope?,
      approval?,
      check_contents=false,
    )
    authorization.recheck()
    recheck_destination(path, destination)
    if authorization.deny_reason(path) is Some(reason) {
      fail("copy blocked: \{reason}")
    }
    file_state.create_parent_directories(path)
    recheck_destination(path, destination)
    @atomic_file.publish_staged_file(
      staged,
      target,
      replace=destination.existed,
    )
    if destination.existed {
      file_state.record_modified(path, digest)
    } else {
      file_state.record_created(path, digest)
    }
  })
  let suffix = if destination.existed {
    " (overwrote existing file)"
  } else {
    ""
  }
  @agent_tool.respond(
    @auto_check.append_summary(
      path,
      "ok: copied \{size} bytes to \{path}\{suffix} (sha256: \{digest})",
    ),
    brief=@agent_tool.brief_line("copied \{size} bytes to \{input.destination}"),
    data={ "bytes": bytes, "sha256": digest },
  )
}

///|
const CopyApprovalPreviewBytes : Int64 = 65536L

///|
async fn syntax_rejection(
  source : String,
  destination : String,
) -> @agent_tool.ToolAction? {
  guard @auto_check.file_parse_errors(source) is Some(gate) &&
    !gate.errors.is_empty() else {
    return None
  }
  // Use the compiler's excerpts without reading the input back into memory.
  let details = @auto_check.format_parse_gate_errors(
    destination,
    "",
    gate.errors,
  )
  Some(
    @agent_tool.respond(
      "rejected: the content for \{destination} has parse errors; nothing was written.\n\{details.join("\n")}",
      is_error=true,
      brief="copy rejected (parse errors)",
    ),
  )
}
