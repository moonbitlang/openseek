///|
test "windows package args accept no mode arguments" {
  ignore(package_command().parse(argv=[]))
}

///|
test "windows package args reject removed installer flag" {
  try package_command().parse(argv=["--installer"]) catch {
    err =>
      assert_true(
        err.to_string().contains("unexpected argument '--installer' found"),
      )
  } noraise {
    _ => fail("expected removed --installer flag to fail")
  }
}

///|
test "windows package args reject removed bare mode" {
  try package_command().parse(argv=["installer"]) catch {
    err =>
      assert_true(
        err
        .to_string()
        .contains("unexpected value 'installer' found; no more were expected"),
      )
  } noraise {
    _ => fail("expected removed installer mode to fail")
  }
}
