///|
async test "staging writes only when the content differs" {
  @vfs.with_tmpdir(prefix="mbtx-stage-", dir => {
    let path = "\{dir}/snippet.mbtx"
    assert_true(stage_source(path, "fn main { }"))
    assert_false(stage_source(path, "fn main { }"))
    assert_true(stage_source(path, "fn main { println(1) }"))
    assert_eq(@fs.read_file(path).text(), "fn main { println(1) }")
  })
}
