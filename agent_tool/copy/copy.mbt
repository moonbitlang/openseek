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
    description="Copy a readable regular file from source to destination. Relative paths resolve from the workspace. Creates missing parent directories and publishes bytes atomically. Rejects MoonBit source and manifest destinations; use write or edit for those.",
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "source": { "type": "string", "description": "Source file." },
        "destination": { "type": "string", "description": "Destination file." },
      },
      "required": ["source", "destination"],
    }),
    program_callable=true,
    owns_file_access=true,
    can_request_approval=write_scope is Some(_) && approval is Some(_),
    execute=Async(arguments => {
      file_state.with_access(() => {
        execute_copy(
          workspace_root,
          file_state,
          arguments,
          write_scope?,
          approval?,
        )
      })
    }),
  )
}

///|
priv struct CopyInput {
  source : String
  destination : String
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
  { source, destination, }
}

///|
fn is_moonbit_managed(path : String) -> Bool {
  path.has_suffix(".mbt") ||
  path.has_suffix(".mbt.md") ||
  path.has_suffix(".mbtx") ||
  path.has_suffix(".mbti") ||
  @manifest_path.is_moon_mod_path(path) ||
  @manifest_path.is_moon_mod_json_path(path) ||
  @manifest_path.is_moon_pkg_path(path) ||
  @workspace_path.path_basename(path) is ("moon.work" | "moon.pkg.json")
}

///|
async fn copy_and_hash(
  source_path : String,
  destination : @fs.File,
) -> (Int64, String) {
  let source = @fs.open(source_path, mode=ReadOnly)
  defer source.close()
  guard source.kind() is Regular else {
    fail("source must name a regular file")
  }
  let buffer = FixedArray::make(65536, b'\x00')
  let reader = source.at(0L)
  let hasher = @crypto.SHA256::new()
  let mut size = 0L
  for ;; {
    let count = reader.read_into(buffer.mut_view())
    if count == 0 {
      break
    }
    let chunk = Bytes::from_array(buffer[:count])
    hasher.update(chunk)
    destination.write(chunk)
    size += count.to_int64()
  }
  (size, @crypto.bytes_to_hex_string(hasher.finalize()))
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
  copy_file(input, workspace_root, path, file_state, write_scope?, approval?) catch {
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
  workspace_root : String,
  path : String,
  file_state : @agent_tool.FileStateMap,
  write_scope? : @write_scope.WriteScope,
  approval? : @agent_runtime.ApprovalChannel,
) -> @agent_tool.ToolAction {
  let source_path = @workspace_path.resolve(workspace_root, input.source)
  guard @fs.kind(source_path) is Regular else {
    fail("source must name a regular file")
  }
  let existed = @fs.exists(path)
  let target = if existed { @fs.realpath(path) } else { path }
  guard !is_moonbit_managed(path) && !is_moonbit_managed(target) else {
    fail(
      "copy is for non-MoonBit artifacts; use write or edit for MoonBit source and manifest files",
    )
  }
  if existed {
    guard @fs.kind(target) is Regular && @fs.can_write(target) else {
      fail("copy can only replace writable regular files")
    }
  } else if (@fs.kind(path, follow_symlink=false) catch { _ => Unknown })
    is SymLink {
    fail("copy cannot write through a dangling symbolic link")
  }
  let basename = @path.Path(target).basename()
  guard !basename.is_empty() && target.has_suffix(basename) else {
    fail("copy requires a file destination")
  }
  let source_size = @fs.file_size(source_path)
  let write_scope = @permission.authorize(
    [path],
    target_path=path,
    tool_name="copy",
    arguments={
      "source": Json(input.source),
      "destination": Json(path),
      "bytes": Json::number(
        source_size.to_double(),
        repr=source_size.to_string(),
      ),
    },
    file_state~,
    write_scope?,
    approval?,
  )
  async fn recheck_target() {
    if write_scope is Some(scope) && scope.deny_reason(path) is Some(reason) {
      fail("copy blocked: \{reason}")
    }
    if @fs.exists(path) && (@fs.realpath(path) catch { _ => path }) != target {
      fail("file target changed before copying; re-read and retry")
    }
  }
  recheck_target()
  file_state.create_parent_directories(path)
  let mut copied : (Int64, String)? = None
  @atomic_file.write_atomic(
    target,
    file => {
      let stats = copy_and_hash(source_path, file)
      file.sync(only_data=true)
      copied = Some(stats)
    },
    replace=existed,
    permission=if existed { 0o600 } else { 0o644 },
    before_commit=recheck_target,
  )
  guard copied is Some((size, digest)) else {
    fail("copy did not transfer source bytes")
  }
  if existed {
    file_state.record_modified(path, digest)
  } else {
    file_state.record_created(path, digest)
  }
  let bytes = Json::number(size.to_double(), repr=size.to_string())
  let suffix = if existed { " (overwrote existing file)" } else { "" }
  @agent_tool.respond(
    "ok: copied \{size} bytes to \{path}\{suffix} (sha256: \{digest})",
    brief=@agent_tool.brief_line("copied \{size} bytes to \{input.destination}"),
    data={ "bytes": bytes, "sha256": digest },
  )
}
