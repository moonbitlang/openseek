///|
/// Remove unchanged session-created files and empty directories automatically.
/// Other targets require one-shot approval for their location and contents.
/// This definition owns its file-state locking; do not wrap it in `serialize`.
pub fn definition(
  workspace_root? : String = ".",
  file_state? : @agent_tool.FileStateMap = FileStateMap(),
  write_scope? : @write_scope.WriteScope,
  approval? : @agent_runtime.ApprovalChannel,
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="remove",
    program_callable=true,
    owns_file_access=true,
    can_request_approval=approval is Some(_),
    description=(
      #|Delete a file or recursively delete a directory, with a non-empty reason.
      #|Unchanged session-created files and empty directories are removed automatically.
      #|Other files and nonempty directories require approval through the permission channel.
      #|If approval is unavailable, rejected, or cancelled, the target is kept.
      #|A file or tree changed while waiting must be reconsidered
      #|and approved again. Directory approval covers the whole captured tree.
      #|Workspace roots and their ancestors, symlinks (including inside a tree),
      #|and special files are refused. Valid paths outside the write scope require
      #|approval for this deletion only.
      #|Do not bypass a refusal with mbtx.
      #|Deleting .mbt/.mbt.md also runs moon check and reports its feedback.
    ),
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "path": { "type": "string" },
        "reason": {
          "type": "string",
          "description": (
            #|A short, non-empty explanation of why this file or directory is being
            #|deleted, recorded in the result for auditing. A blank reason is rejected.
          ),
        },
      },
      "required": ["path", "reason"],
    }),
    execute=Async(arguments => {
      execute_with_workspace(
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
priv struct FileVersion {
  canonical : String
  digest : String
} derive(Eq)

///|
priv enum NodeVersion {
  File(FileVersion)
  Directory(String)
} derive(Eq)

///|
priv struct RemovalVersion {
  // Postorder: children precede their directory, and the target is last.
  entries : Array[(String, NodeVersion)]
} derive(Eq)

///|
fn removal_error(path : String, message : String) -> @agent_tool.ToolAction {
  @agent_tool.respond(
    "error removing \{path}: \{message}",
    is_error=true,
    brief="remove \{@agent_tool.brief_basename(path)}",
  )
}

///|
async fn execute_with_workspace(
  workspace_root : String,
  file_state : @agent_tool.FileStateMap,
  arguments : Json,
  write_scope? : @write_scope.WriteScope,
  approval? : @agent_runtime.ApprovalChannel,
) -> @agent_tool.ToolAction {
  let input = @decode.decode(arguments) catch {
    error => {
      let message = @tool_error.failure_message("\{error}")
      return @agent_tool.respond(
        "error: remove requires \{message}",
        is_error=true,
      )
    }
  }
  let path = @workspace_path.resolve(workspace_root, input.path)
  file_state.with_access(() => {
    let version = inspect_target(path, workspace_root)
    let reason = match version.entries {
      [(_, File(file))] if file_state.created_and_unchanged(path, file.digest) =>
        None
      [(_, Directory(_))] => None
      _ =>
        Some(
          if version.entries.last() is Some((_, Directory(_))) {
            let files = version.entries
              .filter(entry => entry.1 is File(_))
              .length()
            "recursive directory deletion: \{files} files and \{version.entries.length() - files - 1} subdirectories; all contents will be removed"
          } else if file_state.get(path) is Some(Created) {
            "the file's content has changed since the agent last wrote it"
          } else {
            "the file is not recorded as created by the agent this session"
          },
        )
    }
    let write_scope = @permission.authorize(
      version.entries.map(entry => entry.0),
      tool_name="remove",
      arguments={ "path": path, "reason": input.reason },
      file_state~,
      write_scope?,
      approval?,
      reason?,
    )
    guard inspect_target(path, workspace_root, write_scope?) == version else {
      return removal_error(
        path, "file or directory changed while awaiting approval; deletion refused. Reconsider and request approval again",
      )
    }
    if version.entries.last() is Some((_, Directory(_))) {
      delete_directory(path, input.reason, version, file_state, write_scope?)
    } else {
      delete_file(path, input.reason, file_state, write_scope?)
    }
  }) catch {
    error => removal_error(path, @tool_error.failure_message("\{error}"))
  }
}

///|
/// Approval never overrides scope or kind restrictions. Hash complete raw bytes.
async fn inspect_node(
  path : String,
  write_scope? : @write_scope.WriteScope,
) -> NodeVersion {
  if write_scope is Some(scope) && scope.deny_reason(path) is Some(reason) {
    fail("write blocked: \{reason}")
  }
  guard @fs.exists(path) else { fail("no such file") }
  match @fs.kind(path, follow_symlink=false) {
    Regular => {
      let canonical = @fs.realpath(path)
      let bytes = @fs.read_file(path).binary()
      File({
        canonical,
        digest: @crypto.bytes_to_hex_string(@crypto.sha256(bytes)),
      })
    }
    Directory => Directory(@fs.realpath(path))
    _ =>
      fail(
        "not a regular file or directory; symlinks and special files cannot be removed",
      )
  }
}

///|
async fn inspect_target(
  path : String,
  workspace_root : String,
  write_scope? : @write_scope.WriteScope,
) -> RemovalVersion {
  let entries = []
  let root = @fs.realpath(workspace_root)
  async fn visit(path : String) -> Unit {
    let node = inspect_node(path, write_scope?)
    if node is Directory(canonical) {
      // This also protects filesystem roots and aliases of workspace ancestors.
      if @workspace_path.is_under_workspace_root(canonical, root) {
        fail("cannot remove the workspace root or its ancestors")
      }
      for name in @fs.readdir(path, include_hidden=true, sort=true) {
        visit(@workspace_path.join_child(path, name))
      }
    }
    entries.push((path, node))
  }
  visit(path)
  { entries, }
}

///|
async fn delete_directory(
  path : String,
  reason : String,
  version : RemovalVersion,
  file_state : @agent_tool.FileStateMap,
  write_scope? : @write_scope.WriteScope,
) -> @agent_tool.ToolAction {
  // Delete only the reviewed entries. Never use recursive rmdir, which could
  // silently include new files added by an external writer after the recheck.
  for (entry, expected) in version.entries {
    guard inspect_node(entry, write_scope?) == expected else {
      fail("directory changed during deletion; remaining entries were kept")
    }
    match expected {
      File(_) => @fs.remove(entry)
      Directory(_) => @fs.rmdir(entry)
    }
    file_state.forget(entry)
  }
  @agent_tool.respond(
    "ok: recursively removed \{path} (reason: \{reason})",
    brief=@agent_tool.brief_line("removed \{path}"),
  )
}

///|
async fn delete_file(
  path : String,
  reason : String,
  file_state : @agent_tool.FileStateMap,
  write_scope? : @write_scope.WriteScope,
) -> @agent_tool.ToolAction {
  if write_scope is Some(scope) && scope.deny_reason(path) is Some(why) {
    return removal_error(path, "write blocked: \{why}")
  }
  @fs.remove(path)
  file_state.forget(path)
  let summary = "ok: removed \{path} (reason: \{reason})"
  @agent_tool.respond(
    @auto_check.append_summary(path, summary),
    brief=@agent_tool.brief_line("removed \{path}"),
  )
}
