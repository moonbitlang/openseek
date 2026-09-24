///|
async test "native draft storage reports corruption and I/O failures instead of an empty draft" {
  let dir = @fs.tmpdir(prefix="openseek-github-drafts-")
  defer @fs.rmdir(dir, recursive=true)
  let url = "https://github.example/owner/repo/pull/42"
  let path = github_drafts_path(Some(dir), url)
  @fsx.ensure_dir(path.dirname())
  @fs.write_file(path.to_string(), "{broken")
  try read_github_drafts(Some(dir), { url, }) catch {
    _ => ()
  } noraise {
    _ => fail("corrupt drafts must not become an empty list")
  }
  @fsx.remove_if_exists(path)
  @fs.mkdir(path.to_string())
  try read_github_drafts(Some(dir), { url, }) catch {
    _ => ()
  } noraise {
    _ => fail("filesystem errors must reach the composer")
  }
  try write_github_drafts(None, { url, drafts: [], }) catch {
    _ => ()
  } noraise {
    _ => fail("unavailable storage must not acknowledge a save")
  }
}
