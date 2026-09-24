///|
/// The digest `remove` will compute for the file at `path` — read it back and
/// hash it — so a test records the same identity the delete gate revalidates
/// against. Returns `""` for a path that cannot be read (e.g. a missing-file
/// test, where the gate is never reached).
async fn recorded_digest(path : String) -> String {
  @agent_tool.content_digest(@fs.read_file(path).text()) catch {
    _ => ""
  }
}

///|
/// Run the `remove` tool bound to a shared file-state map — the shape every test
/// drives.
async fn run_remove(
  file_state : @agent_tool.FileStateMap,
  arguments : Json,
  approval? : @agent_runtime.ApprovalChannel,
) -> @agent_tool.ToolAction {
  match @remove.definition(file_state~, approval?).execute {
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
    // (and this path is gated, unlike a `git rm` spawned from an mbtx snippet).
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
      output.content.contains(
        "not recorded as created by the agent this session",
      ),
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
      output.content.contains(
        "not recorded as created by the agent this session",
      ),
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
async test "remove keeps a directory without an approval channel" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/pkg.mbt"
    @fs.mkdir(path, recursive=true)
    let state = @agent_tool.FileStateMap()
    state.record_created(path, recorded_digest(path))
    let result = run_remove(state, { "path": path, "reason": "cleanup" })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("no approval channel"))
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
      output.content.contains(
        "not recorded as created by the agent this session",
      ),
    )
    assert_true(@fs.exists(path))
  })
}

///|
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
      @remove.definition(
        workspace_root=dir,
        file_state=state,
        write_scope=scope,
      ).execute {
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
