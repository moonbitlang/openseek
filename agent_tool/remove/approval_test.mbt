///|
async test "existing and externally changed files ask once with path reason and trigger" {
  @vfs.with_tmpdir(dir => {
    let state = @agent_tool.FileStateMap()
    let asked : Array[@agent_runtime.ApprovalAsk] = []
    let channel = @agent_runtime.ApprovalChannel(ask => {
      asked.push(ask)
      AllowedOnce
    })
    let existing = "\{dir}/existing.txt"
    let changed = "\{dir}/changed.txt"
    @fs.write_file(existing, "existing", create_mode=CreateNew)
    @fs.write_file(changed, "formatted", create_mode=CreateNew)
    state.record_created(changed, @agent_tool.content_digest("unformatted"))
    for path in [existing, changed] {
      let result = run_remove(
        state,
        { "path": path, "reason": "replace obsolete starter" },
        approval=channel,
      )
      guard result is Respond(out) else { fail("expected response") }
      assert_false(out.is_error, msg=out.content)
      assert_false(@fs.exists(path))
      assert_eq(state.get(path), None)
      let ask = asked[asked.length() - 1]
      assert_eq(ask.tool_name, "remove")
      assert_eq(
        ask.body,
        Some(
          ({ "path": path, "reason": "replace obsolete starter" } : Json).stringify(),
        ),
      )
    }
    assert_eq(asked.length(), 2)
    assert_true(asked[0].detail.contains("not recorded"))
    assert_true(asked[1].detail.contains("content has changed"))
    // A grant is not retained, even when the same path is recreated unchanged.
    @fs.write_file(existing, "existing", create_mode=CreateNew)
    ignore(
      run_remove(
        state,
        { "path": existing, "reason": "cleanup" },
        approval=channel,
      ),
    )
    assert_eq(asked.length(), 3)
  })
}

///|
async test "unchanged agent-created files do not ask even if approval would be rejected" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/own.txt"
    @fs.write_file(path, "mine", create_mode=CreateNew)
    let state = @agent_tool.FileStateMap()
    state.record_created(path, @agent_tool.content_digest("mine"))
    let result = run_remove(
      state,
      { "path": path, "reason": "undo" },
      approval=ApprovalChannel(_ => fail("must not ask")),
    )
    guard result is Respond(out) else { fail("expected response") }
    assert_false(out.is_error)
    assert_false(@fs.exists(path))
  })
}

///|
async test "rejection cancellation and unavailable approval all preserve the file" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/keep.txt"
    @fs.write_file(path, "keep", create_mode=CreateNew)
    for
      (outcome, message) in [
        (@agent_runtime.Rejected, "rejected"),
        (Cancelled, "cancelled"),
        (Unavailable, "unavailable"),
      ] {
      let result = run_remove(
        FileStateMap(),
        { "path": path, "reason": "cleanup" },
        approval=ApprovalChannel(_ => outcome),
      )
      guard result is Respond(out) else { fail("expected response") }
      assert_true(out.is_error)
      assert_true(out.content.contains(message))
      assert_eq(@fs.read_file(path).text(), "keep")
    }
  })
}

///|
async test "approval does not hold the file gate and cannot authorize a changed version" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/changing.txt"
    @fs.write_file(path, "before", create_mode=CreateNew)
    let state = @agent_tool.FileStateMap()
    let result = @async.with_timeout(2000, () => {
      run_remove(
        state,
        { "path": path, "reason": "cleanup" },
        approval=ApprovalChannel(_ => {
          state.with_access(() => {
            @fs.write_file(path, "after", create_mode=CreateOrTruncate)
          })
          AllowedOnce
        }),
      )
    })
    guard result is Respond(out) else { fail("expected response") }
    assert_true(out.is_error)
    assert_true(out.content.contains("changed while awaiting approval"))
    assert_eq(@fs.read_file(path).text(), "after")
  })
}

