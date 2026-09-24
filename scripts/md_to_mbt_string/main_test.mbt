///|
#cfg(platform="windows")
test "@path.Path::basename handles Unix and Windows separators" {
  assert_eq(
    @path.Path("./prompt/base_prompt.mbt.md").basename(),
    "base_prompt.mbt.md",
  )
  assert_eq(
    @path.Path(".\\prompt\\default_prompt.mbt.md").basename(),
    "default_prompt.mbt.md",
  )
  assert_eq(@path.Path("C:\\a\\b\\c").basename(), "c")
  assert_eq(@path.Path("C:\\a\\b\\").basename(), "b")
  assert_eq(@path.Path("C:\\a\\b/c").basename(), "c")
  assert_eq(@path.Path("").basename(), "")
  assert_eq(@path.Path("/").basename(), "")
  assert_eq(@path.Path("\\").basename(), "")
  assert_eq(@path.Path("a").basename(), "a")
  assert_eq(@path.Path("a/").basename(), "a")
  assert_eq(@path.Path("C:\\a").basename(), "a")
}
