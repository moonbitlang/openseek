///|
async test "PTC real script edits and receives reply without deadlock" {
  @vfs.with_tmpdir(ws => {
    @async.with_task_group(group => {
      @fs.write_file("\{ws}/note.txt", "old\n")
      let state = @agent_tool.FileStateMap()
      state.record_created(
        "\{ws}/note.txt",
        @agent_tool.content_digest("old\n"),
      )
      let definitions = [
        state.serialize(@edit.definition(workspace_root=ws, file_state=state)),
        state.serialize(
          @multi_edit.definition(workspace_root=ws, file_state=state),
        ),
      ]
      let service = @ptc.Service::start(group, Tools(definitions))
      let tool = @mbtx.definition(
        workspace_root=ws,
        file_state=state,
        program_service=service,
        foreground_timeout_ms=5000,
      )
      let output = @async.with_timeout(30000, () => {
        dispatch(tool, {
          "ptc": true,
          "source": (
            #|import { "bobzhang/openseek_tools@0.1.0" @tools, "moonbitlang/async" }
            #|async fn main {
            #|  let result = @tools.call("edit", { "path": "note.txt", "start_line": 1, "old_string": "old", "new_string": "new" })
            #|  if result.is_error { fail(result.content) }
            #|  let batch = @tools.call("multi_edit", { "edits": [
            #|    { "file": "note.txt", "start_line": 1, "old_string": "new", "new_string": "final" },
            #|  ] })
            #|  if batch.is_error { fail(batch.content) }
            #|  let rejected = @tools.call("multi_edit", { "edits": [
            #|    { "file": "note.txt", "start_line": 1, "old_string": "final", "new_string": "wrong" },
            #|    { "file": "note.txt", "start_line": 2, "old_string": "missing", "new_string": "wrong" },
            #|  ] })
            #|  if !rejected.is_error { fail("invalid batch accepted") }
            #|  println("reply received")
            #|}
          ),
        })
      })
      assert_false(output.is_error, msg=output.content)
      assert_true(output.content.contains("reply received"))
      assert_eq(@fs.read_file("\{ws}/note.txt").text(), "final\n")
      assert_true(
        state.created_and_unchanged(
          "\{ws}/note.txt",
          @agent_tool.content_digest("final\n"),
        ),
      )
      assert_true(
        output.data
        is Some(
          {
            "ptc_calls": [
              {
                "name": "edit",
                "status": "done",
                "result": { "is_error": false, .. },
                ..
              },
              ..,
            ],
            ..
          }
        ),
      )
    })
  })
}

///|
async test "PTC real script preserves imports and structured results" {
  @vfs.with_tmpdir(ws => {
    @async.with_task_group(group => {
      let probe = @agent_tool.AgentToolDefinition(
        name="web_search",
        description="offline search",
        schema=JsonSchema({}),
        program_callable=true,
        concurrent_safe=true,
        execute=Sync(_ => {
          @agent_tool.respond("sources", data={
            "sources": [{ "url": "https://example.com" }],
            "truncated": false,
          })
        }),
      )
      let service = @ptc.Service::start(group, Tools([probe]))
      let tool = @mbtx.definition(workspace_root=ws, program_service=service)
      let output = dispatch(tool, {
        "ptc": true,
        "source": (
          #|///|
          #|import { "bobzhang/openseek_tools@0.1.0" @tools, "moonbitlang/async", "moonbitlang/async/fs" @files, }
          #|async fn main {
          #|  let result = @tools.call("web_search", { "query": "query" })
          #|  guard result.data is Some({ "sources": [{ "url": String(url), .. }], .. }) else { fail("missing data") }
          #|  println(url)
          #|  let denied = @tools.call("mbtx", {})
          #|  if !denied.is_error { fail("recursive mbtx was allowed") }
          #|}
        ),
      })
      assert_false(output.is_error, msg=output.content)
      assert_true(output.content.contains("https://example.com"))
    })
  })
}

