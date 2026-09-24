///|
test "codex home is a codex subdirectory of the runtime dir" {
  let home = @codex.home_dir(Path("/tmp/openseek-state"))
  assert_eq(
    home.to_string(),
    if @platform.win32 || @platform.win64 {
      "\\tmp\\openseek-state\\codex"
    } else {
      "/tmp/openseek-state/codex"
    },
  )
}

///|
async test "prepared codex home creates the directory" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-codex-home-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  let home = @codex.prepared_home(root)
  guard home is Some(home) else { fail("codex home was not prepared") }
  assert_eq(home, @codex.home_dir(root))
  assert_true(@fs.kind(home.to_string()) is Directory)
  // Preparing an existing home must succeed too: that is the steady state
  // of every launch after the first.
  guard @codex.prepared_home(root) is Some(_) else {
    fail("codex home was not prepared again")
  }
}
