///|
async test "ordinary mbtx packages a real MoonBit mathplotlib application into a referenced interactive file" {
  @vfs.with_tmpdir(root => {
    let workspace = root + "/project"
    let scratch = root + "/session/scratch"
    let project = scratch + "/chart-app"
    let output = scratch + "/artifact"
    @fs.mkdir(workspace)
    let tool = @mbtx.definition(
      workspace_root=workspace,
      scratch_dir=scratch,
      foreground_timeout_ms=120000,
    )
    let sources = [
      for filename in ["moon.mod", "moon.pkg", "main.mbt", "index.html"] => {
        @fs.read_file("share/artifact/example/" + filename).text()
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
        #|  for index, filename in ["moon.mod", "moon.pkg", "main.mbt", "index.html"] {
        #|    @fs.write_text(project + "/" + filename, args[index + 2], create_mode=CreateNew)
        #|  }
        #|}
      ),
      "args": [project, ..sources.map(source => Json(source))],
      "ptc": false,
    })
    assert_false(created.is_error, msg=created.content)
    assert_true(@fs.exists(project + "/main.mbt"))
    let arguments : Json = {
      "filename": @fs.realpath("share/artifact/build.mbtx"),
      "args": [project, output, "revenue.html"],
      "ptc": false,
    }
    let result = dispatch(tool, arguments)
    assert_false(result.is_error, msg=result.content)
    assert_true(result.content.contains("artifact://revenue.html"))
    let file = @fs.open(output + "/revenue.html", mode=ReadOnly)
    defer file.close()
    assert_true(
      file.size() <= 8L * 1024 * 1024,
      msg="generated example exceeds the 8 MiB inline preview limit",
    )
    let html = file.read_all().text()
    assert_true(
      html.contains("Weekly revenue") &&
      html.contains("<script>") &&
      html.contains(".moonplot"),
    )
    let duplicate = dispatch(tool, arguments)
    assert_true(duplicate.is_error)
    assert_true(duplicate.content.contains("already exists"))
    assert_eq(@fs.read_file(output + "/revenue.html").text(), html)
  })
}
