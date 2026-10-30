///|
async test "explicit artifact paths use existing scratch permissions without granting workspace or other session writes" {
  @vfs.with_tmpdir(root => {
    let workspace = root + "/project"
    let first_scratch = root + "/sessions/first/scratch"
    let second_scratch = root + "/sessions/second/scratch"
    let first = first_scratch + "/artifact"
    let second = second_scratch + "/artifact"
    @fs.mkdir(workspace)
    @fs.mkdir(second, recursive=true)
    let source =
      #|---
      #|import { "moonbitlang/core/async", "moonbitlang/core/async/fs", "moonbitlang/core/env" }
      #|---
      #|async fn main {
      #|  let dir = @env.args()[1]
      #|  let value = @env.args()[2]
      #|  @fs.mkdir(dir, recursive=true, allow_exist=true)
      #|  @fs.write_text(dir + "/chart.html", value, create_mode=CreateNew)
      #|  println("artifact://chart.html")
      #|}
    let one = dispatch(
      @mbtx.definition(workspace_root=workspace, scratch_dir=first_scratch),
      { "source": source, "args": [first, "first"], "ptc": false },
    )
    let two = dispatch(
      @mbtx.definition(workspace_root=workspace, scratch_dir=second_scratch),
      { "source": source, "args": [second, "second"], "ptc": false },
    )
    assert_false(one.is_error, msg=one.content)
    assert_false(two.is_error, msg=two.content)
    assert_eq(@fs.read_file(first + "/chart.html").text(), "first")
    assert_eq(@fs.read_file(second + "/chart.html").text(), "second")
    let escaped = dispatch(
      @mbtx.definition(workspace_root=workspace, scratch_dir=first_scratch),
      {
        "source": (
          #|---
          #|import { "moonbitlang/core/async", "moonbitlang/core/async/fs", "moonbitlang/core/env" }
          #|---
          #|async fn main {
          #|  for path in @env.args()[1:] {
          #|    try @fs.write_text(path, "overwrite") catch {
          #|      _ => ()
          #|    } noraise { _ => fail("unexpected write permission") }
          #|  }
          #|}
        ),
        "args": [
          second + "/chart.html",
          workspace + "/main.mbt",
          workspace + "/output.html",
        ],
        "ptc": false,
      },
    )
    assert_false(escaped.is_error, msg=escaped.content)
    assert_false(@fs.exists(workspace + "/main.mbt"))
    assert_false(@fs.exists(workspace + "/output.html"))
    assert_eq(@fs.read_file(second + "/chart.html").text(), "second")
    let resumed = dispatch(
      @mbtx.definition(workspace_root=workspace, scratch_dir=first_scratch),
      {
        "source": (
          #|---
          #|import { "moonbitlang/core/async", "moonbitlang/core/async/fs", "moonbitlang/core/env" }
          #|---
          #|async fn main { println(@fs.read_text(@env.args()[1] + "/chart.html")) }
        ),
        "args": [first],
        "ptc": false,
      },
    )
    assert_false(resumed.is_error, msg=resumed.content)
    assert_true(resumed.content.contains("first"))
  })
}
