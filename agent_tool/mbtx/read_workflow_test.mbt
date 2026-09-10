///|
/// Run with OPENSEEK_REFERENCES=<checkout>/share to exercise the public
/// namespace; otherwise use this checkout's script, never another installation.
async fn read_workflow_filename() -> String {
  if @env.get_env_var("OPENSEEK_REFERENCES") == Some(@fs.realpath("share")) {
    "@builtin/read.mbtx"
  } else {
    @fs.realpath("share/workflow/read.mbtx")
  }
}

///|
async test "read workflow batches whole files inclusive ranges empty files and EOF" {
  let filename = read_workflow_filename()
  @vfs.with_tmpdir(ws => {
    @vfs.FileSystem({
      "nested/source.mbt": "alpha\nbeta\ngamma\n",
      "nested/empty": "",
      "nested/newline": "\n",
      "nested/space name": "spaces",
    }).write_to(ws)
    let out = run_in(ws, {
      "filename": filename,
      "cwd": "nested",
      "args": [
        "source.mbt:2:3", "empty", "newline", "source.mbt:99", "space name", "source.mbt:3",
      ],
    })
    assert_false(out.is_error, msg=out.content)
    assert_eq(
      out.content,
      (
        #|=== "source.mbt" ===
        #|2 |beta
        #|3 |gamma
        #|<system>start_line=2 shown_lines=2 total_lines=4 truncated=false</system>
        #|=== "empty" ===
        #|<system>start_line=1 shown_lines=0 total_lines=0 truncated=false note=empty file</system>
        #|=== "newline" ===
        #|1 |
        #|2 |
        #|<system>start_line=1 shown_lines=2 total_lines=2 truncated=false</system>
        #|=== "source.mbt" ===
        #|<system>start_line=99 shown_lines=0 total_lines=4 truncated=false</system>
        #|=== "space name" ===
        #|1 |spaces
        #|<system>start_line=1 shown_lines=1 total_lines=1 truncated=false</system>
        #|=== "source.mbt" ===
        #|3 |gamma
        #|4 |
        #|<system>start_line=3 shown_lines=2 total_lines=4 truncated=false</system>
        #|
      ),
    )
    let huge = run_in(ws, {
      "filename": filename,
      "args": ["nested/source.mbt:2:2147483647"],
    })
    assert_false(huge.is_error, msg=huge.content)
    assert_true(
      huge.content.contains("shown_lines=3 total_lines=4 truncated=false"),
    )
  })
}

///|
async test "read workflow continues after distinct file errors and fails the call" {
  let filename = read_workflow_filename()
  @vfs.with_tmpdir(ws => {
    @fs.mkdir("\{ws}/directory")
    @fs.write_file("\{ws}/invalid", b"\xff", create_mode=CreateOrTruncate)
    @fs.write_file("\{ws}/ok", "still read", create_mode=CreateOrTruncate)
    let out = run_in(ws, {
      "filename": filename,
      "args": ["missing", "directory", "invalid", "ok"],
    })
    assert_true(out.is_error, msg=out.content)
    assert_true(
      out.content.contains("=== \"missing\" ===\nerror reading file:"),
    )
    assert_true(out.content.contains("path is a directory; list it with mbtx"))
    assert_true(
      out.content.contains("=== \"invalid\" ===\nerror reading file:"),
    )
    assert_true(out.content.contains("1 |still read"))
    assert_false(out.content.contains("Failure("))
    assert_false(out.content.contains("mbtx sandbox:"))
  })
}

