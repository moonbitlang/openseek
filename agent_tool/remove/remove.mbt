///|
/// Remove unchanged session-created files and empty directories automatically.
/// Other targets require one-shot approval for their location and contents.
/// This definition owns its file-state locking; do not wrap it in `serialize`.
pub fn definition(
  workspace_root~ : String = ".",
  file_state~ : @agent_tool.FileStateMap = FileStateMap(),
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
      #|Symbolic links, other files and nonempty directories require approval through the permission channel.
      #|If approval is unavailable, rejected, or cancelled, the target is kept.
      #|Directory approval covers all contents present when deletion runs, including new entries.
      #|Unlink symbolic links themselves, including dangling links and links inside a tree.
      #|Workspace roots, their ancestors, and special files are refused.
      #|Valid paths outside the write scope require approval for this deletion only.
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
#derive(Eq)
priv struct FileVersion {
  canonical : String
  digest : String?
}

///|
#derive(Eq)
priv enum NodeVersion {
  File(FileVersion)
  Directory(String)
  Symlink(String)
}

///|
#derive(Eq)
priv struct RemovalVersion {
  // Postorder: children precede their directory, and the target is last.
  entries : Array[(String, NodeVersion)]
}

///|
fn NodeVersion::location(self : NodeVersion) -> String {
  match self {
    File(file) => file.canonical
    Directory(location) | Symlink(location) => location
  }
}

///|
fn removal_error(path : String, message : String) -> @agent_tool.ToolAction {
  @agent_tool.respond(
    "error removing \{path}: \{message}",
    is_error=true,
    brief="remove \{@agent_tool.brief_basename(path)}",
  )
}

///|
fn removal_path(workspace_root : String, input : String) -> String raise {
  let name = @path.Path(input).basename()
  if name is ("." | "..") {
    fail("cannot remove . or ..")
  }
  guard !name.is_empty() else {
    return @workspace_path.resolve(workspace_root, input)
  }
  // Strip trailing separators before lstat, but let the kernel interpret an
  // intermediate ".." since its predecessor can be a directory symlink.
  let separator = @path.sep.to_string()
  let path = input.trim_end(chars="/" + separator).to_owned()
  let components = path.replace_all(old=separator, new="/").split("/")
  if !@path.Path(path).is_absolute() && components.any(part => part == "..") {
    @workspace_path.join_child(workspace_root, path)
  } else {
    @workspace_path.resolve(workspace_root, path)
  }
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
  let path = removal_path(workspace_root, input.path) catch {
    error =>
      return removal_error(input.path, @tool_error.failure_message("\{error}"))
  }
  file_state.with_access(() => {
    let version = inspect_target(path, workspace_root, file_state)
    let (_, target) = version.entries[version.entries.length() - 1]
    let directory = target is Directory(_)
    let reason = match target {
      Directory(_) => {
        let automatic = version.entries.length() == 1 ||
          created_directory_tree(version, file_state)
        if automatic &&
          !(write_scope is Some(scope) &&
          version.entries.any(entry => {
            scope.check_entry(entry.0, entry.1.location()) is Some(_)
          })) {
          guard inspect_target(path, workspace_root, file_state, write_scope?) ==
            version else {
            return removal_error(path, "directory changed before deletion")
          }
          return delete_directory(
            path,
            input.reason,
            version,
            file_state,
            write_scope?,
          )
        }
        let files = version.entries.count_if(entry => !(entry.1 is Directory(_)))
        Some(
          "recursive directory deletion: \{files} files and \{version.entries.length() - files - 1} subdirectories; all contents present at deletion will be removed",
        )
      }
      Symlink(_) => Some("unlink symbolic link")
      File(file) => {
        if input.path.has_suffix("/") ||
          input.path.has_suffix(@path.sep.to_string()) {
          return removal_error(path, "not a directory")
        }
        if file.digest is Some(digest) &&
          file_state.created_and_unchanged(path, digest) {
          None
        } else if file_state.get(path) is Some(Created) {
          Some("the file's content has changed since the agent last wrote it")
        } else {
          Some("the file is not recorded as created by the agent this session")
        }
      }
    }
    let _ = @permission.authorize(
      RemoveEntry(path, location=target.location()),
      tool_name="remove",
      arguments={ "path": path, "reason": input.reason },
      file_state~,
      write_scope?,
      approval?,
      reason?,
    )
    guard inspect_node(path) == target else {
      return removal_error(
        path, "target changed while awaiting approval; reconsider and request approval again",
      )
    }
    if directory {
      // Recursive removal can partially succeed. Drop stale creation records
      // even if a later filesystem operation fails.
      file_state.forget_tree(path)
      @fs.remove(target.location(), recursive=true)
    } else {
      @fs.remove(if target is Symlink(location) { location } else { path })
      file_state.forget(path)
      file_state.forget_directory(path)
    }
    removed(path, input.reason, directory~)
  }) catch {
    error => removal_error(path, @tool_error.failure_message("\{error}"))
  }
}

///|
/// A non-empty tree can bypass approval only when every entry was created by
/// this session and every regular file still has the content recorded for it.
/// Directory provenance matters separately: a pre-existing empty directory
/// that happens to contain only agent-created files is still user-owned.
fn created_directory_tree(
  version : RemovalVersion,
  file_state : @agent_tool.FileStateMap,
) -> Bool {
  version.entries.all(entry => {
    match entry {
      (path, File(file)) =>
        file.digest is Some(digest) &&
        file_state.created_and_unchanged(path, digest)
      (_, Symlink(_)) => false
      (path, Directory(_)) => file_state.created_directory(path)
    }
  })
}

///|
/// Inspect the entry itself. A file digest, when requested, covers its raw bytes.
async fn inspect_node(
  path : String,
  hash_file~ : Bool = true,
  write_scope? : @write_scope.WriteScope,
) -> NodeVersion {
  let kind = @fs.kind(path, follow_symlink=false) catch {
    @os_error.OsError(NotFound, ..) => fail("no such file")
    err => raise err
  }
  let node = match kind {
    SymLink => {
      let entry = @path.Path(path)
      let parent = @fs.realpath(entry.dirname().to_string())
      Symlink(
        @path.Path(parent).join(Path(entry.basename().to_owned())).to_string(),
      )
    }
    Directory => Directory(@fs.realpath(path))
    Regular => {
      let canonical = @fs.realpath(path)
      let digest = if hash_file {
        Some(@crypto.bytes_to_hex_string(@crypto.sha256(@fs.read_binary(path))))
      } else {
        None
      }
      File({ canonical, digest, })
    }
    _ => fail("cannot remove special files")
  }
  if write_scope is Some(scope) &&
    scope.check_entry(path, node.location()) is Some(reason) {
    fail("write blocked: \{reason}")
  }
  node
}

///|
async fn inspect_target(
  target_path : String,
  workspace_root : String,
  file_state : @agent_tool.FileStateMap,
  write_scope? : @write_scope.WriteScope,
) -> RemovalVersion {
  let entries = []
  let root = @fs.realpath(workspace_root)
  let may_own_tree = file_state.created_directory(target_path)
  async fn visit(path : String) -> Unit {
    // The preview needs only entry kinds. Hash contents for direct files and
    // for files eligible for automatic deletion.
    let node = inspect_node(
      path,
      hash_file=path == target_path ||
        (may_own_tree && file_state.get(path) is Some(Created)),
      write_scope?,
    )
    if node is Directory(canonical) {
      // This also protects filesystem roots and aliases of workspace ancestors.
      if @workspace_path.is_under_workspace_root(canonical, root) {
        fail("cannot remove the workspace root or its ancestors")
      }
      for name in @fs.readdir(path, include_hidden=true, sort=true) {
        visit(
          if @path.sep == '/' {
            @workspace_path.join_child(path, name)
          } else {
            @workspace_path.join_child_preserving_separator(path, name)
          },
        )
      }
    }
    entries.push((path, node))
  }
  visit(target_path)
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
      File(_) | Symlink(_) => {
        @fs.remove(entry)
        file_state.forget(entry)
      }
      Directory(_) => {
        @fs.remove(entry)
        file_state.forget_directory(entry)
      }
    }
  }
  @agent_tool.respond(
    "ok: recursively removed \{path} (reason: \{reason})",
    brief=@agent_tool.brief_line("removed \{path}"),
  )
}

///|
async fn removed(
  path : String,
  reason : String,
  directory~ : Bool,
) -> @agent_tool.ToolAction {
  let summary = if directory {
    "ok: recursively removed \{path} (reason: \{reason})"
  } else {
    @auto_check.append_summary(path, "ok: removed \{path} (reason: \{reason})")
  }
  @agent_tool.respond(summary, brief=@agent_tool.brief_line("removed \{path}"))
}
