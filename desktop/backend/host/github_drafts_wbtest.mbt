///|
async test "native comment drafts survive independent reads and remain scoped to their PR" {
  let dir = @fs.tmpdir(prefix="openseek-github-drafts-")
  defer @fs.rmdir(dir, recursive=true)
  let url = "https://github.example/owner/repo/pull/42"
  let other = "https://github.example/owner/repo/pull/43"
  let draft : @protocol.GithubDraft = {
    target: Line(path="src/main.mbt", side="RIGHT", line=8, head="revision"),
    body: "Keep this draft after restarting the application.",
  }
  assert_true(read_github_drafts(Some(dir), { url, }).drafts.is_empty())
  write_github_drafts(Some(dir), { url, drafts: [draft], }) |> ignore
  assert_true(read_github_drafts(Some(dir), { url, }).drafts == [draft])
  let updated = {
    ..draft,
    body: "The latest edit must replace the first save.",
  }
  write_github_drafts(Some(dir), { url, drafts: [updated], }) |> ignore
  assert_true(read_github_drafts(Some(dir), { url, }).drafts == [updated])
  assert_true(read_github_drafts(Some(dir), { url: other, }).drafts.is_empty())
  write_github_drafts(Some(dir), { url: other, drafts: [draft], }) |> ignore
  write_github_drafts(Some(dir), { url, drafts: [], }) |> ignore
  assert_true(read_github_drafts(Some(dir), { url, }).drafts.is_empty())
  assert_true(read_github_drafts(Some(dir), { url: other, }).drafts == [draft])
}

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
