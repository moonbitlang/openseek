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
priv struct NodeVersion {
  location : String
  contents : NodeContents
}

///|
#derive(Eq)
priv enum NodeContents {
  File(String)
  Directory
  Symlink(Bytes)
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
    let target = inspect_node(path)
    let directory = target.contents is Directory
    let reason = match target.contents {
      Directory => {
        if @workspace_path.is_under_workspace_root(
            target.location,
            @fs.realpath(workspace_root),
          ) {
          return removal_error(
            path, "cannot remove the workspace root or its ancestors",
          )
        }
        let entries = directory_entries(path)
        if remove_owned_directory(
            path,
            target,
            entries,
            file_state,
            write_scope?,
          ) {
          return removed(path, input.reason, directory~)
        }
        let files = entries.count_if(e => e.1 is Regular)
        let links = entries.count_if(e => e.1 is SymLink)
        let link_summary = if links == 0 {
          ""
        } else {
          ", \{links} symbolic links"
        }
        Some(
          "recursive directory deletion: \{files} files\{link_summary} and \{entries.length() - 1 - files - links} subdirectories; all contents present at deletion will be removed",
        )
      }
      Symlink(_) => Some("unlink symbolic link")
      File(digest) => {
        if input.path.has_suffix("/") ||
          input.path.has_suffix(@path.sep.to_string()) {
          return removal_error(path, "not a directory")
        }
        if file_state.created_and_unchanged(path, digest) {
          None
        } else if file_state.get(path) is Some(Created) {
          Some("the file's content has changed since the agent last wrote it")
        } else {
          Some("the file is not recorded as created by the agent this session")
        }
      }
    }
    let _ = @permission.authorize(
      RemoveEntry(path, location=target.location),
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
      @fs.remove(target.location, recursive=true)
    } else {
      @fs.remove(
        if target.contents is Symlink(_) {
          target.location
        } else {
          path
        },
      )
      file_state.forget(path)
      file_state.forget_directory(path)
    }
    removed(path, input.reason, directory~)
  }) catch {
    error => removal_error(path, @tool_error.failure_message("\{error}"))
  }
}

///|
async fn inspect_node(path : String) -> NodeVersion {
  let kind = @fs.kind(path, follow_symlink=false) catch {
    @os_error.OsError(NotFound, ..) => fail("no such file")
    err => raise err
  }
  match kind {
    SymLink => {
      let entry = @path.Path(path)
      let parent = @fs.realpath(entry.dirname().to_string())
      let location = @path.Path(parent)
        .join(Path(entry.basename().to_owned()))
        .to_string()
      { location, contents: Symlink(read_link_target(location)), }
    }
    Directory => { location: @fs.realpath(path), contents: Directory, }
    Regular => {
      let location = @fs.realpath(path)
      let digest = @crypto.bytes_to_hex_string(
        @crypto.sha256(@fs.read_binary(path)),
      )
      { location, contents: File(digest), }
    }
    _ => fail("cannot remove special files")
  }
}

///|
/// List children before parents for the approval preview and automatic deletion.
async fn directory_entries(root : String) -> Array[(String, @fs.FileKind)] {
  let entries = []
  async fn visit(path : String) -> Unit {
    for name in @fs.readdir(path, include_hidden=true) {
      let child = if @path.sep == '/' {
        @workspace_path.join_child(path, name)
      } else {
        @workspace_path.join_child_preserving_separator(path, name)
      }
      let kind = @fs.kind(child, follow_symlink=false)
      match kind {
        Directory => visit(child)
        Regular | SymLink => entries.push((child, kind))
        _ => fail("cannot remove special files")
      }
    }
    entries.push((path, Directory))
  }
  visit(root)
  entries
}

///|
/// Without approval only remove the checked entries. Non-recursive rmdir
/// preserves anything that appears after the ownership check.
async fn remove_owned_directory(
  path : String,
  root : NodeVersion,
  entries : Array[(String, @fs.FileKind)],
  file_state : @agent_tool.FileStateMap,
  write_scope? : @write_scope.WriteScope,
) -> Bool {
  if entries.length() > 1 && !file_state.created_directory(path) {
    return false
  }
  let owned = []
  for (entry, kind) in entries {
    match kind {
      Directory if entries.length() == 1 || file_state.created_directory(entry) =>
        ()
      Regular if file_state.get(entry) is Some(Created) => ()
      _ => return false
    }
    let node = if entry == path { root } else { inspect_node(entry) }
    match (kind, node.contents) {
      (Directory, Directory) => ()
      (Regular, File(digest)) if file_state.created_and_unchanged(entry, digest) =>
        ()
      _ => return false
    }
    if write_scope is Some(scope) &&
      scope.check_entry(entry, node.location) is Some(_) {
      return false
    }
    owned.push((entry, node))
  }
  guard inspect_node(path) == root else {
    fail("directory location changed before deletion")
  }
  for (entry, expected) in owned {
    guard inspect_node(entry) == expected else {
      fail(
        "directory changed during automatic deletion; remaining entries were kept",
      )
    }
    @fs.remove(entry)
    file_state.forget(entry)
    file_state.forget_directory(entry)
  }
  true
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
