///|
async fn operation_result(
  tool : @agent_tool.AgentToolDefinition,
  args : Json,
) -> @agent_tool.ToolOutput {
  let action = @agent_tool.execute_tool_call(
    @agent_tool.AgentToolCall::from_arguments(tool.name, args),
    Tools([tool]),
  )
  guard action is Respond(out) else { fail("expected response") }
  out
}

///|
async test "operation approval is one-shot for write and remove and never widens the original scope" {
  @vfs.with_tmpdir(ws => {
    @fs.mkdir("\{ws}/allowed")
    guard @write_scope.WriteScope::create(root=ws, allowed_paths=["allowed"])
      is Ok(scope) else {
      fail("scope")
    }
    let asked : Array[String] = []
    let channel = @agent_runtime.ApprovalChannel(ask => {
      asked.push(ask.tool_name)
      AllowedOnce
    })
    for name in ["write", "remove"] {
      let path = "\{ws}/outside-\{name}.txt"
      @fs.write_file(path, "old")
      let tool = match name {
        "write" =>
          @write.definition(
            workspace_root=ws,
            write_scope=scope,
            approval=channel,
          )
        _ =>
          @remove.definition(
            workspace_root=ws,
            write_scope=scope,
            approval=channel,
          )
      }
      let args : Json = match name {
        "write" => { "path": path, "content": "new" }
        _ => { "path": path, "reason": "cleanup" }
      }
      for _ in 0..<2 {
        @fs.write_file(path, "old", create_mode=CreateOrTruncate)
        let out = operation_result(tool, args)
        assert_false(out.is_error, msg=out.content.text())
        assert_true(scope.deny_reason(path) is Some(_))
        if name == "remove" {
          assert_false(@fs.exists(path))
        } else {
          assert_eq(@fs.read_file(path).text(), "new")
        }
      }
    }
    assert_eq(asked, ["write", "write", "remove", "remove"])
    let new_path = "\{ws}/new-parent/new.txt"
    let out = operation_result(
      @write.definition(write_scope=scope, approval=channel),
      { "path": new_path, "content": "created" },
    )
    assert_false(out.is_error, msg=out.content.text())
    assert_eq(@fs.read_file(new_path).text(), "created")
  })
}

///|
async test "operation approval never asks for invalid arguments or invalid source" {
  @vfs.with_tmpdir(ws => {
    @fs.write_file("\{ws}/a.txt", "old")
    guard @write_scope.WriteScope::create(root=ws, allowed_paths=["allowed"])
      is Ok(scope) else {
      fail("scope")
    }
    let asks = Ref(0)
    let approval = @agent_runtime.ApprovalChannel(_ => {
      asks.val += 1
      AllowedOnce
    })
    let cases : Array[(@agent_tool.AgentToolDefinition, Json)] = [
      (
        @write.definition(workspace_root=ws, write_scope=scope, approval~),
        { "path": "bad.mbt", "content": "fn broken( {" },
      ),
      (
        @write.definition(workspace_root=ws, write_scope=scope, approval~),
        { "path": "x" },
      ),
      (
        @remove.definition(workspace_root=ws, write_scope=scope, approval~),
        { "path": ".", "reason": "cleanup" },
      ),
    ]
    for (tool, args) in cases {
      assert_true(operation_result(tool, args).is_error)
    }
    assert_eq(asks.val, 0)
    assert_eq(@fs.read_file("\{ws}/a.txt").text(), "old")
    assert_false(@fs.exists("\{ws}/bad.mbt"))
  })
}

///|
async test "operation approval preserves targets on rejection cancellation unavailability or concurrent edits" {
  @vfs.with_tmpdir(ws => {
    let path = "\{ws}/outside.txt"
    guard @write_scope.WriteScope::create(root=ws, allowed_paths=["allowed"])
      is Ok(scope) else {
      fail("scope")
    }
    for outcome in [@agent_runtime.Rejected, Cancelled, Unavailable] {
      @fs.write_file(path, "old", create_mode=CreateOrTruncate)
      let out = operation_result(
        @write.definition(
          write_scope=scope,
          approval=ApprovalChannel(_ => outcome),
        ),
        { "path": path, "content": "new" },
      )
      assert_true(out.is_error)
      assert_eq(@fs.read_file(path).text(), "old")
    }
    let state = @agent_tool.FileStateMap()
    let tool = @write.definition(
      file_state=state,
      write_scope=scope,
      approval=ApprovalChannel(_ => {
        state.with_access(() => {
          @fs.write_file(path, "external", create_mode=CreateOrTruncate)
        })
        AllowedOnce
      }),
    )
    let out = @async.with_timeout(2000, () => {
      operation_result(tool, { "path": path, "content": "new" })
    })
    assert_true(out.is_error)
    assert_true(out.content.contains("changed while awaiting approval"))
    assert_eq(@fs.read_file(path).text(), "external")
  })
}

