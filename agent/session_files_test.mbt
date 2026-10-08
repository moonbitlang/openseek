///|
async fn scratch_call(
  tools : @agent_tool.Tools,
  name : String,
  arguments : Json,
) -> @agent_tool.ToolOutput {
  guard tools.find(name) is Some(tool) && tool.execute is Async(run) else {
    fail("missing async tool \{name}")
  }
  guard run(arguments) is Respond(output) else { fail("expected response") }
  output
}

///|
async test "session scratch survives PTC execution and registry restart" {
  let root = @fs.tmpdir(prefix="openseek-session-files-")
  defer @fs.rmdir(root, recursive=true)
  let workspace = "\{root}/project"
  let scratch = "\{root}/sessions/one/scratch"
  @fs.mkdir(workspace)
  @fs.write_file("\{workspace}/target.txt", "before\n")
  @async.with_task_group(group => {
    let tools = @agent.build_tools(
      AgentRuntime(workspace_root=workspace),
      AgentTaskScope(group),
      session_scratch_dir=scratch,
    )
    let generated = scratch_call(tools, "mbtx", {
      "filename": "@session/scripts/prepare.mbtx",
      "source": (
        #|import { "moonbitlang/openseek_tools@0.2.0" @tools, "moonbitlang/async" }
        #|async fn main {
        #|  let edits : Json = [{"file":"target.txt","old_string":"before","new_string":"after","start_line":1}]
        #|  let result = @tools.call("write", {"path":"@session/edits.json","content":edits.stringify()})
        #|  if result.is_error { fail(result.content) }
        #|  println("saved edits")
        #|}
      ),
    })
    assert_false(generated.is_error, msg=generated.content)
    let edited = scratch_call(tools, "multi_edit", {
      "edits_file": "@session/edits.json",
    })
    assert_false(edited.is_error, msg=edited.content)
    assert_eq(@fs.read_file("\{workspace}/target.txt").text(), "after\n")
    let read = scratch_call(tools, "mbtx", {
      "filename": "@builtin/read.mbtx",
      "args": ["@session/edits.json:1:1"],
    })
    assert_false(read.is_error, msg=read.content)
    assert_true(read.content.contains("target.txt"))
  })
  assert_true(@fs.exists("\{scratch}/edits.json"))
  @async.with_task_group(group => {
    let tools = @agent.build_tools(
      AgentRuntime(workspace_root=workspace),
      AgentTaskScope(group),
      session_scratch_dir=scratch,
    )
    let rerun = scratch_call(tools, "mbtx", {
      "filename": "@session/scripts/prepare.mbtx",
    })
    assert_false(rerun.is_error, msg=rerun.content)
    let removed = scratch_call(tools, "remove", {
      "path": "@session/scripts",
      "reason": "finished",
    })
    assert_false(removed.is_error, msg=removed.content)
    assert_false(@fs.exists("\{scratch}/scripts"))
  })
}

///|
async test "session scratch isolates sessions and rejects invalid namespace paths" {
  let root = @fs.tmpdir(prefix="openseek-session-isolation-")
  defer @fs.rmdir(root, recursive=true)
  for name in ["one", "two"] {
    @async.with_task_group(group => {
      let tools = @agent.build_tools(
        AgentRuntime(workspace_root=root),
        AgentTaskScope(group),
        session_scratch_dir="\{root}/\{name}/scratch",
      )
      let written = scratch_call(tools, "write", {
        "path": "@session/value",
        "content": name,
      })
      assert_false(written.is_error, msg=written.content)
      for
        path in [
          "@session/", "@session/../value", "@session/a/../../value", "@session/./value",
          "@session/a\\value", "@session//value", "@other/value",
        ] {
        let output = scratch_call(tools, "write", {
          "path": path,
          "content": "bad",
        })
        assert_true(output.is_error, msg=path)
      }
      let removed = scratch_call(tools, "remove", {
        "path": "@session/",
        "reason": "invalid root removal",
      })
      assert_true(removed.is_error)
      let literal = scratch_call(tools, "write", {
        "path": "./@session/literal",
        "content": "project file",
      })
      assert_false(literal.is_error, msg=literal.content)
    })
  }
  assert_eq(@fs.read_file("\{root}/one/scratch/value").text(), "one")
  assert_eq(@fs.read_file("\{root}/two/scratch/value").text(), "two")
  assert_eq(@fs.read_file("\{root}/@session/literal").text(), "project file")
}

