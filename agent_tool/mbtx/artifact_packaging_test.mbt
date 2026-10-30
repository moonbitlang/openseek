///|
async test "generic file packaging retains editable sources without a UI library" {
  @vfs.with_tmpdir(root => {
    let workspace = root + "/workspace"
    let scratch = root + "/scratch"
    let project = scratch + "/app"
    let output = scratch + "/artifact"
    @fs.mkdir(workspace)
    @fs.mkdir(project, recursive=true)
    @fs.write_file(project + "/moon.mod", "name = \"test/file_artifact\"\n")
    @fs.write_file(
      project + "/moon.pkg",
      "pkgtype(kind: \"executable\")\noptions(link: { \"js\": { \"format\": \"iife\" } })\n",
    )
    let main = "fn main { println(\"The application has loaded\") }\n"
    @fs.write_file(project + "/main.mbt", main)
    @fs.write_file(
      project + "/index.html",
      "<!doctype html><div id=\"app\">A generated file</div><!-- openseek:script -->",
    )
    @fs.mkdir(project + "/_build")
    @fs.write_file(project + "/_build/stale.js", "stale executable")
    @fs.mkdir(project + "/assets")
    @fs.write_file(project + "/assets/data.bin", b"\x00\xff")
    @fs.write_file(project + "/.settings.json", "{}")
    let tool = @mbtx.definition(
      workspace_root=workspace,
      scratch_dir=scratch,
      foreground_timeout_ms=120000,
    )
    let recipe = @fs.realpath("share/artifact/build.mbtx")
    let arguments : Json = {
      "filename": recipe,
      "args": [project, output, "answer-v1.html"],
      "ptc": false,
    }
    let result = dispatch(tool, arguments)
    assert_false(result.is_error, msg=result.content)
    assert_true(result.content.contains("artifact://answer-v1.html"))
    let html = @fs.read_file(output + "/answer-v1.html").text()
    assert_true(html.contains("The application has loaded"))
    assert_true(html.contains("<script>"))
    assert_false(html.contains("<!-- openseek:script -->"))
    let retained = output + "/answer-v1.html.source"
    assert_eq(@fs.read_file(retained + "/main.mbt").text(), main)
    assert_eq(
      @fs.read_file(retained + "/assets/data.bin").binary(),
      b"\x00\xff",
    )
    assert_eq(@fs.read_file(retained + "/.settings.json").text(), "{}")
    assert_false(@fs.exists(retained + "/_build"))
    assert_false(@fs.exists(retained + "/.mooncakes"))
    let duplicate = dispatch(tool, arguments)
    assert_true(duplicate.is_error)
    assert_true(duplicate.content.contains("already exists"))
    assert_eq(@fs.read_file(output + "/answer-v1.html").text(), html)
    @fs.rmdir(project, recursive=true)
    let rebuilt = dispatch(tool, {
      "filename": recipe,
      "args": [retained, output, "answer-v2.html"],
      "ptc": false,
    })
    assert_false(rebuilt.is_error, msg=rebuilt.content)
    assert_true(@fs.exists(output + "/answer-v2.html.source/main.mbt"))
    assert_false(@fs.exists(retained + "/_build"))
    assert_false(@fs.exists(retained + "/.mooncakes"))
  })
}

///|
#cfg(not(platform="windows"))
async test "packaging refuses a symlink as its explicit output directory" {
  @vfs.with_tmpdir(root => {
    let workspace = root + "/workspace"
    let scratch = root + "/scratch"
    let real_output = scratch + "/real-output"
    let linked_output = scratch + "/artifact"
    @fs.mkdir(workspace)
    @fs.mkdir(real_output, recursive=true)
    @fs.symlink(target=real_output, linked_output)
    let result = dispatch(
      @mbtx.definition(workspace_root=workspace, scratch_dir=scratch),
      {
        "filename": @fs.realpath("share/artifact/build.mbtx"),
        "args": [workspace, linked_output, "answer.html"],
        "ptc": false,
      },
    )
    assert_true(result.is_error)
    assert_true(
      result.content.contains("output directory must be a regular directory"),
      msg=result.content,
    )
    assert_eq(@fs.readdir(real_output).length(), 0)
  })
}

///|
#cfg(not(platform="windows"))
async test "component source links are rejected before publishing a revision" {
  @vfs.with_tmpdir(root => {
    let workspace = root + "/workspace"
    let scratch = root + "/scratch"
    let project = scratch + "/app"
    @fs.mkdir(workspace)
    @fs.mkdir(project, recursive=true)
    @fs.write_file(project + "/moon.mod", "name = \"test/answer\"\n")
    @fs.write_file(project + "/moon.pkg", "pkgtype(kind: \"executable\")\n")
    @fs.write_file(project + "/main.mbt", "fn main { println(1) }\n")
    @fs.write_file(root + "/external.bin", b"data")
    @fs.symlink(target=root + "/external.bin", project + "/data.bin")
    let tool = @mbtx.definition(
      workspace_root=workspace,
      scratch_dir=scratch,
      foreground_timeout_ms=120000,
    )
    let result = dispatch(tool, {
      "filename": @fs.realpath("share/artifact/build.mbtx"),
      "args": [project, scratch + "/artifact", "linked.html"],
      "ptc": false,
    })
    assert_true(result.is_error)
    assert_true(
      result.content.contains(
        "component sources must be regular files or directories",
      ),
    )
    assert_false(@fs.exists(scratch + "/artifact/linked.html"))
    assert_false(@fs.exists(scratch + "/artifact/linked.html.source"))
  })
}
