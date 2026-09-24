///|
/// Remove unchanged files created by this session automatically. Other regular
/// files require a one-shot approval for their current location and contents.
/// This definition owns its file-state locking; do not wrap it in `serialize`.
pub fn definition(
  workspace_root? : String = ".",
  file_state? : @agent_tool.FileStateMap = FileStateMap(),
  write_scope? : @write_scope.WriteScope,
  approval? : @agent_runtime.ApprovalChannel,
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="remove",
    description=(
      #|Delete a regular file, with a non-empty reason recorded in the result.
      #|Unchanged files created by this session are removed automatically. Other
      #|files require approval through the session's permission channel. If approval
      #|is unavailable, rejected, or cancelled, the file is kept. Approval applies
      #|only to this deletion; a file changed while waiting must be reconsidered
      #|and approved again. Directories, symlinks, and paths outside the worker's
      #|write scope are refused without asking. Do not bypass a refusal with mbtx.
      #|Deleting .mbt/.mbt.md also runs moon check and reports its feedback.
    ),
    schema=JsonSchema({
      "type": "object",
      "properties": {
        "path": { "type": "string" },
        "reason": {
          "type": "string",
          "description": (
            #|A short, non-empty explanation of why this file is being deleted, recorded
            #|in the result so a destructive action can be audited later. A blank reason
            #|is rejected.
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
priv enum Removal {
  Finished(@agent_tool.ToolAction)
  NeedsApproval(FileVersion, String)
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
  try {
    let decision = file_state.with_access(() => {
      let version = inspect_file(path, write_scope?)
      if file_state.created_and_unchanged(path, version.digest) {
        Finished(delete_file(path, input.reason, file_state, write_scope?))
      } else {
        let why = if file_state.get(path) is Some(Created) {
          "the file's content has changed since the agent last wrote it"
        } else {
          "the file is not recorded as created by the agent this session"
        }
        NeedsApproval(version, why)
      }
    })
    let (version, why) = match decision {
      Finished(result) => return result
      NeedsApproval(version, why) => (version, why)
    }
    guard approval is Some(channel) else {
      return removal_error(
        path,
        "\{why}; deletion requires approval, but this session has no approval channel",
      )
    }
    // Human-paced IO must not occupy the shared file-operation gate. The
    // original version, not a fresh approval for whatever is there, is retained.
    let body : Json = { "path": path, "reason": input.reason }
    let outcome = channel.ask({
      tool_name: "remove",
      detail: "delete this one file: \{why}. This grants no other deletions or sandbox changes.",
      body: Some(body.stringify()),
    })
    match outcome {
      AllowedOnce =>
        file_state.with_access(() => {
          let current = inspect_file(path, write_scope?)
          guard current == version else {
            return removal_error(
              path, "file changed while awaiting approval; deletion refused. Reconsider and request approval again",
            )
          }
          delete_file(path, input.reason, file_state, write_scope?)
        })
      Rejected =>
        removal_error(
          path, "deletion approval rejected; file kept. Do not retry without new user instructions",
        )
      Cancelled => removal_error(path, "deletion approval cancelled; file kept")
      Unavailable =>
        removal_error(path, "deletion approval unavailable; file kept")
    }
  } catch {
    error => removal_error(path, @tool_error.failure_message("\{error}"))
  }
}

///|
/// Approval never overrides scope or file-kind restrictions. Hash raw bytes so
/// binary files can be approved without decoding them as text.
async fn inspect_file(
  path : String,
  write_scope? : @write_scope.WriteScope,
) -> FileVersion {
  if write_scope is Some(scope) && scope.deny_reason(path) is Some(reason) {
    fail("write blocked: \{reason}")
  }
  guard @fs.exists(path) else { fail("no such file") }
  guard @fs.kind(path, follow_symlink=false) is Regular else {
    fail("not a regular file; remove deletes regular files")
  }
  let canonical = @fs.realpath(path)
  let bytes = @fs.read_file(path).binary()
  { canonical, digest: @crypto.bytes_to_hex_string(@crypto.sha256(bytes)), }
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
