///|
/// What GitHub says about the pull request at `payload.url`, for a client
/// that has only its address — an item an agent attached to a conversation,
/// say. It needs no checkout: `gh` is pointed at the repository the address
/// names. An address that is not a pull request's has nothing to say.
async fn github_pr_detail_op(
  payload : @protocol.GithubPrDetailPayload,
) -> @protocol.GithubPrDetailReply {
  let identity = github_review_identity(payload.url) catch {
    _ => return { pull_request: None, }
  }
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
  { pull_request: Some(pull_request), }
}
