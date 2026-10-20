///|
/// What GitHub says about the pull request at `payload.url`, for a client
/// that has only its address — an item an agent attached to a conversation,
/// say. It needs no checkout: `gh` is pointed at the repository the address
/// names. An address that is not a pull request's has nothing to say.
///
/// The address is model output and the lookup runs without the user asking,
/// so it carries no credential meant for another host; see
/// `github_pull_request_summary_environment`.
async fn github_pull_request_summary_op(
  payload : @protocol.GithubPullRequestSummaryPayload,
) -> @protocol.GithubPullRequestSummaryReply {
  guard github_pull_request_summary_identity(payload.url) is Some(identity) else {
    return { pull_request: None, }
  }
  guard resolve_gh() is Some(gh) else {
    raise HostError("Install GitHub CLI (gh) and sign in to load PR status.")
  }
  let env = github_pull_request_summary_environment(
    identity.host,
    git_environment(),
  )
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
        PullRequestSummaryFields,
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
/// What `parse_pull_request` requires, without the check rollup: the card shows
/// no checks, and a token that may read a pull request but not its check runs
/// makes `gh pr view` fail the whole request rather than leave the field out.
const PullRequestSummaryFields : String = "number,title,state,url,baseRefName,isDraft,additions,deletions,changedFiles"

///|
/// `gh` sends `GH_ENTERPRISE_TOKEN` (or `GITHUB_ENTERPRISE_TOKEN`) to
/// whichever GitHub Enterprise Server host a command targets, so a lookup of
/// any other host than the `GH_HOST` that token was set for goes without it.
/// Credentials `gh` stored itself are kept per host and never leave theirs,
/// and `GH_TOKEN` goes only to github.com and its `ghe.com` tenants. Names
/// match case-insensitively because Windows preserves arbitrary key casing.
fn github_pull_request_summary_environment(
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

///|
/// The pull request a page under its address belongs to: a link copied from
/// GitHub may carry a query, a fragment, or a tab such as `/files`.
fn github_pull_request_summary_identity(url : String) -> GithubReviewIdentity? {
  let path = url.split("#").collect()[0].split("?").collect()[0]
  let parts = path.split("/").map(part => part.to_owned()).collect()
  guard parts is ["https:", "", host, owner, repo, "pull", number, ..] else {
    return None
  }
  let canonical = "https://\{host}/\{owner}/\{repo}/pull/\{number}"
  Some(github_review_identity(canonical) catch { _ => return None })
}
