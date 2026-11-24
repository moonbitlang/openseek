///|
async fn run_copy(
  tool : @agent_tool.AgentToolDefinition,
  arguments : Json,
) -> @agent_tool.ToolAction {
  @agent_tool.execute_tool_call(
    @agent_tool.AgentToolCall::from_arguments("copy", arguments),
    Tools([tool]),
  )
}

///|
async test "copy validates its source and destination arguments" {
  @vfs.with_tmpdir(dir => {
    let tool = @copy.definition(workspace_root=dir)
    @fs.write_binary("\{dir}/input.bin", b"\xff")
    for
      (arguments, message) in [
        (({ "destination": "out.bin" } : Json), "arguments.source"),
        ({ "source": "input.bin", "destination": "" }, "arguments.destination"),
        (
          { "source": "input.bin\u{0}", "destination": "out.bin" },
          "contain no NUL",
        ),
        (
          { "source": "input.bin", "destination": "out.bin\u{0}" },
          "contain no NUL",
        ),
        (
          { "source": "input.bin", "destination": "nested/" },
          "file destination",
        ),
      ] {
      guard run_copy(tool, arguments) is Respond(out) else {
        fail("expected response")
      }
      assert_true(out.is_error)
      assert_true(out.content.contains(message), msg=out.content)
      assert_false(@fs.exists("\{dir}/out.bin"))
      assert_false(@fs.exists("\{dir}/nested"))
    }
  })
}

///|
async test "copy copies arbitrary bytes, supports self-copy, and records provenance" {
  @vfs.with_tmpdir(dir => {
    let bytes = b"\x00\xff\x80hello\r\n"
    @fs.write_binary("\{dir}/input.bin", bytes)
    let state = @agent_tool.FileStateMap()
    let tool = @copy.definition(workspace_root=dir, file_state=state)
    guard run_copy(tool, {
        "destination": "output/nested.bin",
        "source": "input.bin",
      })
      is Respond(out) else {
      fail("expected response")
    }
    assert_false(out.is_error, msg=out.content)
    let path = "\{dir}/output/nested.bin"
    let digest = @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
    assert_eq(@fs.read_binary(path), bytes)
    assert_eq(out.data, Some({ "bytes": bytes.length(), "sha256": digest }))
    assert_true(state.get(path) is Some(Created))
    assert_true(state.created_and_unchanged(path, digest))
    assert_eq(@fs.read_binary("\{dir}/input.bin"), bytes)
    guard run_copy(tool, { "destination": path, "source": path })
      is Respond(overwritten) else {
      fail("expected response")
    }
    assert_false(overwritten.is_error, msg=overwritten.content)
    assert_true(overwritten.content.contains("overwrote existing file"))
    assert_eq(@fs.read_binary(path), bytes)
    assert_true(state.created_and_unchanged(path, digest))
  })
}

///|
async test "copy streams multi-chunk binary files" {
  @vfs.with_tmpdir(dir => {
    let source = "\{dir}/large.bin"
    let file = @fs.open(source, mode=WriteOnly, create_mode=CreateNew)
    defer file.close()
    let chunk = Bytes::make(65536, b'\xff')
    for _ in 0..<4 {
      file.write(chunk)
    }
    file.write(b"\x00\x80\xff")
    file.close()
    let tool = @copy.definition(workspace_root=dir)
    guard run_copy(tool, { "destination": "copy.bin", "source": "large.bin" })
      is Respond(out) else {
      fail("expected response")
    }
    assert_false(out.is_error, msg=out.content)
    let copied = @fs.read_binary("\{dir}/copy.bin")
    assert_eq(copied.length(), 262147)
    assert_eq(copied[0], b'\xff')
    assert_eq(copied[copied.length() - 3:], b"\x00\x80\xff")
    assert_eq(
      out.data,
      Some({
        "bytes": copied.length(),
        "sha256": @crypto.bytes_to_hex_string(@crypto.sha256(copied)),
      }),
    )
  })
}

