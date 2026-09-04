///|
/// Tool definition for `remove`: delete a file the agent created earlier this
/// session, with a required rationale recorded for auditing.
///
/// This fills the one gap in the tool-mediated file API — `read`/`write`/`edit`
/// exist, but there was no in-workflow way to delete a file. `remove` is
/// intentionally narrow: it deletes ONLY a file the session's `FileStateMap`
/// records as `Created` — one the agent itself created this session — so removing
/// it merely undoes the agent's own work. A pre-existing file (one the agent did
/// not create this session) is refused. It handles any file type: it is the only
/// way to delete a source file (the shell sandbox blocks `rm` on source paths),
/// and the gated path for other files too — a deletion here is provenance-checked
/// where a `shell` `rm` is not. Deleting a `.mbt`/`.mbt.md` file runs `moon
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
      #|type: the only in-workflow way to delete a source file (the shell sandbox blocks
      #|rm on source paths), and the provenance-gated path for other files too. Deleting a
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

  let exists = @fs.exists(path)
  if !exists {
    return err("no such file")
  }
  // Classify the final component WITHOUT following a symlink: a path replaced by
  // a symlink since `write` recorded it must be refused, not followed to whatever
  // it now points at.
  let kind = @fs.kind(path, follow_symlink=false)
  guard kind is Regular else {
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

///|
/// The digest `remove` will compute for the file at `path` — read it back and
/// hash it — so a test records the same identity the delete gate revalidates
/// against. Returns `""` for a path that cannot be read (e.g. a missing-file
/// test, where the gate is never reached).
async fn recorded_digest(path : String) -> String {
  @agent_tool.content_digest(@fs.read_file(path).text()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ""
  }
}

///|
/// Run the `remove` tool bound to a shared file-state map — the shape every test
/// drives.
async fn run_remove(
  file_state : @agent_tool.FileStateMap,
  arguments : Json,
) -> @agent_tool.ToolAction {
  match definition(file_state~).execute {
    Async(run) => run(arguments)
    Sync(_) => fail("remove tool should be async")
  }
}

///|
async test "remove deletes a file the agent created this session, recording why" {
  @vfs.with_tmpdir(dir => {
    @vfs.FileSystem({ "scratch.mbt": "pub fn f() -> Int { 1 }\n" }).write_to(
      dir,
    )
    let path = "\{dir}/scratch.mbt"
    // The map records the create, as `write` would have.
    let state = @agent_tool.FileStateMap()
    state.record_created(path, recorded_digest(path))
    let result = run_remove(state, {
      "path": path,
      "reason": "scratch no longer needed",
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    // The rationale is recorded in the durable result for auditing.
    assert_eq(
      output.content,
      "ok: removed \{path} (reason: scratch no longer needed)",
    )
    assert_false(@fs.exists(path))
  })
}

///|
async test "remove keeps deleting a created file it later edited" {
  @vfs.with_tmpdir(dir => {
    @vfs.FileSystem({ "grown.mbt": "pub fn f() -> Int { 1 }\n" }).write_to(dir)
    let path = "\{dir}/grown.mbt"
    let state = @agent_tool.FileStateMap()
    // Created then modified this session: record_modified must not downgrade it.
    state.record_created(path, recorded_digest(path))
    state.record_modified(path, recorded_digest(path))
    let result = run_remove(state, { "path": path, "reason": "undo" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_false(@fs.exists(path))
  })
}

///|
async test "remove deletes a non-source file the agent created" {
  @vfs.with_tmpdir(dir => {
    // The gate is provenance, not file type: a created .txt is deletable too
    // (and this path is gated, unlike a bare shell `rm`).
    @vfs.FileSystem({ "notes.txt": "scratch" }).write_to(dir)
    let path = "\{dir}/notes.txt"
    let state = @agent_tool.FileStateMap()
    state.record_created(path, recorded_digest(path))
    let result = run_remove(state, { "path": path, "reason": "temp file" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_false(@fs.exists(path))
  })
}

///|
async test "remove refuses a pre-existing file it did not create" {
  @vfs.with_tmpdir(dir => {
    @vfs.FileSystem({ "lib.mbt": "pub fn g() -> Int { 0 }\n" }).write_to(dir)
    let path = "\{dir}/lib.mbt"
    // Empty state: the agent did not create this file this session.
    let state = @agent_tool.FileStateMap()
    let result = run_remove(state, { "path": path, "reason": "cleanup" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(
      output.content.contains("not created by the agent this session"),
    )
    assert_true(@fs.exists(path))
  })
}

///|
async test "remove refuses a file the agent only modified" {
  @vfs.with_tmpdir(dir => {
    @vfs.FileSystem({ "edited.mbt": "pub fn h() -> Int { 2 }\n" }).write_to(dir)
    let path = "\{dir}/edited.mbt"
    let state = @agent_tool.FileStateMap()
    state.record_modified(path, recorded_digest(path))
    let result = run_remove(state, { "path": path, "reason": "cleanup" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(
      output.content.contains("not created by the agent this session"),
    )
    assert_true(@fs.exists(path))
  })
}

///|
async test "remove refuses a created file whose identity no longer matches" {
  @vfs.with_tmpdir(dir => {
    @vfs.FileSystem({ "lib.mbt": "pub fn f() -> Int { 1 }\n" }).write_to(dir)
    let path = "\{dir}/lib.mbt"
    let state = @agent_tool.FileStateMap()
    // Record a digest that cannot match the file's actual content, standing in
    // for a path rebound to a DIFFERENT file since the agent wrote it (e.g. a
    // `git checkout` restoring a tracked file). The gate must refuse rather than
    // delete what may no longer be the agent's file.
    state.record_created(
      path,
      @agent_tool.content_digest("different content\n"),
    )
    let result = run_remove(state, { "path": path, "reason": "cleanup" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("content has changed since"))
    assert_true(@fs.exists(path))
  })
}

///|
async test "remove reports a missing file" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/ghost.mbt"
    let state = @agent_tool.FileStateMap()
    state.record_created(path, recorded_digest(path))
    let result = run_remove(state, { "path": path, "reason": "cleanup" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("no such file"))
  })
}

///|
async test "remove refuses a directory" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/pkg.mbt"
    @fs.mkdir(path, recursive=true)
    let state = @agent_tool.FileStateMap()
    state.record_created(path, recorded_digest(path))
    let result = run_remove(state, { "path": path, "reason": "cleanup" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("not a regular file"))
    assert_true(@fs.exists(path))
  })
}

///|
async test "remove refuses a path recreated after an earlier removal" {
  @vfs.with_tmpdir(dir => {
    @vfs.FileSystem({ "redo.mbt": "pub fn a() -> Int { 1 }\n" }).write_to(dir)
    let path = "\{dir}/redo.mbt"
    let state = @agent_tool.FileStateMap()
    state.record_created(path, recorded_digest(path))
    // The first removal succeeds and drops the provenance.
    let first = run_remove(state, { "path": path, "reason": "undo" })
    guard first is Respond(ok) else { fail("expected Respond") }
    assert_false(ok.is_error)
    assert_false(@fs.exists(path))
    // Something OTHER than the agent's tools recreates the same path.
    @vfs.FileSystem({ "redo.mbt": "pub fn b() -> Int { 2 }\n" }).write_to(dir)
    // The stale Created must not authorize deleting this different file.
    let second = run_remove(state, { "path": path, "reason": "undo again" })
    guard second is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(
      output.content.contains("not created by the agent this session"),
    )
    assert_true(@fs.exists(path))
  })
}

///|
#cfg(not(platform="windows"))
async test "remove refuses a path replaced by a symlink" {
  @vfs.with_tmpdir(dir => {
    @vfs.FileSystem({ "target.mbt": "pub fn t() -> Int { 0 }\n" }).write_to(dir)
    let target = "\{dir}/target.mbt"
    // The path the agent created is now a symlink to another file.
    let link = "\{dir}/alias.mbt"
    @fs.symlink(target~, link)
    let state = @agent_tool.FileStateMap()
    state.record_created(link, recorded_digest(link))
    let result = run_remove(state, { "path": link, "reason": "cleanup" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("not a regular file"))
    // The kind check does not follow the link, so neither it nor its target is
    // removed.
    assert_true(@fs.exists(link))
    assert_true(@fs.exists(target))
  })
}

///|
async test "remove rejects missing path" {
  let state = @agent_tool.FileStateMap()
  let result = run_remove(state, { "reason": "cleanup" })
  guard result is Respond(output) else { fail("expected Respond") }
  assert_eq(output.content, "error: remove requires arguments.path")
  assert_true(output.is_error)
}

///|
async test "remove rejects a missing reason" {
  @vfs.with_tmpdir(dir => {
    @vfs.FileSystem({ "x.mbt": "pub fn x() -> Int { 0 }\n" }).write_to(dir)
    let path = "\{dir}/x.mbt"
    let state = @agent_tool.FileStateMap()
    state.record_created(path, recorded_digest(path))
    // A destructive action must carry a rationale — no delete without one.
    let result = run_remove(state, { "path": path })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_eq(output.content, "error: remove requires arguments.reason")
    assert_true(output.is_error)
    assert_true(@fs.exists(path))
  })
}

///|
async test "remove rejects a blank reason" {
  @vfs.with_tmpdir(dir => {
    @vfs.FileSystem({ "y.mbt": "pub fn y() -> Int { 0 }\n" }).write_to(dir)
    let path = "\{dir}/y.mbt"
    let state = @agent_tool.FileStateMap()
    state.record_created(path, recorded_digest(path))
    // A whitespace-only rationale would produce an empty audit entry, so it is
    // rejected just like a missing one. Includes Unicode whitespace (a
    // non-breaking and an ideographic space) that ASCII `trim` would miss.
    let result = run_remove(state, {
      "path": path,
      "reason": "\u{00a0} \u{3000}",
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_eq(
      output.content,
      "error: remove requires arguments.reason to be a non-empty explanation",
    )
    assert_true(output.is_error)
    assert_true(@fs.exists(path))
  })
}

///|
#cfg(not(platform="windows"))
async test "a write scope confines remove to its allowed paths" {
  @vfs.with_tmpdir(prefix="openseek-remove-scope-", dir => {
    @vfs.FileSystem({ "lib/mine.txt": "m\n", "other/mine.txt": "m\n" }).write_to(
      dir,
    )
    // Both files carry agent-created provenance, so only the scope decides.
    let state = @agent_tool.FileStateMap()
    state.record_created(
      "\{dir}/lib/mine.txt",
      recorded_digest("\{dir}/lib/mine.txt"),
    )
    state.record_created(
      "\{dir}/other/mine.txt",
      recorded_digest("\{dir}/other/mine.txt"),
    )
    guard @write_scope.WriteScope::create(root=dir, allowed_paths=["lib"])
      is Ok(scope) else {
      fail("expected the scope to build")
    }
    let run = match
      definition(workspace_root=dir, file_state=state, write_scope=scope).execute {
      Async(execute) => execute
      Sync(_) => fail("remove tool should be async")
    }
    guard run({ "path": "other/mine.txt", "reason": "test" })
      is Respond(blocked) else {
      fail("expected Respond")
    }
    assert_true(blocked.is_error)
    assert_true(blocked.content.contains("write blocked"))
    assert_true(@fs.exists("\{dir}/other/mine.txt"))
    guard run({ "path": "lib/mine.txt", "reason": "test" }) is Respond(admitted) else {
      fail("expected Respond")
    }
    assert_false(admitted.is_error)
    assert_false(@fs.exists("\{dir}/lib/mine.txt"))
  })
}
