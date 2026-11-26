///|
async test "directory approval describes and removes a complete tree including hidden and empty entries" {
  @vfs.with_tmpdir(dir => {
    @vfs.FileSystem({
      "tree/a": "a",
      "tree/nested/.hidden": "hidden",
      "outside/file": "keep",
    }).write_to(dir)
    @fs.mkdir("\{dir}/tree/empty")
    @fs.symlink("\{dir}/tree/nested/out", target="\{dir}/outside")
    @fs.symlink("\{dir}/tree/loop", target="\{dir}/tree")
    let state = @agent_tool.FileStateMap()
    state.record_created("\{dir}/tree/a", @agent_tool.content_digest("a"))
    let asked = Ref(false)
    let definition = @remove.definition(
      workspace_root=dir,
      file_state=state,
      approval=ApprovalChannel(ask => {
        asked.val = true
        assert_eq(
          ask.detail,
          "\{dir}/tree (recursive directory deletion: 2 files, 2 symbolic links and 2 subdirectories; all contents present at deletion will be removed)",
        )
        assert_true(ask.body is Some(body) && body.contains("cleanup"))
        AllowedOnce
      }),
    )
    guard definition.execute is Async(run) else { fail("expected async") }
    guard run({ "path": "tree", "reason": "cleanup" }) is Respond(out) else {
      fail("expected response")
    }
    assert_false(out.is_error, msg=out.content)
    assert_true(asked.val)
    assert_false(@fs.exists("\{dir}/tree"))
    assert_eq(state.get("\{dir}/tree/a"), None)
    assert_eq(@fs.read_text("\{dir}/outside/file"), "keep")
  })
}

///|
async test "nonempty directory requires approval and all denial outcomes preserve it" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/tree"
    @fs.mkdir(path)
    @fs.mkdir("\{path}/empty-child")
    for outcome in [@agent_runtime.Rejected, Cancelled, Unavailable] {
      let result = run_remove(
        FileStateMap(),
        { "path": path, "reason": "cleanup" },
        approval=ApprovalChannel(_ => outcome),
      )
      guard result is Respond(out) else { fail("expected response") }
      assert_true(out.is_error)
      assert_true(@fs.exists(path))
    }
    let result = run_remove(
      FileStateMap(),
      { "path": path, "reason": "cleanup" },
      approval=ApprovalChannel(_ => AllowedOnce),
    )
    guard result is Respond(out) else { fail("expected response") }
    assert_false(out.is_error, msg=out.content)
    assert_false(@fs.exists(path))
  })
}

///|
async test "directory approval deletes the contents present at execution" {
  @vfs.with_tmpdir(dir => {
    @vfs.FileSystem({
      "tree/old": "old",
      "outside/keep": "keep",
      "treehouse/file": "mine",
    }).write_to(dir)
    let state = @agent_tool.FileStateMap()
    let sibling = "\{dir}/treehouse/file"
    state.record_created(sibling, @agent_tool.content_digest("mine"))
    let added = "\{dir}/tree/new/file"
    let result = run_remove(
      state,
      { "path": "\{dir}/tree", "reason": "cleanup" },
      approval=ApprovalChannel(_ => {
        state.with_access(() => {
          @fs.remove("\{dir}/tree/old")
          state.create_parent_directories(added)
          @fs.write_text(added, "new", create_mode=CreateNew)
          state.record_created(added, @agent_tool.content_digest("new"))
          @fs.symlink("\{dir}/tree/link", target="\{dir}/outside")
        })
        AllowedOnce
      }),
    )
    guard result is Respond(out) else { fail("expected response") }
    assert_false(out.is_error, msg=out.content)
    assert_false(@fs.exists("\{dir}/tree"))
    assert_eq(@fs.read_text("\{dir}/outside/keep"), "keep")
    assert_eq(state.get(added), None)
    assert_false(state.created_directory("\{dir}/tree/new"))
    assert_true(state.get(sibling) is Some(Created))
  })
}

///|
async test "directory deletion protects the workspace and its ancestors" {
  @vfs.with_tmpdir(dir => {
    @vfs.FileSystem({ "workspace/tree/keep": "keep", "outside/file": "outside" }).write_to(
      dir,
    )
    let asks = Ref(0)
    let definition = @remove.definition(
      workspace_root="\{dir}/workspace",
      approval=ApprovalChannel(_ => {
        asks.val += 1
        Rejected
      }),
    )
    guard definition.execute is Async(run) else { fail("expected async") }
    for path in [".", "..", dir, "\{dir}/workspace"] {
      guard run({ "path": path, "reason": "cleanup" }) is Respond(out) else {
        fail("expected response")
      }
      assert_true(out.is_error, msg=path)
    }
    assert_eq(asks.val, 0)
    assert_eq(@fs.read_text("\{dir}/workspace/tree/keep"), "keep")
    assert_eq(@fs.read_text("\{dir}/outside/file"), "outside")
  })
}

///|
async test "directory approval cannot authorize a redirected parent with identical contents" {
  @vfs.with_tmpdir(dir => {
    @vfs.FileSystem({ "first/tree/a": "same", "second/tree/a": "same" }).write_to(
      dir,
    )
    @fs.symlink("\{dir}/alias", target="\{dir}/first")
    let result = run_remove(
      FileStateMap(),
      { "path": "\{dir}/alias/tree", "reason": "cleanup" },
      approval=ApprovalChannel(_ => {
        @fs.remove("\{dir}/alias")
        @fs.symlink("\{dir}/alias", target="\{dir}/second")
        AllowedOnce
      }),
    )
    guard result is Respond(out) else { fail("expected response") }
    assert_true(out.is_error)
    assert_true(out.content.contains("changed while awaiting approval"))
    assert_eq(@fs.read_text("\{dir}/first/tree/a"), "same")
    assert_eq(@fs.read_text("\{dir}/second/tree/a"), "same")
  })
}

///|
async test "empty directories are removed without asking even when a channel is present" {
  @vfs.with_tmpdir(dir => {
    for with_channel in [false, true] {
      let path = "\{dir}/empty"
      @fs.mkdir(path)
      let result = run_remove(
        FileStateMap(),
        { "path": path, "reason": "cleanup empty directory" },
        approval?=if with_channel {
          Some(ApprovalChannel(_ => fail("must not ask")))
        } else {
          None
        },
      )
      guard result is Respond(out) else { fail("expected response") }
      assert_false(out.is_error, msg=out.content)
      assert_false(@fs.exists(path))
    }
  })
}

///|
async test "a complete agent-created directory tree is removed without approval" {
  @vfs.with_tmpdir(prefix="openseek-remove-created-tree-", dir => {
    let state = @agent_tool.FileStateMap()
    let root = "\{dir}/generated"
    let nested = "\{root}/nested"
    let path = "\{nested}/report.txt"
    state.create_parent_directories(path)
    @fs.write_text(path, "temporary report", create_mode=CreateNew)
    state.record_created(path, @agent_tool.content_digest("temporary report"))
    let asked = Ref(false)
    let definition = @remove.definition(
      workspace_root=dir,
      file_state=state,
      approval=ApprovalChannel(_ => {
        asked.val = true
        AllowedOnce
      }),
    )
    guard definition.execute is Async(run) else { fail("expected async") }
    guard run({
        "path": "generated",
        "reason": "generated report is no longer needed",
      })
      is Respond(output) else {
      fail("expected response")
    }
    assert_false(output.is_error, msg=output.content)
    assert_false(asked.val)
    assert_false(@fs.exists(root))
    assert_true(state.get(path) is None)
    assert_false(state.created_directory(root))
    assert_false(state.created_directory(nested))
  })
}