///|
async test "approval rechecks file kind and worker scope" {
  @vfs.with_tmpdir(dir => {
    @fs.mkdir("\{dir}/allowed")
    @fs.write_file("\{dir}/target", "same", create_mode=CreateNew)
    guard @write_scope.WriteScope::create(root=dir, allowed_paths=["allowed"])
      is Ok(scope) else {
      fail("expected scope")
    }
    let path = "\{dir}/allowed/file"
    for replace_with_link in [true, false] {
      @fs.write_file(path, "same", create_mode=CreateNew)
      let definition = @remove.definition(
        workspace_root=dir,
        write_scope=scope,
        approval=ApprovalChannel(_ => {
          if replace_with_link {
            @fs.remove(path)
            @fs.symlink(path, target="\{dir}/target")
          } else {
            @fs.rename("\{dir}/allowed", "\{dir}/moved")
            @fs.symlink("\{dir}/allowed", target="\{dir}/moved")
          }
          AllowedOnce
        }),
      )
      guard definition.execute is Async(run) else { fail("expected async") }
      guard run({ "path": path, "reason": "cleanup" }) is Respond(out) else {
        fail("expected response")
      }
      assert_true(out.is_error)
      assert_eq(@fs.read_file(path).text(), "same")
      if replace_with_link {
        @fs.remove(path)
      }
    }
  })
}

///|
async test "symlinks and out-of-scope files never request approval" {
  @vfs.with_tmpdir(dir => {
    @fs.mkdir("\{dir}/allowed")
    @fs.mkdir("\{dir}/allowed/directory")
    @fs.write_file("\{dir}/outside", "keep", create_mode=CreateNew)
    @fs.symlink("\{dir}/allowed/link", target="\{dir}/outside")
    guard @write_scope.WriteScope::create(root=dir, allowed_paths=["allowed"])
      is Ok(scope) else {
      fail("expected scope")
    }
    let definition = @remove.definition(
      workspace_root=dir,
      write_scope=scope,
      approval=ApprovalChannel(_ => fail("must not ask")),
    )
    guard definition.execute is Async(run) else { fail("expected async") }
    for path in ["outside", "allowed/link"] {
      guard run({ "path": path, "reason": "cleanup" }) is Respond(out) else {
        fail("expected response")
      }
      assert_true(out.is_error)
    }
    assert_eq(@fs.read_file("\{dir}/outside").text(), "keep")
  })
}

///|
async test "binary files can be approved and cancellation leaves the gate reusable" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/binary"
    let bytes = b"\xff\x00\x80"
    @fs.write_file(path, bytes, create_mode=CreateNew)
    let state = @agent_tool.FileStateMap()
    let asked = Ref(false)
    let timed_out = try {
      @async.with_timeout(1000, () => {
        ignore(
          run_remove(
            state,
            { "path": path, "reason": "cleanup" },
            approval=ApprovalChannel(_ => {
              asked.val = true
              @async.sleep(60_000)
              AllowedOnce
            }),
          ),
        )
      })
      false
    } catch {
      _ => true
    }
    assert_true(timed_out)
    assert_true(asked.val)
    assert_eq(@fs.read_file(path).binary(), bytes)
    let result = @async.with_timeout(2000, () => {
      run_remove(
        state,
        { "path": path, "reason": "cleanup" },
        approval=ApprovalChannel(_ => AllowedOnce),
      )
    })
    guard result is Respond(out) else { fail("expected response") }
    assert_false(out.is_error, msg=out.content)
    assert_false(@fs.exists(path))
  })
}

///|
async test "approval is invalidated when a parent symlink redirects to identical bytes" {
  @vfs.with_tmpdir(dir => {
    @vfs.FileSystem({ "first/file": "same", "second/file": "same" }).write_to(
      dir,
    )
    @fs.symlink("\{dir}/alias", target="\{dir}/first")
    let path = "\{dir}/alias/file"
    let result = run_remove(
      FileStateMap(),
      { "path": path, "reason": "cleanup" },
      approval=ApprovalChannel(_ => {
        @fs.remove("\{dir}/alias")
        @fs.symlink("\{dir}/alias", target="\{dir}/second")
        AllowedOnce
      }),
    )
    guard result is Respond(out) else { fail("expected response") }
    assert_true(out.is_error)
    assert_true(out.content.contains("changed while awaiting approval"))
    assert_eq(@fs.read_file("\{dir}/first/file").text(), "same")
    assert_eq(@fs.read_file("\{dir}/second/file").text(), "same")
  })
}
