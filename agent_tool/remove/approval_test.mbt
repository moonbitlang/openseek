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
    @fs.write_text(existing, "existing", create_mode=CreateNew)
    @fs.write_text(changed, "formatted", create_mode=CreateNew)
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
          ({ "path": path, "reason": "replace obsolete starter" } : Json).stringify(
            indent=2,
          ),
        ),
      )
    }
    assert_eq(asked.length(), 2)
    assert_true(asked[0].detail.contains("not recorded"))
    assert_true(asked[1].detail.contains("content has changed"))
    // A grant is not retained, even when the same path is recreated unchanged.
    @fs.write_text(existing, "existing", create_mode=CreateNew)
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
    @fs.write_text(path, "mine", create_mode=CreateNew)
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
    @fs.write_text(path, "keep", create_mode=CreateNew)
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
      assert_eq(@fs.read_text(path), "keep")
    }
  })
}

///|
async test "approval does not hold the file gate and cannot authorize a changed version" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/changing.txt"
    @fs.write_text(path, "before", create_mode=CreateNew)
    let state = @agent_tool.FileStateMap()
    let result = @async.with_timeout(2000, () => {
      run_remove(
        state,
        { "path": path, "reason": "cleanup" },
        approval=ApprovalChannel(_ => {
          state.with_access(() => {
            @fs.write_text(path, "after", create_mode=CreateOrTruncate)
          })
          AllowedOnce
        }),
      )
    })
    guard result is Respond(out) else { fail("expected response") }
    assert_true(out.is_error)
    assert_true(out.content.contains("changed while awaiting approval"))
    assert_eq(@fs.read_text(path), "after")
  })
}

///|
async test "approval rechecks file kind and worker scope" {
  @vfs.with_tmpdir(dir => {
    @fs.mkdir("\{dir}/allowed")
    @fs.write_text("\{dir}/target", "same", create_mode=CreateNew)
    let scope = @write_scope.WriteScope::create(root=dir, allowed_paths=[
      "allowed",
    ])
    let path = "\{dir}/allowed/file"
    for replace_with_link in [true, false] {
      @fs.write_text(path, "same", create_mode=CreateNew)
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
      assert_eq(@fs.read_text(path), "same")
      if replace_with_link {
        @fs.remove(path)
      }
    }
  })
}

///|
async test "approval unlinks file directory and dangling links by their in-scope names" {
  @vfs.with_tmpdir(dir => {
    @vfs.FileSystem({ "outside/file": "keep" }).write_to(dir)
    @fs.mkdir("\{dir}/allowed")
    let scope = @write_scope.WriteScope::create(root=dir, allowed_paths=[
      "allowed",
    ])
    let asks = Ref(0)
    let definition = @remove.definition(
      workspace_root=dir,
      write_scope=scope,
      approval=ApprovalChannel(ask => {
        asks.val += 1
        assert_true(ask.detail.contains("symbolic link"))
        assert_false(ask.detail.contains("write blocked"))
        AllowedOnce
      }),
    )
    guard definition.execute is Async(run) else { fail("expected async") }
    for
      (target, path) in [
        ("outside/file", "allowed/link"),
        ("outside", "allowed/link/"),
        ("missing", "allowed/link"),
      ] {
      @fs.symlink("\{dir}/allowed/link", target="\{dir}/\{target}")
      guard run({ "path": path, "reason": "cleanup" }) is Respond(out) else {
        fail("expected response")
      }
      assert_false(out.is_error, msg=out.content)
      assert_eq(@fs.readdir("\{dir}/allowed"), [])
    }
    assert_eq(asks.val, 3)
    assert_eq(@fs.read_text("\{dir}/outside/file"), "keep")
  })
}

///|
async test "unlink approval binds the stored target spelling, independently of target contents" {
  @vfs.with_tmpdir(dir => {
    let link = "\{dir}/link"
    @fs.write_text("\{dir}/file", "before", create_mode=CreateNew)
    @fs.symlink(link, target="file")
    for redirect in [true, false] {
      let result = run_remove(
        FileStateMap(),
        { "path": link, "reason": "cleanup" },
        approval=ApprovalChannel(_ => {
          if redirect {
            @fs.remove(link)
            @fs.symlink(link, target="./file")
          } else {
            @fs.write_text("\{dir}/file", "after", create_mode=TruncateExisting)
          }
          AllowedOnce
        }),
      )
      guard result is Respond(out) else { fail("expected response") }
      assert_eq(out.is_error, redirect, msg=out.content)
      if redirect {
        assert_true(out.content.contains("changed while awaiting approval"))
        assert_true(@fs.kind(link, follow_symlink=false) is SymLink)
      }
    }
    assert_eq(@fs.readdir(dir), ["file"])
    assert_eq(@fs.read_text("\{dir}/file"), "after")
  })
}

///|
async test "binary files can be approved and cancellation leaves the gate reusable" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/binary"
    let bytes = b"\xff\x00\x80"
    @fs.write_binary(path, bytes, create_mode=CreateNew)
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
    assert_eq(@fs.read_binary(path), bytes)
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
    assert_eq(@fs.read_text("\{dir}/first/file"), "same")
    assert_eq(@fs.read_text("\{dir}/second/file"), "same")
  })
}

///|
async test "removing through an intermediate link checks the resolved parent" {
  @vfs.with_tmpdir(dir => {
    @vfs.FileSystem({ "allowed/file": "keep", "outside/file": "remove" }).write_to(
      dir,
    )
    @fs.mkdir("\{dir}/outside/sub")
    @fs.symlink("\{dir}/allowed/alias", target="\{dir}/outside/sub")
    let scope = @write_scope.WriteScope::create(root=dir, allowed_paths=[
      "allowed",
    ])
    let ask_count = Ref(0)
    let definition = @remove.definition(
      workspace_root=dir,
      write_scope=scope,
      approval=ApprovalChannel(ask => {
        ask_count.val += 1
        assert_true(ask.detail.contains("write blocked"))
        AllowedOnce
      }),
    )
    guard definition.execute is Async(run) else { fail("expected async") }
    guard run({ "path": "allowed/alias/../file", "reason": "cleanup" })
      is Respond(out) else {
      fail("expected response")
    }
    assert_false(out.is_error, msg=out.content)
    assert_eq(ask_count.val, 1)
    assert_false(@fs.exists("\{dir}/outside/file"))
    assert_eq(@fs.read_text("\{dir}/allowed/file"), "keep")
    assert_true(
      @fs.kind("\{dir}/allowed/alias", follow_symlink=false) is SymLink,
    )
  })
}

///|
async test "redirecting a parent invalidates approval for an identical dangling link" {
  @vfs.with_tmpdir(dir => {
    for parent in ["first", "second"] {
      @fs.mkdir("\{dir}/\{parent}")
      @fs.symlink("\{dir}/\{parent}/link", target="missing")
    }
    let parent_link = "\{dir}/parent_link"
    @fs.symlink(parent_link, target="\{dir}/first")
    let result = run_remove(
      FileStateMap(),
      { "path": "\{parent_link}/link", "reason": "cleanup" },
      approval=ApprovalChannel(_ => {
        @fs.remove(parent_link)
        @fs.symlink(parent_link, target="\{dir}/second")
        AllowedOnce
      }),
    )
    guard result is Respond(out) else { fail("expected response") }
    assert_true(out.is_error)
    assert_true(out.content.contains("changed while awaiting approval"))
    for parent in ["first", "second"] {
      assert_true(
        @fs.kind("\{dir}/\{parent}/link", follow_symlink=false) is SymLink,
      )
    }
  })
}
