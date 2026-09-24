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
  assert_true(@host.read_github_drafts(Some(dir), { url, }).drafts.is_empty())
  @host.write_github_drafts(Some(dir), { url, drafts: [draft], }) |> ignore
  assert_true(@host.read_github_drafts(Some(dir), { url, }).drafts == [draft])
  let updated = {
    ..draft,
    body: "The latest edit must replace the first save.",
  }
  @host.write_github_drafts(Some(dir), { url, drafts: [updated], }) |> ignore
  assert_true(@host.read_github_drafts(Some(dir), { url, }).drafts == [updated])
  assert_true(
    @host.read_github_drafts(Some(dir), { url: other, }).drafts.is_empty(),
  )
  @host.write_github_drafts(Some(dir), { url: other, drafts: [draft], })
  |> ignore
  @host.write_github_drafts(Some(dir), { url, drafts: [], }) |> ignore
  assert_true(@host.read_github_drafts(Some(dir), { url, }).drafts.is_empty())
  assert_true(
    @host.read_github_drafts(Some(dir), { url: other, }).drafts == [draft],
  )
}
