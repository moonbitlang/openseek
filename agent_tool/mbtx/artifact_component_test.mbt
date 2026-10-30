///|
async test "mbtx builds a Rabbita answer and can revise it from retained source alone" {
  @vfs.with_tmpdir(root => {
    let workspace = root + "/project"
    let scratch = root + "/session/scratch"
    let project = scratch + "/answer-app"
    let output = scratch + "/artifact"
    @fs.mkdir(workspace)
    let tool = @mbtx.definition(
      workspace_root=workspace,
      scratch_dir=scratch,
      foreground_timeout_ms=120000,
    )
    let filenames = [
      "moon.mod", "moon.pkg", "main.mbt", "model.mbt", "model_wbtest.mbt", "bridge.mbt",
      "index.html",
    ]
    let sources = [
      for filename in filenames => {
        @fs.read_file("share/artifact/rabbita/" + filename).text()
      }
    ]
    let created = dispatch(tool, {
      "source": (
        #|---
        #|import { "moonbitlang/core/async", "moonbitlang/core/async/fs", "moonbitlang/core/env" }
        #|---
        #|async fn main {
        #|  let args = @env.args()
        #|  let project = args[1]
        #|  @fs.mkdir(project, recursive=true)
        #|  for index, name in ["moon.mod", "moon.pkg", "main.mbt", "model.mbt", "model_wbtest.mbt", "bridge.mbt", "index.html"] {
        #|    @fs.write_text(project + "/" + name, args[index + 2], create_mode=CreateNew)
        #|  }
        #|  @fs.mkdir(project + "/_build", recursive=true)
        #|  @fs.write_text(project + "/_build/stale.js", "stale executable")
        #|  @fs.mkdir(project + "/assets")
        #|  @fs.write_binary(project + "/assets/data.bin", b"\x00\xff")
        #|  @fs.write_text(project + "/.answer-settings.json", "{}")
        #|}
      ),
      "args": [project, ..sources.map(source => Json(source))],
      "ptc": false,
    })
    assert_false(created.is_error, msg=created.content)
    let recipe = @fs.realpath("share/artifact/build.mbtx")
    let result = dispatch(tool, {
      "filename": recipe,
      "args": [project, output, "speedup-v1.html"],
      "ptc": false,
    })
    assert_false(result.is_error, msg=result.content)
    assert_true(result.content.contains("artifact://speedup-v1.html"))
    let html = @fs.read_file(output + "/speedup-v1.html").text()
    assert_true(html.contains("<div id=\"app\"></div>"))
    assert_true(html.contains("How much faster"))
    assert_true(html.contains(".composition"))
    assert_false(html.contains("<!-- openseek:script -->"))
    let retained = output + "/speedup-v1.html.source"
    for index, filename in filenames {
      assert_eq(@fs.read_file(retained + "/" + filename).text(), sources[index])
    }
    assert_false(@fs.exists(retained + "/_build"))
    assert_false(@fs.exists(retained + "/.mooncakes"))
    assert_eq(
      @fs.read_file(retained + "/assets/data.bin").binary(),
      b"\x00\xff",
    )
    assert_eq(@fs.read_file(retained + "/.answer-settings.json").text(), "{}")
    // The scratch working project is gone, as it would be in a session fork.
    @fs.rmdir(project, recursive=true)
    let rebuilt = dispatch(tool, {
      "filename": recipe,
      "args": [retained, output, "speedup-v2.html"],
      "ptc": false,
    })
    assert_false(rebuilt.is_error, msg=rebuilt.content)
    assert_true(rebuilt.content.contains("artifact://speedup-v2.html"))
    assert_true(@fs.exists(output + "/speedup-v2.html.source/model.mbt"))
    assert_eq(@fs.read_file(output + "/speedup-v1.html").text(), html)
    assert_false(@fs.exists(retained + "/_build"))
    assert_false(@fs.exists(retained + "/.mooncakes"))
  })
}
