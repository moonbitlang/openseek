///|
async test "component authoring helpers prepare clean sources and replace related inputs in a batch" {
  @vfs.with_tmpdir(root => {
    let workspace = root + "/workspace"
    let scratch = root + "/scratch"
    @fs.mkdir(workspace)
    @fs.mkdir(scratch)
    let staging = scratch + "/staging"
    @fs.mkdir(staging)
    @fs.write_file(staging + "/model.mbt", "model replacement")
    @fs.write_file(staging + "/main.mbt", "view replacement")
    @fs.write_file(staging + "/values.json", "[1,2]")
    let tool = @mbtx.definition(
      workspace_root=workspace,
      scratch_dir=scratch,
      foreground_timeout_ms=120000,
    )
    let init = @fs.realpath("share/artifact/init.mbtx")
    let write = @fs.realpath("share/artifact/write.mbtx")
    let starter = @fs.realpath("share/artifact/rabbita")
    let prepared = dispatch(tool, {
      "filename": init,
      "args": [scratch, starter, "linear"],
      "ptc": false,
    })
    assert_false(prepared.is_error, msg=prepared.content)
    assert_false(@fs.exists(scratch + "/artifact"))
    let project = scratch + "/component-work/linear"
    assert_eq(@fs.readdir(project, include_hidden=true).length(), 7)
    let previous = @fs.read_file(project + "/model.mbt").text()
    let duplicate = dispatch(tool, {
      "filename": init,
      "args": [scratch, starter, "linear"],
      "ptc": false,
    })
    assert_true(duplicate.is_error)
    assert_eq(@fs.read_file(project + "/model.mbt").text(), previous)
    let changed = dispatch(tool, {
      "filename": write,
      "args": [
        scratch,
        project,
        "model.mbt",
        staging + "/model.mbt",
        "main.mbt",
        staging + "/main.mbt",
        "data/values.json",
        staging + "/values.json",
      ],
      "ptc": false,
    })
    assert_false(changed.is_error, msg=changed.content)
    assert_false(@fs.exists(scratch + "/artifact"))
    assert_eq(@fs.read_file(project + "/model.mbt").text(), "model replacement")
    assert_eq(@fs.read_file(project + "/main.mbt").text(), "view replacement")
    assert_eq(@fs.read_file(project + "/data/values.json").text(), "[1,2]")
    let invalid = dispatch(tool, {
      "filename": write,
      "args": [
        scratch,
        project,
        "main.mbt",
        staging + "/model.mbt",
        "../escape.mbt",
        staging + "/main.mbt",
      ],
      "ptc": false,
    })
    assert_true(invalid.is_error)
    assert_eq(@fs.read_file(project + "/main.mbt").text(), "view replacement")
    for destination in [workspace, scratch + "/artifact/answer.html.source"] {
      if !@fs.exists(destination) {
        @fs.mkdir(destination, recursive=true)
      }
      let refused = dispatch(tool, {
        "filename": write,
        "args": [scratch, destination, "main.mbt", staging + "/main.mbt"],
        "ptc": false,
      })
      assert_true(refused.is_error)
      assert_false(@fs.exists(destination + "/main.mbt"))
    }
  })
}

///|
#cfg(not(platform="windows"))
async test "component authoring refuses linked parents and dangling target links" {
  @vfs.with_tmpdir(root => {
    let workspace = root + "/workspace"
    let scratch = root + "/scratch"
    let project = scratch + "/component"
    @fs.mkdir(workspace)
    @fs.mkdir(project, recursive=true)
    @fs.write_file(scratch + "/input.mbt", "must not write")
    @fs.symlink(target=workspace, project + "/linked")
    @fs.symlink(target=workspace + "/foreign.mbt", project + "/dangling.mbt")
    let tool = @mbtx.definition(
      workspace_root=workspace,
      scratch_dir=scratch,
      foreground_timeout_ms=120000,
    )
    for file in ["linked/main.mbt", "dangling.mbt"] {
      let refused = dispatch(tool, {
        "filename": @fs.realpath("share/artifact/write.mbtx"),
        "args": [scratch, project, file, scratch + "/input.mbt"],
        "ptc": false,
      })
      assert_true(refused.is_error)
    }
    assert_false(@fs.exists(workspace + "/main.mbt"))
    assert_false(@fs.exists(workspace + "/foreign.mbt"))
  })
}
