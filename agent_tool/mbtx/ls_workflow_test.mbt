///|
async test "@builtin/ls.mbtx lists cwd hidden entries and multiple directories" {
  @vfs.with_tmpdir(ws => {
    @vfs.FileSystem({
      "nested/z": "",
      "nested/a": "",
      "nested/.hidden": "",
      "nested/sub/child": "",
    }).write_to(ws)
    @fs.mkdir("\{ws}/empty")
    let out = run_in(ws, { "filename": "@builtin/ls.mbtx", "cwd": "nested" })
    assert_false(out.is_error, msg=out.content)
    assert_eq(
      out.content,
      (
        #|=== "." ===
        #|file "a"
        #|directory "sub"
        #|file "z"
        #|<system>shown_entries=3 total_entries=3 truncated=false entry_errors=0</system>
        #|
      ),
    )
    for flag in ["-a", "--all"] {
      let all = run_in(ws, {
        "filename": "@builtin/ls.mbtx",
        "args": [flag, "nested", "\{ws}/empty"],
      })
      assert_false(all.is_error, msg=all.content)
      assert_true(all.content.contains("file \".hidden\""))
      assert_true(all.content.contains("shown_entries=4 total_entries=4"))
      assert_true(all.content.contains("shown_entries=0 total_entries=0"))
      assert_false(all.content.contains("\"child\""))
      assert_false(all.content.contains("directory \"..\""))
    }
  })
}

///|
async test "ls workflow reports errors and continues with later directories" {
  @vfs.with_tmpdir(ws => {
    @vfs.FileSystem({ "file": "", "ok/entry": "" }).write_to(ws)
    let out = run_in(ws, {
      "filename": "@builtin/ls.mbtx",
      "args": ["missing", "file", "ok"],
    })
    assert_true(out.is_error, msg=out.content)
    assert_true(
      out.content.contains("=== \"missing\" ===\nerror reading directory:"),
    )
    assert_true(
      out.content.contains("=== \"file\" ===\nerror reading directory:"),
    )
    assert_true(out.content.contains("file \"entry\""))
    assert_false(out.content.contains("total_entries=0"))
    for args in [["--unknown"], [""]] {
      let invalid = run_in(ws, { "filename": "@builtin/ls.mbtx", "args": args })
      assert_true(invalid.is_error, msg=invalid.content)
      assert_true(invalid.content.contains("error: ls "))
    }
    let help = run_in(ws, { "filename": "@builtin/ls.mbtx", "args": ["--help"] })
    assert_false(help.is_error, msg=help.content)
    assert_true(help.content.contains("--all"))
    assert_true(help.content.contains("40000"))
    @fs.mkdir("\{ws}/--dash")
    let literal = run_in(ws, {
      "filename": "@builtin/ls.mbtx",
      "args": ["--", "--dash"],
    })
    assert_false(literal.is_error, msg=literal.content)
    assert_true(literal.content.contains("=== \"--dash\" ==="))
  })
}

///|
#cfg(not(platform="windows"))
async test "ls workflow quotes names and identifies broken and directory symlinks" {
  @vfs.with_tmpdir(ws => {
    @vfs.FileSystem({
      "dir/space name": "",
      "dir/line\nquote\"😀": "",
      "dir/sub/child": "",
    }).write_to(ws)
    @fs.symlink(target="missing", "\{ws}/dir/broken")
    @fs.symlink(target="sub", "\{ws}/dir/link")
    let out = dispatch(@mbtx.definition(workspace_root=ws, read_only=true), {
      "filename": "@builtin/ls.mbtx",
      "args": ["dir", "dir/link"],
    })
    assert_false(out.is_error, msg=out.content)
    assert_true(out.content.contains("file \"space name\""))
    assert_true(out.content.contains("file \"line\\nquote\\\"😀\""))
    assert_true(out.content.contains("symlink \"broken\""))
    assert_true(out.content.contains("symlink \"link\""))
    assert_true(out.content.contains("=== \"dir/link\" ===\nfile \"child\""))
  })
}

///|
async test "ls workflow bounds Unicode listings and skips directories within the transport cap" {
  @vfs.with_tmpdir(ws => {
    @fs.mkdir("\{ws}/large")
    for index in 0..<300 {
      @fs.write_file(
        "\{ws}/large/\{index}_\{"界".repeat(60)}",
        "",
        create_mode=CreateOrTruncate,
      )
    }
    @async.with_task_group() <| group => {
      let scope = @agent_runtime.AgentTaskScope(group)
      let runtime = @bgjobs.BgJobRuntime(scope, spill_dir=ws)
      let out = dispatch(
        @mbtx.definition(workspace_root=ws, bg_runtime=runtime, job_dir=ws),
        { "filename": "@builtin/ls.mbtx", "args": ["large", "large"] },
      )
      assert_false(out.is_error, msg=out.content)
      assert_true(out.content.contains("total_entries=300 truncated=true"))
      assert_true(out.content.contains("skipped_directories=1"))
      assert_true(@utf8.encode(out.content).length() <= 40_000)
      assert_false(out.content.contains("STOPPED"))
      assert_false(out.content.contains("�"))
      for line in out.content.split("\n") {
        if line.has_prefix("file ") {
          // Every emitted name remains a complete JSON string.
          assert_true(@json.parse(line[5:]) is String(_))
        }
      }
    }
  })
}
