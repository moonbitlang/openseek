///|
/// Optional enrichment of a saved URL. Saving the association never reaches
/// this path and never waits for GitHub or requires a local checkout.
async fn git_pr_detail(
  payload : @protocol.GitPrDetailPayload,
) -> @protocol.GitPullRequest? {
  let identity = github_review_identity(payload.url) catch { _ => return None }
  guard resolve_gh() is Some(gh) else {
    raise HostError("Install GitHub CLI (gh) and sign in to load PR status.")
  }
  let result = @async.with_timeout_opt(GithubRequestTimeoutMs, () => {
    github_panel_json(gh, @pathx.Path(".").resolve(), [
      "pr",
      "view",
      identity.number.to_string(),
      "--repo",
      "https://\{identity.host}/\{identity.owner}/\{identity.repo}",
      "--json",
      PullRequestFields,
    ])
  })
  guard result is Some(raw) else {
    raise HostError("PR status lookup timed out.")
  }
  guard parse_pull_request(raw) is Some(pull_request) else {
    raise HostError("GitHub returned invalid PR status.")
  }
  Some(pull_request)
}
