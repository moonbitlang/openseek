///|
/// What GitHub says about the pull request at `payload.url`, for a client
/// that has only its address — an item an agent attached to a conversation,
/// say. It needs no checkout: `gh` is pointed at the repository the address
/// names. An address that is not a pull request's has nothing to say.
///
/// The address is model output and the lookup runs without the user asking,
/// so it carries no credential meant for another host; see
/// `github_pull_request_summary_environment`.
pub async fn pull_request_summary(
  payload : @protocol.GithubPullRequestSummaryPayload,
) -> @protocol.GithubPullRequestSummaryReply {
  guard github_pull_request_summary_identity(payload.url) is Some(identity) else {
    return { pull_request: None, }
  }
  let raw = read_pull_request_fields(identity, PullRequestSummaryFields)
  guard parse_pull_request(raw) is Some(pull_request) else {
    raise InvalidResponse("GitHub returned invalid PR status.")
  }
  { pull_request: Some(pull_request), }
}

///|
const PullRequestSummariesBatchSize : Int32 = 20

///|
const PullRequestSummaryFragment : String =
  #|fragment PRSummary on PullRequest {
  #|  number
  #|  title
  #|  state
  #|  isDraft
  #|  url
  #|  baseRefName
  #|  additions
  #|  deletions
  #|  changedFiles
  #|}

///|
/// Batch variant of `pull_request_summary` for sidebar status badges. Groups
/// requested URLs by GitHub host, deduplicates canonical PR identities (e.g.
/// `/pull/42` and `/pull/42/files`), and queries up to 20 PRs per GraphQL call.
/// Partial errors for one repository or pull request omit only that entry so
/// healthy pull requests still resolve.
pub async fn pull_request_summaries(
  payload : @protocol.GithubPullRequestSummariesPayload,
) -> @protocol.GithubPullRequestSummariesReply {
  let results : Map[String, @protocol.GitPullRequest] = Map([])
  guard !payload.urls.is_empty() else { return { pull_requests: results, } }
  let by_host : Map[String, Array[(Array[String], GithubReviewIdentity)]] = Map([],
  )
  let by_canonical : Map[String, Array[String]] = Map([])
  for url in payload.urls {
    guard github_pull_request_summary_identity(url) is Some(identity) else {
      continue
    }
    let canonical = "https://\{identity.host.to_lower()}/\{identity.owner.to_lower()}/\{identity.repo.to_lower()}/pull/\{identity.number}"
    match by_canonical.get(canonical) {
      Some(urls) => if !urls.contains(url) { urls.push(url) }
      None => {
        let urls = [url]
        by_canonical[canonical] = urls
        by_host.get_or_init(identity.host, () => []).push((urls, identity))
      }
    }
  }
  guard !by_host.is_empty() else { return { pull_requests: results, } }
  guard resolve_gh() is Some(gh) else {
    raise Unavailable("Install GitHub CLI (gh) and sign in to load PR status.")
  }
  let queries : @async.Semaphore = Semaphore(4)
  @async.with_task_group(group => {
    for host, targets in by_host {
      for start = 0
          start < targets.length()
          start = start + PullRequestSummariesBatchSize {
        let chunk = targets[start:(start + PullRequestSummariesBatchSize).min(
            targets.length(),
          )]
        group.spawn_bg(() => {
          queries.acquire()
          defer queries.release()
          read_pull_request_summaries_batch(gh, host, chunk, results) catch {
            _ => ()
          }
        })
      }
    }
  })
  { pull_requests: results, }
}

///|
async fn read_pull_request_summaries_batch(
  gh : @pathx.Absolute,
  host : String,
  targets : ArrayView[(Array[String], GithubReviewIdentity)],
  results : Map[String, @protocol.GitPullRequest],
) -> Unit {
  let args = ["api", "graphql", "--hostname", host]
  let variables : Array[String] = []
  let aliases : Array[String] = []
  for index, target in targets {
    let (_, identity) = target
    variables.push(
      "$owner\{index}:String!,$repo\{index}:String!,$number\{index}:Int!",
    )
    aliases.push(
      "pr\{index}:repository(owner:$owner\{index},name:$repo\{index}){pullRequest(number:$number\{index}){...PRSummary}}",
    )
    args.append([
      "-f",
      "owner\{index}=\{identity.owner}",
      "-f",
      "repo\{index}=\{identity.repo}",
      "-F",
      "number\{index}=\{identity.number}",
    ])
  }
  args.append([
    "-f",
    "query=query(\{variables.join(",")}){\{aliases.join(" ")}}\n\{PullRequestSummaryFragment}",
  ])
  let output = @async.with_timeout_opt(GithubRequestTimeoutMs, () => {
    github_command(
      gh,
      @pathx.Path(".").resolve(),
      args,
      env=github_pull_request_summary_environment(host, @gitx.environment()),
      allow_partial_graphql=true,
    )
  })
  guard output is Some(text) else {
    raise Unavailable("PR status lookup timed out.")
  }
  let response = @json.parse(text)
  decode_pull_request_summaries_batch(response, targets, results)
}

///|
fn decode_pull_request_summaries_batch(
  response : Json,
  targets : ArrayView[(Array[String], GithubReviewIdentity)],
  results : Map[String, @protocol.GitPullRequest],
) -> Unit raise GithubError {
  guard response is { "data": Object(data), .. } else {
    raise InvalidResponse("GitHub omitted the PR summary response.")
  }
  let errored : Set[String] = Set([])
  if response is { "errors": Array(entries), .. } {
    for entry in entries {
      if entry is { "path": [String(key), ..], .. } {
        errored.insert(key)
      }
    }
  }
  for index, target in targets {
    let (urls, _) = target
    let key = "pr\{index}"
    guard !errored.contains(key) else { continue }
    guard data.get(key) is Some({ "pullRequest": pr, .. }) &&
      parse_pull_request(pr) is Some(summary) else {
      continue
    }
    for url in urls {
      results[url] = summary
    }
  }
}

///|
async fn read_pull_request_fields(
  identity : GithubReviewIdentity,
  fields : String,
) -> Json {
  guard resolve_gh() is Some(gh) else {
    raise Unavailable("Install GitHub CLI (gh) and sign in to load PR status.")
  }
  let env = github_pull_request_summary_environment(
    identity.host,
    @gitx.environment(),
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
        fields,
      ],
      env~,
    )
    @json.parse(output) catch {
      _ => raise InvalidResponse("GitHub CLI returned invalid JSON.")
    }
  })
  guard result is Some(raw) else {
    raise Unavailable("PR status lookup timed out.")
  }
  raw
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
