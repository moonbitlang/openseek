///|
/// Run the `write` tool from a built definition — the shape every test that
/// drives the registered executor uses.
async fn run_write(
  tool : @agent_tool.AgentToolDefinition,
  arguments : Json,
) -> @agent_tool.ToolAction {
  match tool.execute {
    Async(run) => run(arguments)
    Sync(_) => fail("write tool should be async")
  }
}

///|
async test "write resolves relative paths under the workspace root" {
  @vfs.with_tmpdir(prefix="openseek-write-workspace-", dir => {
    let result = run_write(@write.definition(workspace_root=dir), {
      "path": "note.txt",
      "content": "workspace",
    })
    guard result is Respond(output) else { fail("expected Respond") }
    let path = "\{dir}/note.txt"
    assert_false(output.is_error)
    assert_eq(output.content, "ok: wrote 1 line (9 chars) to \{path}")
    assert_eq(@fs.read_file(path).text(), "workspace")
  })
}

///|
async test "write fails on a dangling symlink instead of creating its target" {
  @vfs.with_tmpdir(dir => {
    // alias.txt -> lib/new.mbt where the target does not exist: `exists`
    // follows the link (false), so an O_CREAT write would create ungated
    // source THROUGH the link. CreateNew on the not-existed probe makes the
    // write fail instead.
    @fs.mkdir("\{dir}/lib", recursive=true)
    let link = "\{dir}/alias.txt"
    @fs.symlink(target="lib/new.mbt", link)
    let result = execute_via_boundary({
      "path": link,
      "content": "not moonbit (",
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("write failed"))
    assert_false(@fs.exists("\{dir}/lib/new.mbt"))
  })
}

///|
/// Execute through the registry so filesystem faults — which raise out of the
/// executor — are converted by the dispatch boundary in
/// `@agent_tool.execute_tool_call`, the same path production takes.
async fn execute_via_boundary(arguments : Json) -> @agent_tool.ToolAction {
  let tools = @agent_tool.Tools([@write.definition()])
  let call = @agent_tool.AgentToolCall(
    ToolCall(id="call_1", name="write", arguments=Json::stringify(arguments)),
  )
  @agent_tool.execute_tool_call(call, tools)
}

///|
async test "write surfaces filesystem errors through the dispatch boundary" {
  @vfs.with_tmpdir(dir => {
    // A parent component that is a regular file cannot be created or written
    // through, so the write fails (missing parent *directories* are created).
    @fs.write_file("\{dir}/afile", "x", create_mode=CreateOrTruncate)
    let result = execute_via_boundary({
      "path": "\{dir}/afile/child.txt",
      "content": "x",
    })
    guard result is Respond(output) else { fail("expected Respond") }
    assert_true(output.content.contains("write failed"))
    assert_true(output.is_error)
  })
}

///|
async test "write records a new file as Created and keeps it on overwrite" {
  @vfs.with_tmpdir(dir => {
    let state = @agent_tool.FileStateMap()
    let tool = @write.definition(file_state=state)
    let path = "\{dir}/note.txt"
    // A brand-new file the agent wrote is recorded as its own creation.
    let _ = run_write(tool, { "path": path, "content": "v1" })
    assert_true(state.get(path) is Some(Created))
    // Overwriting that same non-source file keeps the stronger Created state.
    let _ = run_write(tool, { "path": path, "content": "v2" })
    assert_true(state.get(path) is Some(Created))
  })
}

///|
async test "write records an overwrite of a pre-existing file as Modified" {
  @vfs.with_tmpdir(dir => {
    let state = @agent_tool.FileStateMap()
    let path = "\{dir}/pre.txt"
    // The file exists before the agent touches it this session.
    @vfs.FileSystem({ "pre.txt": "old" }).write_to(dir)
    let _ = run_write(@write.definition(file_state=state), {
      "path": path,
      "content": "new",
    })
    assert_true(state.get(path) is Some(Modified))
  })
}

///|
async test "a write scope confines write to its allowed paths" {
  @vfs.with_tmpdir(prefix="openseek-write-scope-", dir => {
    @vfs.FileSystem({ "lib/keep.txt": "k\n" }).write_to(dir)
    guard @write_scope.WriteScope::create(root=dir, allowed_paths=["lib"])
      is Ok(scope) else {
      fail("expected the scope to build")
    }
    let tool = @write.definition(workspace_root=dir, write_scope=scope)
    guard run_write(tool, { "path": "lib/new.txt", "content": "n\n" })
      is Respond(admitted) else {
      fail("expected Respond")
    }
    assert_false(admitted.is_error)
    assert_eq(@fs.read_file("\{dir}/lib/new.txt").text(), "n\n")
    // Out of scope: blocked before parent directories are even created.
    guard run_write(tool, { "path": "other/new.txt", "content": "n\n" })
      is Respond(blocked) else {
      fail("expected Respond")
    }
    assert_true(blocked.is_error)
    assert_true(blocked.content.contains("write blocked"))
    assert_false(@fs.exists("\{dir}/other"))
  })
}