///|
async test "PTC without a job runtime stays foreground and saves reusable original source" {
  @vfs.with_tmpdir(ws => {
    @async.with_task_group(group => {
      let service = @ptc.Service::start(group, Tools([]))
      let definition = @mbtx.definition(
        workspace_root=ws,
        job_dir=ws,
        auto_background_after_ms=1,
        foreground_timeout_ms=10000,
        program_service=service,
      )
      let source =
        #|import { "bobzhang/openseek_tools@0.1.0" @tools, "moonbitlang/async" @a, "moonbitlang/async/http" @h, "moonbitlang/core/json" @j, "moonbitlang/core/env" @e }
        #|async fn main {
        #|  @a.sleep(50)
        #|  let denied = @tools.call("mbtx", {})
        #|  if !denied.is_error { fail("recursive call allowed") }
        #|  println("foreground done")
        #|}
      for
        args in [
          ({ "ptc": true, "source": source, "filename": "saved.mbtx" } : Json),
          { "ptc": true, "filename": "saved.mbtx" },
        ] {
        let output = dispatch(definition, args)
        assert_false(output.is_error, msg=output.content)
        assert_true(output.content.contains("foreground done"))
      }
      assert_eq(@fs.read_file("\{ws}/saved.mbtx").text(), source)
      for
        args in [
          ({ "ptc": true, "source": source, "subrun": true } : Json),
          { "ptc": true, "source": source, "escalated": true },
          { "ptc": true, "source": source, "target": "native" },
          { "ptc": "yes", "source": source },
        ] {
        assert_true(dispatch(definition, args).is_error)
      }
    })
  })
}

///|
async test "PTC foreground timeout stops the active host call before returning" {
  @vfs.with_tmpdir(ws => {
    @async.with_task_group(group => {
      let started = Ref(false)
      let stopped = Ref(false)
      let tool = @agent_tool.AgentToolDefinition(
        name="block",
        description="block",
        schema=JsonSchema({}),
        program_callable=true,
        execute=Async(_ => {
          started.val = true
          defer {
            stopped.val = true
          }
          @async.sleep(60000)
          @agent_tool.respond("unexpected")
        }),
      )
      let service = @ptc.Service::start(group, Tools([tool]))
      let output = @async.with_timeout(30000, () => {
        dispatch(
          @mbtx.definition(
            workspace_root=ws,
            program_service=service,
            foreground_timeout_ms=1000,
          ),
          {
            "ptc": true,
            "source": "import { \"bobzhang/openseek_tools@0.1.0\" @tools, \"moonbitlang/async\" }\nasync fn main { @tools.call(\"block\", {}).content |> println }",
          },
        )
      })
      assert_true(output.is_error, msg=output.content)
      assert_true(started.val)
      assert_true(stopped.val)
      assert_true(
        output.data
        is Some({ "ptc_calls": [{ "status": "interrupted", .. }], .. }),
      )
    })
  })
}

///|
async test "PTC leaves the script namespace and source unchanged" {
  @vfs.with_tmpdir(ws => {
    @async.with_task_group(group => {
      let source =
        #|let tools = "user-owned name"
        #|fn main { println(tools) }
      let service = @ptc.Service::start(group, Tools([]))
      let output = dispatch(
        @mbtx.definition(workspace_root=ws, program_service=service),
        { "ptc": true, "source": source, "filename": "unchanged.mbtx" },
      )
      assert_false(output.is_error, msg=output.content)
      assert_true(output.content.contains("user-owned name"))
      assert_eq(@fs.read_file("\{ws}/unchanged.mbtx").text(), source)
      // No tool call was made, so no trace is persisted with the result.
      assert_true(output.data is None)
    })
  })
}

///|
/// A registry without a PTC service does not advertise `ptc`; an explicit
/// request for it is refused rather than silently run without tools.
async test "explicit PTC without a session service is an error" {
  @vfs.with_tmpdir(ws => {
    let output = dispatch(@mbtx.definition(workspace_root=ws), {
      "ptc": true,
      "source": "fn main { println(1) }",
    })
    assert_true(output.is_error)
    assert_true(output.content.contains("unavailable"))
    // Omitted, null, or explicitly false: the plain path, no registration.
    for
      args in [
        ({ "source": "fn main { println(1) }" } : Json),
        { "ptc": null, "source": "fn main { println(1) }" },
        { "ptc": false, "source": "fn main { println(1) }" },
      ] {
      let output = dispatch(@mbtx.definition(workspace_root=ws), args)
      assert_false(output.is_error, msg=output.content)
      assert_true(output.data is None)
    }
  })
}
