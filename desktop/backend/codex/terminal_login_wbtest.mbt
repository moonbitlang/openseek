///|
#cfg(not(platform="windows"))
async test "terminal login resolves the service PATH without guessing another installation" {
  let root = @fs.tmpdir(prefix="codex-terminal-path-")
  defer @fs.rmdir(root, recursive=true)
  @fs.mkdir(root + "/first")
  @fs.mkdir(root + "/second")
  @fs.write_file(root + "/first/codex", "not executable", permission=0o600)
  @fs.write_file(root + "/second/codex", "#!/bin/sh\n", permission=0o700)
  assert_eq(
    login_executable("codex", Some(root + "/first:" + root + "/second")),
    @pathx.Path(root + "/second/codex").resolve().to_string(),
  )
  try login_executable("codex", Some(root + "/first")) catch {
    error => assert_true(error.to_string().contains("service PATH"))
  } noraise {
    _ => fail("must not search a different home installation")
  }
}
