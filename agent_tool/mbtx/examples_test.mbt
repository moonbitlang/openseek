///|
/// The PTC examples under share/examples are shown to the model inline by the
/// system prompt; these tests run them through the real sandbox and host so
/// what the model is shown is what the host accepts. `dispatch` comes from
/// mbtx_test.mbt.
async fn example_source(name : String) -> String {
  @fs.read_file(@fs.realpath("share/examples/\{name}")).text()
}

///|
async test "ptc_guarded_edit example applies a clean fix and reports a reverted one" {
  @vfs.with_tmpdir(ws => {
    @async.with_task_group(group => {
      let lib =
        #|///|
        #|#deprecated("use `len` instead")
        #|pub fn length(xs : Array[Int]) -> Int {
        #|  xs.length()
        #|}
        #|
        #|///|
        #|pub fn len(xs : Array[Int]) -> Int {
        #|  xs.length()
        #|}
        #|
        #|///|
        #|pub fn total() -> Int {
        #|  length([1, 2, 3]) + length([4])
        #|}
        #|
      @vfs.FileSystem::from_pairs([
        ("moon.mod", "name = \"tmp/example\"\n"),
        ("lib/moon.pkg", ""),
        ("lib/lib.mbt", lib),
      ]).write_to(ws)
      let state = @agent_tool.FileStateMap()
      let service = @ptc.Service::start(
        group,
        Tools([
          state.serialize(@edit.definition(workspace_root=ws, file_state=state)),
        ]),
      )
      let tool = @mbtx.definition(
        workspace_root=ws,
        file_state=state,
        program_service=service,
        foreground_timeout_ms=120000,
      )
      let source = example_source("ptc_guarded_edit.mbtx")
      let path = "\{ws}/lib/lib.mbt"
      let applied = @async.with_timeout(180000, () => {
        dispatch(tool, {
          "description": "guarded edit example",
          "ptc": true,
          "source": source,
          "cwd": ws,
          "args": [path, "length([1, 2, 3])", "len([1, 2, 3])", "14"],
        })
      })
      assert_false(applied.is_error, msg=applied.content)
      assert_true(
        applied.content.contains("applied; 1 warning(s) remain"),
        msg=applied.content,
      )
      assert_true(
        @fs.read_file(path).text().contains("len([1, 2, 3]) + length([4])"),
      )
      // A fix that leaves an unused binding behind is reverted by the host,
      // and the script reports the counts it was given.
      let reverted = @async.with_timeout(180000, () => {
        dispatch(tool, {
          "description": "guarded edit example",
          "ptc": true,
          "source": source,
          "cwd": ws,
          "args": [
            path, "  len([1, 2, 3]) + length([4])", "  let unused = 0\n  len([1, 2, 3]) + len([4])",
            "14",
          ],
        })
      })
      assert_false(reverted.is_error, msg=reverted.content)
      assert_true(
        reverted.content.contains(
          "reverted: the warning count changed by 0 (>= revert_if_warning_delta_greater_or_equal=0)",
        ),
        msg=reverted.content,
      )
      assert_true(
        @fs.read_file(path).text().contains("len([1, 2, 3]) + length([4])"),
      )
    })
  })
}

///|
async test "ptc_search_filter example keeps the selected sources with their URLs" {
  @vfs.with_tmpdir(ws => {
    @async.with_task_group(group => {
      let search = @agent_tool.AgentToolDefinition(
        name="web_search",
        description="offline search",
        schema=JsonSchema({}),
        program_callable=true,
        concurrent_safe=true,
        execute=Sync(_ => {
          @agent_tool.respond("sources", data={
            "sources": [
              { "url": "https://docs.python.org/3/", "title": "Python docs" },
              { "url": "https://example.com/other", "snippet": "not it" },
            ],
            "truncated": true,
          })
        }),
      )
      let service = @ptc.Service::start(group, Tools([search]))
      let tool = @mbtx.definition(workspace_root=ws, program_service=service)
      let output = @async.with_timeout(120000, () => {
        dispatch(tool, {
          "description": "search example",
          "ptc": true,
          "source": example_source("ptc_search_filter.mbtx"),
          "cwd": ws,
          "args": ["python", "python.org"],
        })
      })
      assert_false(output.is_error, msg=output.content)
      assert_true(
        output.content.contains("- Python docs — https://docs.python.org/3/"),
        msg=output.content,
      )
      assert_true(
        output.content.contains("1 of 2 source(s) shown for python"),
        msg=output.content,
      )
      assert_true(
        output.content.contains("note: the search results were truncated"),
        msg=output.content,
      )
      assert_false(output.content.contains("example.com"))
    })
  })
}
