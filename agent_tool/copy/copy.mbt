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
    description="Copy a readable regular file from source to destination. Relative paths resolve from the workspace. Creates missing parent directories and publishes the bytes atomically after destination validation.",
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
    let directory = @fs.tmpdir(prefix="openseek-copy-")
    defer (@fs.remove(directory, recursive=true) catch { _ => () })
    let file = @fs.open(
      "\{directory}/candidate",
      mode=ReadWrite,
      create_mode=CreateNew,
      permission=0o600,
    )
    defer file.close()
    let (bytes, digest) = {
      let source = @fs.open(source_path, mode=ReadOnly)
      defer source.close()
      @file_content.transfer(source, destination=file)
    }
    let candidate = { file, bytes, digest, }
    file_state.with_access(() => {
      commit_copy(input, candidate, path, file_state, write_scope?, approval?)
    })
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
async fn commit_copy(
  input : CopyInput,
  candidate : StagedFile,
  path : String,
  file_state : @agent_tool.FileStateMap,
  write_scope? : @write_scope.WriteScope,
  approval? : @agent_runtime.ApprovalChannel,
) -> @agent_tool.ToolAction {
  let target = @fs.realpath(path) catch { _ => path }
  let text = if requires_text(path) || requires_text(target) {
    let bytes = candidate.file.read_all()
    Some(
      @utf8.decode(bytes, ignore_bom=false) catch {
        _ => fail("source and manifest content must be valid UTF-8")
      },
    )
  } else {
    None
  }
  if text is Some(content) {
    for checked_path in (if path == target { [path] } else { [path, target] }) {
      if @manifest_error.write_error(checked_path, content) is Some(message) {
        fail(message)
      }
    }
  }
  let existed = @fs.exists(path)
  guard !(existed && (is_mbt_source(path) || is_mbt_source(target))) else {
    fail("cannot overwrite an existing source file; use edit or multi_edit")
  }
  if input.revert_on_parse_errors &&
    text is Some(content) &&
    @auto_check.write_parse_error(path, target, content) is Some(gate) {
    let details = @auto_check.format_parse_gate_errors(
      path,
      content,
      gate.errors,
    )
    return @agent_tool.respond(
      "rejected: the content for \{path} has parse errors; nothing was written.\n\{details.join("\n")}",
      is_error=true,
      brief="copy rejected (parse errors)",
    )
  }
  let bytes = Json::number(
    candidate.bytes.to_double(),
    repr=candidate.bytes.to_string(),
  )
  let arguments : Map[String, Json] = {
    "destination": Json(path),
    "source": Json(input.source),
    "bytes": bytes,
    "sha256": Json(candidate.digest),
  }
  if text is Some(content) {
    arguments["content"] = Json(content)
  } else {
    arguments["content_omitted"] = Json(true)
  }
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
  if @fs.exists(path) && (@fs.realpath(path) catch { _ => path }) != target {
    authorization.recheck()
    fail("file target changed before copying; re-read and retry")
  }
  if authorization.deny_reason(path) is Some(reason) {
    fail("copy blocked: \{reason}")
  }
  file_state.create_parent_directories(path)
  publish_file(candidate, path, target, existed, authorization, file_state)
  if existed {
    file_state.record_modified(path, candidate.digest)
  } else {
    file_state.record_created(path, candidate.digest)
  }
  let suffix = if existed { " (overwrote existing file)" } else { "" }
  @agent_tool.respond(
    @auto_check.append_summary(
      path,
      "ok: copied \{candidate.bytes} bytes to \{path}\{suffix} (sha256: \{candidate.digest})",
    ),
    brief=@agent_tool.brief_line(
      "copied \{candidate.bytes} bytes to \{input.destination}",
    ),
    data={ "bytes": bytes, "sha256": candidate.digest },
  )
}