///|
async test "operation approval pins prospective paths and rejects symlink redirection" {
  @vfs.with_tmpdir(ws => {
    @fs.mkdir("\{ws}/first")
    @fs.mkdir("\{ws}/second")
    @fs.symlink("\{ws}/alias", target="\{ws}/first")
    guard @write_scope.WriteScope::create(root=ws, allowed_paths=["allowed"])
      is Ok(scope) else {
      fail("scope")
    }
    let tool = @write.definition(
      workspace_root=ws,
      write_scope=scope,
      approval=ApprovalChannel(_ => {
        @fs.remove("\{ws}/alias")
        @fs.symlink("\{ws}/alias", target="\{ws}/second")
        AllowedOnce
      }),
    )
    let out = operation_result(tool, {
      "path": "alias/new.txt",
      "content": "new",
    })
    assert_true(out.is_error)
    assert_false(@fs.exists("\{ws}/first/new.txt"))
    assert_false(@fs.exists("\{ws}/second/new.txt"))
  })
}

///|
async test "edit tools retain scope restrictions in direct and programmatic calls" {
  @vfs.with_tmpdir(ws => {
    @vfs.FileSystem({ "allowed/a": "old", "outside": "old" }).write_to(ws)
    guard @write_scope.WriteScope::create(root=ws, allowed_paths=["allowed"])
      is Ok(scope) else {
      fail("scope")
    }
    let state = @agent_tool.FileStateMap()
    let tools = @agent_tool.Tools([
      state.serialize(
        @edit.definition(workspace_root=ws, write_scope=scope, file_state=state),
      ),
      state.serialize(
        @multi_edit.definition(
          workspace_root=ws,
          write_scope=scope,
          file_state=state,
        ),
      ),
    ])
    let outside : Json = {
      "file": "outside",
      "old_string": "old",
      "new_string": "new",
      "start_line": 1,
    }
    let calls : Array[(String, Json)] = [
      (
        "edit",
        {
          "path": "outside",
          "old_string": "old",
          "new_string": "new",
          "start_line": 1,
        },
      ),
      (
        "multi_edit",
        {
          "edits": [
            {
              "file": "allowed/a",
              "old_string": "old",
              "new_string": "new",
              "start_line": 1,
            },
            outside,
          ],
        },
      ),
    ]
    for registry in [tools, tools.program_tools()] {
      for (name, args) in calls {
        guard registry.find(name) is Some(tool) else { fail("missing tool") }
        assert_false(tool.can_request_approval())
        let out = operation_result(tool, args)
        assert_true(out.is_error)
        assert_true(out.content.contains("write blocked"))
        assert_eq(@fs.read_file("\{ws}/allowed/a").text(), "old")
        assert_eq(@fs.read_file("\{ws}/outside").text(), "old")
      }
    }
  })
}

///|
async test "operation approval permits a validated full source replacement but never invalid source" {
  @vfs.with_tmpdir(ws => {
    let path = "\{ws}/template.mbt"
    let before = "///|\nfn template() -> Int { 1 }\n"
    let after = "///|\nfn template() -> Int { 2 }\n"
    @fs.write_file(path, before)
    let asks = Ref(0)
    let tool = @write.definition(
      approval=ApprovalChannel(ask => {
        asks.val += 1
        assert_true(ask.detail.contains("overwrite an existing source file"))
        assert_true(ask.body is Some(body) && body.contains("template.mbt"))
        AllowedOnce
      }),
    )
    let invalid = operation_result(tool, {
      "path": path,
      "content": "fn invalid( {",
    })
    assert_true(invalid.is_error)
    assert_eq(asks.val, 0)
    assert_eq(@fs.read_file(path).text(), before)
    let valid = operation_result(tool, { "path": path, "content": after })
    assert_false(valid.is_error, msg=valid.content.text())
    assert_eq(asks.val, 1)
    assert_eq(@fs.read_file(path).text(), after)
  })
}
