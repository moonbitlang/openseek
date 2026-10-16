///|
async test "ensure_codex_config creates the file once and keeps edits" {
  let home = @fs.tmpdir(prefix="openseek-codex-config-")
  let nested = @pathx.Path("\{home}/isolated/codex")
  let created = @host.ensure_codex_config(Some(nested))
  assert_eq(created, "\{home}/isolated/codex/config.toml")
  let seeded = @fs.read_file(created).text()
  assert_true(seeded.has_prefix("# Codex configuration"))
  // A later call returns the same path without touching user edits.
  @fs.write_file(created, "model = \"gpt-5.4\"\n", create_mode=CreateOrTruncate)
  let again = @host.ensure_codex_config(Some(nested))
  assert_eq(again, created)
  assert_eq(@fs.read_file(created).text(), "model = \"gpt-5.4\"\n")
}

///|
async test "configuration preparation preserves filesystem failures and handles competing creators" {
  let directory = @fs.tmpdir(prefix="codex-config-races-")
  defer @fs.rmdir(directory, recursive=true)
  let blocker = directory + "/blocker"
  @fs.write_file(blocker, "keep", create_mode=CreateNew)
  try @host.ensure_codex_config(Some(Path(blocker))) catch {
    @os_error.OSError(_) as error => assert_true(error.is_ENOTDIR())
    error => raise error
  } noraise {
    _ => fail("non-directory must be an error")
  }
  assert_eq(@fs.read_file(blocker).text(), "keep")
  let home = @pathx.Path(directory + "/home")
  @async.with_task_group(group => {
    let first = group.spawn(() => @host.ensure_codex_config(Some(home)))
    let second = group.spawn(() => @host.ensure_codex_config(Some(home)))
    assert_eq(first.wait(), second.wait())
  })
  assert_true(
    @fs.read_file(directory + "/home/config.toml")
    .text()
    .has_prefix("# Codex configuration"),
  )
}
