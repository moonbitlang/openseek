///|
#cfg(target="native")
const ArtifactSuffix : String = ".exe"

///|
#cfg(target="wasm")
const ArtifactSuffix : String = ".wasm"

///|
test "current executable identifies the running test artifact" {
  let exe = @env.current_exe()
  assert_true(@path.Path(exe).is_absolute())
  let basename = @path.Path(exe).basename()
  assert_true(basename.has_suffix(ArtifactSuffix))
  assert_true(basename.contains("env.blackbox_test"))
  let dir = @env.current_exe_dir()
  assert_eq(dir, @path.Path(exe).dirname().to_string())
  // Integration probes can relocate the artifact, including Unicode paths,
  // and launch it from another working directory with exact expectations.
  if @sys.get_env_var("OPENSEEK_TEST_CURRENT_EXE") is Some(expected) {
    assert_eq(exe, expected)
  }
  if @sys.get_env_var("OPENSEEK_TEST_CURRENT_EXE_DIR") is Some(expected) {
    assert_eq(dir, expected)
  }
}

///|
test "repeated executable lookups return the same paths" {
  let exe = @env.current_exe()
  let dir = @env.current_exe_dir()
  for _ in 0..<20 {
    assert_eq(@env.current_exe(), exe)
    assert_eq(@env.current_exe_dir(), dir)
  }
}