///|
#cfg(not(platform="windows"))
async test "session scratch refuses symlink escapes even without an approval channel" {
  let root = @fs.tmpdir(prefix="openseek-session-links-")
  defer @fs.rmdir(root, recursive=true)
  let scratch = "\{root}/scratch"
  @fs.mkdir(scratch)
  @fs.write_file("\{root}/outside", "keep")
  @fs.symlink(target="\{root}/outside", "\{scratch}/link")
  @fs.symlink(target=root, "\{scratch}/parent")
  @fs.symlink(target="\{root}/missing", "\{scratch}/dangling")
  @async.with_task_group(group => {
    let tools = @agent.build_tools(
      AgentRuntime(workspace_root=root),
      AgentTaskScope(group),
      session_scratch_dir=scratch,
    )
    for path in ["@session/link", "@session/parent/new", "@session/dangling"] {
      let output = scratch_call(tools, "write", {
        "path": path,
        "content": "bad",
      })
      assert_true(output.is_error, msg=path)
    }
    let output = scratch_call(tools, "multi_edit", {
      "edits_file": "@session/link",
    })
    assert_true(output.is_error)
  })
  assert_eq(@fs.read_file("\{root}/outside").text(), "keep")
  assert_false(@fs.exists("\{root}/new"))
  assert_false(@fs.exists("\{root}/missing"))
}

///|
async test "session scratch edits can mix project and session targets" {
  let root = @fs.tmpdir(prefix="openseek-session-edits-")
  defer @fs.rmdir(root, recursive=true)
  let scratch = "\{root}/scratch"
  @fs.write_file("\{root}/project.txt", "before")
  @async.with_task_group(group => {
    let tools = @agent.build_tools(
      AgentRuntime(workspace_root=root),
      AgentTaskScope(group),
      session_scratch_dir=scratch,
    )
    assert_false(@fs.exists(scratch))
    let write = scratch_call(tools, "write", {
      "path": "@session/notes.txt",
      "content": "before",
    })
    assert_false(write.is_error, msg=write.content)
    let edit = scratch_call(tools, "edit", {
      "path": "@session/notes.txt",
      "old_string": "before",
      "new_string": "middle",
      "start_line": 1,
    })
    assert_false(edit.is_error, msg=edit.content)
    let batch = scratch_call(tools, "multi_edit", {
      "edits": [
        {
          "file": "project.txt",
          "old_string": "before",
          "new_string": "after",
          "start_line": 1,
        },
        {
          "file": "@session/notes.txt",
          "old_string": "middle",
          "new_string": "after",
          "start_line": 1,
        },
      ],
    })
    assert_false(batch.is_error, msg=batch.content)
    assert_eq(@fs.read_file("\{root}/project.txt").text(), "after")
    assert_eq(@fs.read_file("\{scratch}/notes.txt").text(), "after")
    for value in ["let scratch_value = 1\n", "let scratch_value = 2\n"] {
      let output = scratch_call(tools, "write", {
        "path": "@session/value.mbt",
        "content": value,
      })
      assert_false(output.is_error, msg=output.content)
    }
    let invalid = scratch_call(tools, "multi_edit", {
      "edits": [
        {
          "file": "@session/../project.txt",
          "old_string": "after",
          "new_string": "bad",
          "start_line": 1,
        },
      ],
    })
    assert_true(invalid.is_error)
    assert_eq(@fs.read_file("\{root}/project.txt").text(), "after")
  })
}