///|
async test "read workflow caps Unicode gutters and the whole foreground batch successfully" {
  let filename = read_workflow_filename()
  @vfs.with_tmpdir(ws => {
    @fs.write_file("\{ws}/emoji", "A😀B", create_mode=CreateOrTruncate)
    @fs.write_file(
      "\{ws}/large",
      "界".repeat(50_000),
      create_mode=CreateOrTruncate,
    )
    let tiny = run_in(ws, {
      "filename": filename,
      "args": ["--max-output-chars", "5", "emoji"],
    })
    assert_false(tiny.is_error, msg=tiny.content)
    assert_true(tiny.content.contains("1 |A\n<system>"), msg=tiny.content)
    assert_true(tiny.content.contains("truncated=true"))
    let gutter = run_in(ws, {
      "filename": filename,
      "args": ["--max-output-chars", "1", "emoji"],
    })
    assert_false(gutter.is_error, msg=gutter.content)
    assert_true(
      gutter.content.contains("shown_lines=0 total_lines=1 truncated=true"),
    )
    // This uses the retained foreground runner, which would STOP at 48000 bytes.
    @async.with_task_group() <| group => {
      let scope = @agent_runtime.AgentTaskScope(group)
      let runtime = @bgjobs.BgJobRuntime(scope, spill_dir=ws)
      let out = dispatch(
        @mbtx.definition(workspace_root=ws, bg_runtime=runtime, job_dir=ws),
        {
          "filename": filename,
          "args": ["--max-output-chars", "50000", "large", "large", "emoji"],
        },
      )
      assert_false(out.is_error, msg=out.content)
      assert_true(out.content.contains("truncated=true"))
      assert_true(out.content.contains("skipped_files=2"))
      assert_true(@utf8.encode(out.content).length() <= 40_000)
      assert_false(out.content.contains("STOPPED"))
      assert_false(out.content.contains("�"))
    }
  })
}

///|
async test "read workflow errors explain invalid selectors and arguments" {
  let filename = read_workflow_filename()
  @vfs.with_tmpdir(ws => {
    for
      args in [
        [],
        ["x:0"],
        ["x:-1"],
        ["x:5:4"],
        ["x:2147483648"],
        ["--max-output-chars", "0"],
        ["--literal"],
        ["--unknown"],
        [""],
      ] {
      let out = run_in(ws, { "filename": filename, "args": args })
      assert_true(out.is_error, msg=out.content)
      assert_true(out.content.contains("error: read "), msg=out.content)
      assert_false(out.content.contains("Failure("))
    }
    let help = run_in(ws, { "filename": filename, "args": ["--help"] })
    assert_false(help.is_error, msg=help.content)
    assert_true(help.content.contains("inclusive and 1-based"))
  })
}

///|
#cfg(not(platform="windows"))
async test "read workflow parses colons from the right and has literal paths" {
  let filename = read_workflow_filename()
  @vfs.with_tmpdir(ws => {
    @fs.write_file(
      "\{ws}/C:\\src\\main.mbt",
      "drive\nselected",
      create_mode=CreateOrTruncate,
    )
    @vfs.FileSystem({ "log:120": "literal", "--flag": "option name" }).write_to(
      ws,
    )
    let out = run_in(ws, {
      "filename": filename,
      "args": ["C:\\src\\main.mbt:2:2", "--literal", "log:120", "--", "--flag"],
    })
    assert_false(out.is_error, msg=out.content)
    assert_true(out.content.contains("2 |selected"))
    assert_true(out.content.contains("1 |literal"))
    assert_true(out.content.contains("1 |option name"))
  })
}

///|
async test "read workflow reads absolute paths and sandbox wording as ordinary source" {
  let filename = read_workflow_filename()
  @vfs.with_tmpdir(ws => {
    @vfs.with_tmpdir(outside => {
      let path = "\{outside}/sample.mbt"
      let source = "Sandbox policy blocked file write: \"x.mbt\"\nOSError(\"@process.spawn(): Permission denied\")\nx.mbt: Operation not permitted"
      @fs.write_file(path, source, create_mode=CreateOrTruncate)
      let out = dispatch(@mbtx.definition(workspace_root=ws, read_only=true), {
        "filename": filename,
        "args": [path],
      })
      assert_false(out.is_error, msg=out.content)
      assert_true(out.content.contains("1 |Sandbox policy blocked"))
      assert_true(out.content.contains("3 |x.mbt: Operation not permitted"))
      assert_false(out.content.contains("mbtx sandbox:"))
    })
  })
}
