///|
/// Tool definition for `remove`: delete a file the agent created earlier this
/// session, with a required rationale recorded for auditing.
///
/// This fills the one gap in the tool-mediated file API — `write`/`edit`
/// exist, but there was no in-workflow way to delete a file. `remove` is
/// intentionally narrow: it deletes ONLY a file the session's `FileStateMap`
/// records as `Created` — one the agent itself created this session — so removing
/// it merely undoes the agent's own work. A pre-existing file (one the agent did
/// not create this session) is refused. It handles any file type: source and
/// non-source files go through the same gate — a deletion here is
/// provenance-checked where a `git rm` spawned from an `mbtx` snippet is not (a
/// snippet's own writes stay in its temp dir, so a spawned child is the only
/// unprovenanced deletion route). Deleting a
/// `.mbt`/`.mbt.md` file runs `moon
/// check`, so a break it causes shows up in the result as after `write`/`edit`.
/// Each removal carries a required `reason`, recorded in the (durable) result so
/// a destructive action can be audited later.
///
/// `Created` alone is not a delete capability (see `FileStateMap`). Three guards
/// keep the gate honest: the gate is `created_and_unchanged`, which pairs the
/// `Created` provenance with a content digest — `remove` reads the file back and
/// hashes it, so a path rebound to different content since the agent wrote it (a
/// `git checkout` restoring a tracked file, a `mv` onto the path) is refused, and
/// an `edit` cannot launder a rebind into a deletable `Created` (`record_edited`
/// downgrades it); this tool drops the provenance when it removes a file
/// (`forget`), so a path recreated after a removal reads as unknown; and the kind
/// check does not follow symlinks, so a path replaced by a link is refused rather
/// than followed. The digest is a content version — a byte-identical different
/// file passes, which is harmless — suited to the cooperative environment.
///
/// ## Result
/// - `Respond(ToolOutput("ok: removed <path> (reason: <reason>)"))` when the file
///   is deleted; a `.mbt`/`.mbt.md` removal also appends module `moon check`
///   feedback.
/// - `Respond(ToolOutput("error removing <path>: <reason>", is_error=true))` for
///   a missing file, a non-regular file, a file the agent did not create this
///   session (or created but whose content has changed since), or a filesystem
///   failure.
/// - `Respond(ToolOutput("error: remove requires ...", is_error=true))` for
///   invalid arguments.
pub fn definition(
  workspace_root? : String = ".",
  file_state? : @agent_tool.FileStateMap = FileStateMap(),
  write_scope? : @write_scope.WriteScope,
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="remove",
    description=(
      #|Delete a file the agent created earlier THIS session (tracked in the session's
      #|file-state record). Only a file the agent itself created this session can be
      #|removed — a pre-existing file is refused, since deleting it could lose work the
      #|agent never made; change existing source with edit/multi_edit. Handles any file
      #|type: it is the provenance-gated deletion path (a git rm spawned from an mbtx
      #|snippet checks no provenance), for source and non-source files alike. Deleting a
      #|.mbt/.mbt.md file runs moon check so any break it causes is reported. Requires a
      #|`reason` — a short, non-empty explanation of why the file is deleted — recorded
      #|with the result for auditing this destructive action; a blank reason is rejected.
      #|The path must name an existing regular file.
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
      )
    }),
  )
}

///|
async fn execute_with_workspace(
  workspace_root : String,
  file_state : @agent_tool.FileStateMap,
  arguments : Json,
  write_scope? : @write_scope.WriteScope,
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
  // Containment gate for confined (worker) registries: deletion is a
  // write-class operation. Re-checked immediately before the delete.
  if write_scope is Some(scope) && scope.deny_reason(path) is Some(reason) {
    return @agent_tool.respond(
      "error removing \{path}: write blocked: \{reason}",
      is_error=true,
      brief="remove \{@agent_tool.brief_basename(path)}",
    )
  }
  remove_file(path, input, file_state, write_scope?)
}

///|
async fn remove_file(
  path : String,
  input : @decode.RemoveInput,
  file_state : @agent_tool.FileStateMap,
  write_scope? : @write_scope.WriteScope,
) -> @agent_tool.ToolAction {
  let fail_brief = "remove \{@agent_tool.brief_basename(path)}"
  fn err(message : String) -> @agent_tool.ToolAction {
    @agent_tool.respond(
      "error removing \{path}: \{message}",
      is_error=true,
      brief=fail_brief,
    )
  }

  guard @fs.exists(path) else { return err("no such file") }
  // Classify the final component WITHOUT following a symlink: a path replaced by
  // a symlink since `write` recorded it must be refused, not followed to whatever
  // it now points at.
  guard @fs.kind(path, follow_symlink=false) is Regular else {
    return err("not a regular file; remove deletes regular files")
  }
  // The gate is two steps. First the CHEAP provenance check: a path the agent
  // never created (or only modified) is rejected without reading the file — so a
  // mistaken call against a large or binary pre-existing asset does not load and
  // decode it just to reject it.
  guard file_state.get(path) is Some(Created) else {
    return err(
      "not created by the agent this session — only a file the agent itself created this session can be removed; change existing source with edit/multi_edit",
    )
  }
  // It IS recorded `Created`. Now confirm its CONTENT is still what the agent
  // wrote: read the file back and digest it. A path rebound to different content
  // since the agent wrote it (a `git checkout` restoring a tracked file, a `mv`)
  // fails this and is refused. `record_edited` already downgrades a `Created`
  // file rebound before an edit, so an edit cannot launder a rebind either.
  let current_text = @fs.read_file(path).text()
  guard file_state.created_and_unchanged(
    path,
    @agent_tool.content_digest(current_text),
  ) else {
    return err(
      (
        #|the agent created this file this session but its content has changed since
        #|(rebound or externally modified) — refusing to remove what may no longer be the
        #|file it created
      ),
    )
  }
  // Containment re-check at the moment of deleting: the early gate decided on
  // filesystem state that awaits ago may have changed underneath the tool.
  if write_scope is Some(scope) && scope.deny_reason(path) is Some(reason) {
    return err("write blocked: \{reason}")
  }
  @fs.remove(path)
  // Drop the provenance so a path recreated after this removal is not treated as
  // still agent-created — otherwise a later remove could delete a different file
  // that happens to land at the same path.
  file_state.forget(path)
  // Record the rationale in the (durable) result for auditing, and append module
  // `moon check` feedback when a source file was removed — a deletion can break
  // the build just as an edit can.
  let summary = "ok: removed \{path} (reason: \{input.reason})"
  let content = @auto_check.append_summary(path, summary)
  @agent_tool.respond(
    content,
    brief=@agent_tool.brief_line("removed \{input.path}"),
  )
}
