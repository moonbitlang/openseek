///|
async test "call dirs get short names that are never shared" {
  @vfs.with_tmpdir(prefix="mbtx-call-dir-", owner => {
    // The owner need not exist yet: a job dir is created with its first call.
    let parent = "\{owner}/jobs"
    let first = fresh_call_dir(parent, "snippet-")
    let second = fresh_call_dir(parent, "snippet-")
    assert_not_eq(first, second)
    let names = @fs.readdir(parent)
    assert_eq(names.length(), 2)
    for name in names {
      // `snippet-` and eight hex digits: the whole cost of a call's identity
      // in every path the build writes below it.
      assert_eq(name.length(), 16, msg=name)
      assert_true(name.has_prefix("snippet-"), msg=name)
      assert_true(@fs.kind("\{parent}/\{name}") is Directory)
    }
  })
}
