///|
test "a bin dir is prepended to the path, and stands alone when there is none" {
  assert_eq(@env.prepend_to_path_env("/toolchain/bin", None), "/toolchain/bin")
  assert_eq(
    @env.prepend_to_path_env("/toolchain/bin", Some("")),
    "/toolchain/bin",
  )
  assert_eq(
    @env.prepend_to_path_env("/toolchain/bin", Some("/usr/bin")),
    "/toolchain/bin\{@env.path_sep}/usr/bin",
  )
}

///|
/// Windows environment blocks commonly spell the key `Path`; the child gets
/// exactly one path variable, under the spelling that was already there.
test "prepending updates the existing spelling" {
  let env = { "Path": "/usr/bin" }
  assert_eq(
    @env.prepend_path_entry(env, "/toolchain/bin"),
    "/toolchain/bin\{@env.path_sep}/usr/bin",
  )
  assert_eq(env.get("Path"), Some("/toolchain/bin\{@env.path_sep}/usr/bin"))
  assert_eq(env.get("PATH"), None)
  assert_eq(env.length(), 1)
}

///|
/// The branch that matters for `inherit_env=false` children: a block carrying
/// both spellings must come out with exactly one, so which one the child reads
/// is not a coin toss. Which spelling survives follows the block's own
/// iteration order, so assert the invariant rather than a particular winner.
test "a duplicate path key is dropped so the child sees exactly one" {
  let env = { "Path": "/usr/bin", "PATH": "/opt/bin" }
  let joined = @env.prepend_path_entry(env, "/toolchain/bin")
  assert_eq(env.length(), 1)
  assert_true(
    joined == "/toolchain/bin\{@env.path_sep}/usr/bin" ||
    joined == "/toolchain/bin\{@env.path_sep}/opt/bin",
  )
  for key, value in env {
    assert_true(key == "Path" || key == "PATH")
    assert_eq(value, joined)
  }
}

///|
test "an empty block gains an uppercase PATH" {
  let env : Map[String, String] = Map([])
  assert_eq(@env.prepend_path_entry(env, "/toolchain/bin"), "/toolchain/bin")
  assert_eq(env.get("PATH"), Some("/toolchain/bin"))
}
