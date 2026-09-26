///|
async test "directory approval describes and removes a complete tree including hidden and empty entries" {
  @vfs.with_tmpdir(dir => {
    @vfs.FileSystem({ "tree/a": "a", "tree/nested/.hidden": "hidden" }).write_to(
      dir,
    )
    @fs.mkdir("\{dir}/tree/empty")
    let state = @agent_tool.FileStateMap()
    state.record_created("\{dir}/tree/a", @agent_tool.content_digest("a"))
    let asked = Ref(false)
    let definition = @remove.definition(
      workspace_root=dir,
      file_state=state,
      approval=ApprovalChannel(ask => {
        asked.val = true
        assert_true(ask.detail.contains("recursive directory deletion"))
        assert_true(ask.detail.contains("2 files and 2 subdirectories"))
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
async test "directory approval invalidates changed added removed renamed and replaced entries" {
  for change in ["edit", "add", "remove", "rename", "kind", "link"] {
    @vfs.with_tmpdir(dir => {
      @vfs.FileSystem({
        "tree/a": "before",
        "tree/keep": "keep",
        "outside": "outside",
      }).write_to(dir)
      let state = @agent_tool.FileStateMap()
      let result = run_remove(
        state,
        { "path": "\{dir}/tree", "reason": "cleanup" },
        approval=ApprovalChannel(_ => {
          state.with_access(() => {
            match change {
              "edit" =>
                @fs.write_file(
                  "\{dir}/tree/a",
                  "after",
                  create_mode=CreateOrTruncate,
                )
              "add" => @fs.mkdir("\{dir}/tree/new-empty")
              "remove" => @fs.remove("\{dir}/tree/a")
              "rename" => @fs.rename("\{dir}/tree/a", "\{dir}/tree/b")
              "kind" => {
                @fs.remove("\{dir}/tree/a")
                @fs.mkdir("\{dir}/tree/a")
              }
              _ => {
                @fs.remove("\{dir}/tree/a")
                @fs.symlink("\{dir}/tree/a", target="\{dir}/outside")
              }
            }
          })
          AllowedOnce
        }),
      )
      guard result is Respond(out) else { fail("expected response") }
      assert_true(out.is_error, msg=change)
      assert_eq(@fs.read_file("\{dir}/tree/keep").text(), "keep")
      assert_eq(@fs.read_file("\{dir}/outside").text(), "outside")
    })
  }
}

///|
async test "directory deletion refuses workspace ancestors symlinks and scope escapes before approval" {
  @vfs.with_tmpdir(dir => {
    @vfs.FileSystem({ "workspace/tree/keep": "keep", "outside/file": "outside" }).write_to(
      dir,
    )
    @fs.symlink("\{dir}/workspace/tree/link", target="\{dir}/outside")
    @fs.symlink("\{dir}/workspace-alias", target="\{dir}/workspace")
    let definition = @remove.definition(
      workspace_root="\{dir}/workspace",
      approval=ApprovalChannel(_ => fail("must not ask")),
    )
    guard definition.execute is Async(run) else { fail("expected async") }
    for path in [".", "..", "../workspace-alias", "tree"] {
      guard run({ "path": path, "reason": "cleanup" }) is Respond(out) else {
        fail("expected response")
      }
      assert_true(out.is_error, msg=path)
    }
    guard @write_scope.WriteScope::create(root=dir, allowed_paths=[
        "workspace/tree",
      ])
      is Ok(scope) else {
      fail("expected scope")
    }
    let confined = @remove.definition(
      workspace_root=dir,
      write_scope=scope,
      approval=ApprovalChannel(_ => fail("must not ask")),
    )
    guard confined.execute is Async(run_confined) else {
      fail("expected async")
    }
    guard run_confined({ "path": "workspace", "reason": "cleanup" })
      is Respond(out) else {
      fail("expected response")
    }
    assert_true(out.is_error)
    assert_eq(@fs.read_file("\{dir}/workspace/tree/keep").text(), "keep")
    assert_eq(@fs.read_file("\{dir}/outside/file").text(), "outside")
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
    assert_eq(@fs.read_file("\{dir}/first/tree/a").text(), "same")
    assert_eq(@fs.read_file("\{dir}/second/tree/a").text(), "same")
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
    @fs.write_file(path, "temporary report", create_mode=CreateNew)
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
