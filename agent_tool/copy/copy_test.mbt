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
          {
            "source": "input.bin",
            "destination": "out.bin",
            "encoding": "base64",
          },
          "arguments.encoding",
        ),
      ] {
      guard run_copy(tool, arguments) is Respond(out) else {
        fail("expected response")
      }
      assert_true(out.is_error)
      assert_true(out.content.contains(message), msg=out.content)
      assert_false(@fs.exists("\{dir}/out.bin"))
    }
  })
}

///|
async test "copy copies arbitrary bytes and records their provenance" {
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
    // A staged read finishes before publication, including a self-copy.
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
async test "copy streams large binary files" {
  @vfs.with_tmpdir(dir => {
    let source = "\{dir}/large.bin"
    let file = @fs.open(source, mode=WriteOnly, create_mode=CreateNew)
    defer file.close()
    let chunk = Bytes::make(65536, b'\xff')
    for _ in 0..<272 {
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
    assert_eq(copied.length(), 17825795)
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
async test "copy binary approval permits only the selected write and preserves rejection" {
  @vfs.with_tmpdir(dir => {
    @fs.write_binary("\{dir}/candidate", b"\xff\x00")
    guard @write_scope.WriteScope::create(root=dir, allowed_paths=["allowed"])
      is Ok(scope) else {
      fail("expected scope")
    }
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
        // The grant is operation-local; the original scope remains unchanged.
        assert_true(scope.deny_reason("\{dir}/outside/new.bin") is Some(_))
      } else {
        assert_true(out.is_error)
        assert_false(@fs.exists("\{dir}/outside"))
      }
    }
  })
}

///|
async test "copy rejects a symlink retargeted during approval" {
  @vfs.with_tmpdir(dir => {
    let original = "fn f() -> Int { 1 }"
    @fs.write_text("\{dir}/one.bin", original)
    @fs.write_text("\{dir}/two.bin", original)
    @fs.symlink(target="one.bin", "\{dir}/alias.bin")
    @fs.write_text("\{dir}/candidate", "fn f() -> Int { 2 }")
    guard @write_scope.WriteScope::create(root=dir, allowed_paths=["allowed"])
      is Ok(scope) else {
      fail("expected scope")
    }
    let tool = @copy.definition(
      workspace_root=dir,
      write_scope=scope,
      approval=ApprovalChannel(_ => {
        @fs.remove("\{dir}/alias.bin")
        @fs.symlink(target="two.bin", "\{dir}/alias.bin")
        AllowedOnce
      }),
    )
    guard run_copy(tool, { "destination": "alias.bin", "source": "candidate" })
      is Respond(out) else {
      fail("expected response")
    }
    assert_true(out.is_error)
    assert_true(out.content.contains("changed while awaiting approval"))
    assert_eq(@fs.read_text("\{dir}/one.bin"), original)
    assert_eq(@fs.read_text("\{dir}/two.bin"), original)
  })
}

///|
async test "copy cancellation during approval preserves the target and releases the gate" {
  @vfs.with_tmpdir(dir => {
    @fs.write_text("\{dir}/candidate", "fn f() -> Int { 2 }")
    @fs.write_text("\{dir}/target.txt", "fn f() -> Int { 1 }")
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
    assert_eq(@fs.read_text("\{dir}/target.txt"), "fn f() -> Int { 1 }")
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
    assert_eq(@fs.read_text("\{dir}/target.txt"), "fn f() -> Int { 2 }")
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
async test "copy rejects missing and nonregular sources before touching the destination" {
  @vfs.with_tmpdir(dir => {
    for source in ["missing.bin", "."] {
      let tools = @agent_tool.Tools([@copy.definition(workspace_root=dir)])
      let arguments : Json = {
        "destination": "new/output.bin",
        "source": source,
      }
      let result = @agent_tool.execute_tool_call(
        AgentToolCall(
          ToolCall(id="copy", name="copy", arguments=arguments.stringify()),
        ),
        tools,
      )
      guard result is Respond(out) else { fail("expected response") }
      assert_true(out.is_error)
      assert_false(@fs.exists("\{dir}/new"))
    }
  })
}

///|
async test "copy preserves manifest UTF-8 and syntax checks including symlink targets" {
  @vfs.with_tmpdir(dir => {
    let tool = @copy.definition(workspace_root=dir)
    for
      (name, content, message) in [
        ("moon.mod", b"{\"name\":\"bad\"}", "current text syntax"),
        ("moon.mod.json", b"{}", "legacy"),
        ("pkg.generated.mbti", b"generated", "run moon info"),
        ("moon.pkg", b"# bad", "comment syntax"),
        ("source.mbt", b"\xff", "valid UTF-8"),
        ("source.mbti", b"\xff", "valid UTF-8"),
        ("script.mbtx", b"\xff", "valid UTF-8"),
        ("script.mbtx", b"fn f( {", "nothing was written"),
        ("source.mbt", b"fn f( {", "nothing was written"),
        ("doc.mbt.md", b"```mbt check\nfn f( {\n```", "nothing was written"),
      ] {
      @fs.write_binary("\{dir}/candidate", content)
      guard run_copy(tool, {
          "destination": "new/\{name}",
          "source": "candidate",
        })
        is Respond(out) else {
        fail("expected response")
      }
      assert_true(out.is_error, msg=out.content)
      assert_true(out.content.contains(message), msg=out.content)
      assert_false(@fs.exists("\{dir}/new"))
    }
    @fs.write_text("\{dir}/moon.pkg", "import {}\n")
    @fs.symlink(target="moon.pkg", "\{dir}/alias.bin")
    @fs.write_text("\{dir}/candidate", "{\"import\":{}}")
    guard run_copy(tool, {
        "destination": "alias.bin",
        "source": "candidate",
        "revert_on_parse_errors": false,
      })
      is Respond(out) else {
      fail("expected response")
    }
    assert_true(out.is_error)
    assert_true(out.content.contains("current text syntax"))
    assert_eq(@fs.read_text("\{dir}/moon.pkg"), "import {}\n")
    // Explicit parse opt-out still applies, without skipping UTF-8/manifest rules.
    @fs.write_text("\{dir}/candidate", "fn f( {")
    guard run_copy(tool, {
        "destination": "fixture.mbt",
        "source": "candidate",
        "revert_on_parse_errors": false,
      })
      is Respond(fixture) else {
      fail("expected response")
    }
    assert_false(fixture.is_error, msg=fixture.content)
  })
}

///|
async test "copy checks named MoonBit sources without waiting for the file gate" {
  @vfs.with_tmpdir(dir => {
    @fs.write_text("\{dir}/invalid.mbt", "fn f( {")
    let state = @agent_tool.FileStateMap()
    let tool = @copy.definition(workspace_root=dir, file_state=state)
    let result = @async.with_timeout(15000, () => {
      state.with_access(() => {
        run_copy(tool, {
          "destination": "new/source.mbt",
          "source": "invalid.mbt",
        })
      })
    })
    guard result is Respond(out) else { fail("expected response") }
    assert_true(out.is_error)
    assert_true(out.content.contains("has parse errors"), msg=out.content)
    assert_eq(@fs.readdir(dir, include_hidden=true), ["invalid.mbt"])
  })
}

///|
async test "copy new source approval displays and writes the fixed candidate" {
  @vfs.with_tmpdir(dir => {
    let source = "\{dir}/candidate"
    let path = "\{dir}/source.mbt"
    let candidate = "fn value() -> Int { 2 }\n"
    @fs.write_text(source, candidate)
    guard @write_scope.WriteScope::create(root=dir, allowed_paths=["allowed"])
      is Ok(scope) else {
      fail("expected scope")
    }
    let state = @agent_tool.FileStateMap()
    let tool = @copy.definition(
      workspace_root=dir,
      write_scope=scope,
      file_state=state,
      approval=ApprovalChannel(ask => {
        assert_true(
          ask.body is Some(body) && body.contains(candidate.trim().to_owned()),
        )
        // Approval releases the file gate, but changing the original source
        // cannot change the already checked candidate.
        state.with_access(() => @fs.write_text(source, "invalid ("))
        AllowedOnce
      }),
    )
    guard run_copy(tool, { "destination": "source.mbt", "source": "candidate" })
      is Respond(out) else {
      fail("expected response")
    }
    assert_false(out.is_error, msg=out.content)
    assert_eq(@fs.read_text(path), candidate)
    assert_eq(@fs.read_text(source), "invalid (")
    assert_true(state.get(path) is Some(Created))
  })
}

///|
async test "copy cannot bypass source overwrite rejection or destination write scopes" {
  @vfs.with_tmpdir(dir => {
    // Existing source targets must be rejected before decoding the candidate.
    @fs.write_binary("\{dir}/candidate", b"\xff")
    @fs.write_text("\{dir}/source.mbt", "fn f() -> Int { 1 }")
    @fs.symlink(target="source.mbt", "\{dir}/alias.bin")
    guard @write_scope.WriteScope::create(root=dir, allowed_paths=["allowed"])
      is Ok(scope) else {
      fail("expected scope")
    }
    for
      (tool, path, message) in [
        (
          @copy.definition(
            workspace_root=dir,
            approval=ApprovalChannel(_ => fail("must not ask")),
          ),
          "source.mbt",
          "cannot overwrite",
        ),
        (
          @copy.definition(
            workspace_root=dir,
            approval=ApprovalChannel(_ => fail("must not ask")),
          ),
          "alias.bin",
          "cannot overwrite",
        ),
        (
          @copy.definition(workspace_root=dir, write_scope=scope),
          "blocked/new.bin",
          "no approval channel",
        ),
      ] {
      guard run_copy(tool, { "destination": path, "source": "candidate" })
        is Respond(out) else {
        fail("expected response")
      }
      assert_true(out.is_error)
      assert_true(out.content.contains(message), msg=out.content)
    }
    assert_eq(@fs.read_text("\{dir}/source.mbt"), "fn f() -> Int { 1 }")
    assert_false(@fs.exists("\{dir}/blocked"))
  })
}

///|
async test "copy approvals retain binary metadata and allow changed destination contents" {
  @vfs.with_tmpdir(dir => {
    let path = "\{dir}/outside.bin"
    @fs.write_binary(path, b"\x00\xffbefore")
    @fs.write_binary("\{dir}/candidate", b"\x00\xffafter")
    guard @write_scope.WriteScope::create(root=dir, allowed_paths=["allowed"])
      is Ok(scope) else {
      fail("expected scope")
    }
    let tool = @copy.definition(
      workspace_root=dir,
      write_scope=scope,
      approval=ApprovalChannel(ask => {
        guard ask.body is Some(body) else { fail("missing approval body") }
        assert_true(body.contains("sha256"))
        assert_true(body.contains("content_omitted"))
        assert_false(body.contains("after"))
        @fs.write_binary(path, b"\x00\xffchange")
        AllowedOnce
      }),
    )
    guard run_copy(tool, { "destination": path, "source": "candidate" })
      is Respond(out) else {
      fail("expected response")
    }
    assert_false(out.is_error, msg=out.content)
    assert_eq(@fs.read_binary(path), b"\x00\xffafter")
  })
}

///|
async test "copy rejects a dangling destination symlink" {
  @vfs.with_tmpdir(dir => {
    @fs.symlink(target="new.bin", "\{dir}/alias.bin")
    @fs.write_binary("\{dir}/candidate", b"\xff")
    let tools = @agent_tool.Tools([@copy.definition(workspace_root=dir)])
    let arguments : Json = { "destination": "alias.bin", "source": "candidate" }
    guard @agent_tool.execute_tool_call(
        AgentToolCall(
          ToolCall(id="copy", name="copy", arguments=arguments.stringify()),
        ),
        tools,
      )
      is Respond(out) else {
      fail("expected response")
    }
    assert_true(out.is_error)
    assert_false(@fs.exists("\{dir}/new.bin"))
  })
}

///|
async test "copy atomically replaces the resolved file and preserves its symlink" {
  @vfs.with_tmpdir(dir => {
    let target = "\{dir}/old.bin"
    let link = "\{dir}/alias.bin"
    @fs.write_binary(target, b"old")
    @fs.write_binary("\{dir}/candidate", b"\xff\x00")
    @fs.symlink(target="old.bin", link)
    let tool = @copy.definition(workspace_root=dir)
    guard run_copy(tool, { "destination": "alias.bin", "source": "candidate" })
      is Respond(out) else {
      fail("expected response")
    }
    assert_false(out.is_error, msg=out.content)
    assert_true(@fs.kind(link, follow_symlink=false) is SymLink)
    assert_eq(@fs.read_binary(target), b"\xff\x00")
    let entries = @fs.readdir(dir, include_hidden=true)
    assert_eq(entries.length(), 3)
    assert_true(entries.contains("alias.bin"))
    assert_true(entries.contains("candidate"))
    assert_true(entries.contains("old.bin"))
  })
}
