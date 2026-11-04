///|
/// Whitebox coverage for the isolated-home preparation the connection path
/// runs before every spawn: the directory is created, and preparing the same
/// home again succeeds.
async test "preparing the isolated codex home creates the directory" {
  let root : @pathx.Path = @fs.tmpdir(prefix="openseek-codex-home-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  let home = home_dir(root)
  prepare_home_directory(home)
  assert_true(@fs.kind(home.to_string()) is Directory)
  // Preparing an existing home must succeed too: that is the steady state
  // of every launch after the first.
  prepare_home_directory(home)
  assert_true(@fs.kind(home.to_string()) is Directory)
}