///|
async test "copy accepts empty files and marks existing targets Modified" {
  @vfs.with_tmpdir(dir => {
    @fs.write_text("\{dir}/empty", "")
    @fs.write_text("\{dir}/target", "old")
    let state = @agent_tool.FileStateMap()
    guard run_copy(@copy.definition(workspace_root=dir, file_state=state), {
        "destination": "target",
        "source": "empty",
      })
      is Respond(out) else {
      fail("expected response")
    }
    assert_false(out.is_error, msg=out.content)
    assert_eq(@fs.file_size("\{dir}/target"), 0L)
    assert_true(state.get("\{dir}/target") is Some(Modified))
    assert_true(out.data is Some({ "bytes": 0, .. }))
  })
}

///|
async test "copy rejects missing and nonregular sources before touching destination" {
  @vfs.with_tmpdir(dir => {
    let tool = @copy.definition(workspace_root=dir)
    for source in ["missing.bin", "."] {
      guard run_copy(tool, { "destination": "new/output.bin", "source": source })
        is Respond(out) else {
        fail("expected response")
      }
      assert_true(out.is_error)
      assert_false(@fs.exists("\{dir}/new"))
    }
  })
}

///|
async test "copy rejects MoonBit source and manifest destinations including symlink targets" {
  @vfs.with_tmpdir(dir => {
    let tool = @copy.definition(workspace_root=dir)
    @fs.write_text("\{dir}/candidate", "fn f() -> Int { 1 }\n")
    for
      name in [
        "source.mbt", "doc.mbt.md", "script.mbtx", "api.mbti", "pkg.generated.mbti",
        "moon.mod", "moon.mod.json", "moon.pkg",
      ] {
      guard run_copy(tool, {
          "destination": "new/\{name}",
          "source": "candidate",
        })
        is Respond(out) else {
        fail("expected response")
      }
      assert_true(out.is_error, msg=out.content)
      assert_true(
        out.content.contains("non-MoonBit artifacts"),
        msg=out.content,
      )
      assert_false(@fs.exists("\{dir}/new"))
    }
    @fs.write_text("\{dir}/moon.pkg", "import {}\n")
    @fs.symlink(target="moon.pkg", "\{dir}/alias.bin")
    guard run_copy(tool, { "destination": "alias.bin", "source": "candidate" })
      is Respond(out) else {
      fail("expected response")
    }
    assert_true(out.is_error)
    assert_true(out.content.contains("non-MoonBit artifacts"), msg=out.content)
    assert_eq(@fs.read_text("\{dir}/moon.pkg"), "import {}\n")
  })
}

///|
async test "copy enforces write scope, one-shot approval, and symlink retarget checks" {
  @vfs.with_tmpdir(dir => {
    @fs.write_binary("\{dir}/candidate", b"\xff\x00")
    guard @write_scope.WriteScope::create(root=dir, allowed_paths=["allowed"])
      is Ok(scope) else {
      fail("expected scope")
    }
    // Without an approval channel, out-of-scope destinations fail closed.
    guard run_copy(@copy.definition(workspace_root=dir, write_scope=scope), {
        "destination": "blocked/new.bin",
        "source": "candidate",
      })
      is Respond(blocked) else {
      fail("expected response")
    }
    assert_true(blocked.is_error)
    assert_true(
      blocked.content.contains("no approval channel"),
      msg=blocked.content,
    )
    assert_false(@fs.exists("\{dir}/blocked"))

    // Rejection and cancellation leave no directories or temporary files;
    // AllowedOnce grants only the approved target.
    for outcome in [@agent_runtime.Rejected, Cancelled, AllowedOnce] {
      let tool = @copy.definition(
        workspace_root=dir,
        write_scope=scope,
        approval=ApprovalChannel(_ => outcome),
      )
      guard run_copy(tool, {
          "destination": "outside/new.bin",
          "source": "candidate",
        })
        is Respond(out) else {
        fail("expected response")
      }
      if outcome is AllowedOnce {
        assert_false(out.is_error, msg=out.content)
        assert_eq(@fs.read_binary("\{dir}/outside/new.bin"), b"\xff\x00")
        assert_true(scope.deny_reason("\{dir}/outside/new.bin") is Some(_))
      } else {
        assert_true(out.is_error)
        assert_false(@fs.exists("\{dir}/outside"))
      }
    }

    // Retargeting a symlink while awaiting approval is rejected.
    @fs.write_text("\{dir}/one.bin", "one")
    @fs.write_text("\{dir}/two.bin", "two")
    @fs.symlink(target="one.bin", "\{dir}/alias.bin")
    let retarget = @copy.definition(
      workspace_root=dir,
      write_scope=scope,
      approval=ApprovalChannel(_ => {
        @fs.remove("\{dir}/alias.bin")
        @fs.symlink(target="two.bin", "\{dir}/alias.bin")
        AllowedOnce
      }),
    )
    guard run_copy(retarget, {
        "destination": "alias.bin",
        "source": "candidate",
      })
      is Respond(out) else {
      fail("expected response")
    }
    assert_true(out.is_error)
    assert_true(
      out.content.contains("changed while awaiting approval"),
      msg=out.content,
    )
    assert_eq(@fs.read_text("\{dir}/one.bin"), "one")
    assert_eq(@fs.read_text("\{dir}/two.bin"), "two")
  })
}

