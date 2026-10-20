///|
/// What GitHub says about the pull request at `payload.url`, for a client
/// that has only its address — an item an agent attached to a conversation,
/// say. It needs no checkout: `gh` is pointed at the repository the address
/// names. An address that is not a pull request's has nothing to say.
///
/// The address is model output and the lookup runs without the user asking,
/// so it carries no credential meant for another host; see
/// `github_pr_detail_environment`.
async fn github_pr_detail_op(
  payload : @protocol.GithubPrDetailPayload,
) -> @protocol.GithubPrDetailReply {
  let identity = github_review_identity(payload.url) catch {
    _ => return { pull_request: None, }
  }
  guard resolve_gh() is Some(gh) else {
    raise HostError("Install GitHub CLI (gh) and sign in to load PR status.")
  }
  let env = github_pr_detail_environment(identity.host, git_environment())
  let result = @async.with_timeout_opt(GithubRequestTimeoutMs, () => {
    let output = github_command(
      gh,
      @pathx.Path(".").resolve(),
      [
        "pr",
        "view",
        identity.number.to_string(),
        "--repo",
        "https://\{identity.host}/\{identity.owner}/\{identity.repo}",
        "--json",
        PullRequestFields,
      ],
      env~,
    )
    @json.parse(output) catch {
      _ => raise HostError("GitHub CLI returned invalid JSON.")
    }
  })
  guard result is Some(raw) else {
    raise HostError("PR status lookup timed out.")
  }
  guard parse_pull_request(raw) is Some(pull_request) else {
    raise HostError("GitHub returned invalid PR status.")
  }
  { pull_request: Some(pull_request), }
}

///|
/// `gh` sends `GH_ENTERPRISE_TOKEN` (or `GITHUB_ENTERPRISE_TOKEN`) to
/// whichever GitHub Enterprise Server host a command targets, so a lookup of
/// any other host than the `GH_HOST` that token was set for goes without it.
/// Credentials `gh` stored itself are kept per host and never leave theirs,
/// and `GH_TOKEN` goes only to github.com and its `ghe.com` tenants. Names
/// match case-insensitively because Windows preserves arbitrary key casing.
fn github_pr_detail_environment(
  host : String,
  env : Map[String, String],
) -> Map[String, String] {
  let mut intended = false
  let tokens : Array[String] = []
  for name, value in env {
    match name.to_upper() {
      "GH_HOST" => intended = value.to_lower() == host.to_lower()
      "GH_ENTERPRISE_TOKEN" | "GITHUB_ENTERPRISE_TOKEN" => tokens.push(name)
      _ => ()
    }
  }
  if !intended {
    for name in tokens {
      env.remove(name)
    }
  }
  env
}