///|
async test "copy cancellation during approval preserves target and releases the gate" {
  @vfs.with_tmpdir(dir => {
    @fs.write_text("\{dir}/candidate", "new")
    @fs.write_text("\{dir}/target.txt", "old")
    guard @write_scope.WriteScope::create(root=dir, allowed_paths=["allowed"])
      is Ok(scope) else {
      fail("expected scope")
    }
    let state = @agent_tool.FileStateMap()
    let asked = Ref(false)
    let waiting = @copy.definition(
      workspace_root=dir,
      write_scope=scope,
      file_state=state,
      approval=ApprovalChannel(_ => {
        asked.val = true
        @async.sleep(60_000)
        AllowedOnce
      }),
    )
    let result = @async.with_timeout_opt(1000, () => {
      run_copy(waiting, { "destination": "target.txt", "source": "candidate" })
    })
    assert_true(result is None)
    assert_true(asked.val)
    assert_eq(@fs.read_text("\{dir}/target.txt"), "old")
    assert_eq(state.get("\{dir}/target.txt"), None)
    let approved = @copy.definition(
      workspace_root=dir,
      write_scope=scope,
      file_state=state,
      approval=ApprovalChannel(_ => AllowedOnce),
    )
    guard @async.with_timeout(2000, () => {
        run_copy(approved, {
          "destination": "target.txt",
          "source": "candidate",
        })
      })
      is Respond(out) else {
      fail("expected response")
    }
    assert_false(out.is_error, msg=out.content)
    assert_eq(@fs.read_text("\{dir}/target.txt"), "new")
  })
}

///|
async test "copy rejects dangling symlinks and atomically replaces symlink targets" {
  @vfs.with_tmpdir(dir => {
    @fs.write_binary("\{dir}/candidate", b"\xff\x00")
    @fs.symlink(target="missing.bin", "\{dir}/dangling.bin")
    let tool = @copy.definition(workspace_root=dir)
    guard run_copy(tool, {
        "destination": "dangling.bin",
        "source": "candidate",
      })
      is Respond(dangling) else {
      fail("expected response")
    }
    assert_true(dangling.is_error)
    assert_false(@fs.exists("\{dir}/missing.bin"))

    let target = "\{dir}/old.bin"
    let link = "\{dir}/alias.bin"
    @fs.write_binary(target, b"old")
    @fs.symlink(target="old.bin", link)
    guard run_copy(tool, { "destination": "alias.bin", "source": "candidate" })
      is Respond(out) else {
      fail("expected response")
    }
    assert_false(out.is_error, msg=out.content)
    assert_true(@fs.kind(link, follow_symlink=false) is SymLink)
    assert_eq(@fs.read_binary(target), b"\xff\x00")
    let entries = @fs.readdir(dir, include_hidden=true)
    assert_eq(entries.length(), 4)
    assert_true(entries.contains("alias.bin"))
    assert_true(entries.contains("candidate"))
    assert_true(entries.contains("dangling.bin"))
    assert_true(entries.contains("old.bin"))
  })
}
