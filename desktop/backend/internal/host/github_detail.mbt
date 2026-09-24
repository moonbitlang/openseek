///|
async fn github_pull_request_op(
  payload : @protocol.GithubPullRequestPayload,
) -> @protocol.GithubPullRequestDetail {
  guard payload.number > 0 && payload.repository_url.has_prefix("https://") else {
    raise HostError("Select a pull request from a GitHub repository.")
  }
  guard @pathx.Absolute::from_uri_path(payload.cwd) is Some(dir) else {
    raise HostError("Select a workspace with an absolute checkout path.")
  }
  guard resolve_gh() is Some(gh) else {
    raise HostError(
      "Install GitHub CLI (gh) and run gh auth login to load pull requests.",
    )
  }
  let reply = @async.with_timeout_opt(20000, () => {
    github_pull_request(payload, args => github_panel_json(gh, dir, args))
  })
  match reply {
    Some(reply) => reply
    None =>
      raise HostError(
        "GitHub request timed out. Check your connection and retry.",
      )
  }
}

///|
async fn github_pull_request(
  payload : @protocol.GithubPullRequestPayload,
  query : async (Array[String]) -> Json,
) -> @protocol.GithubPullRequestDetail {
  // gh supplies the existing metadata shape, but its JSON field selection
  // does not expose bodyHTML. Fetch every displayed body through GraphQL.
  let raw = query([
    "pr",
    "view",
    payload.number.to_string(),
    "--repo",
    payload.repository_url,
    "--json",
    "number,title,url,author,isDraft,state,baseRefName,headRefName,additions,deletions,changedFiles,statusCheckRollup,createdAt,reviewRequests,latestReviews,assignees,labels,milestone,mergeable",
  ])
  guard raw is { "url": String(url), .. } else {
    raise HostError("GitHub returned invalid pull request details.")
  }
  let identity = github_review_identity(url)
  let (body_html, comments) = github_pull_request_content(identity, query)
  github_pull_request_detail(raw, body_html, comments)
}

///|
async fn github_pull_request_content(
  identity : GithubReviewIdentity,
  query : async (Array[String]) -> Json,
) -> (String, Array[@protocol.GithubComment]) {
  let query_text = "query($owner:String!,$repo:String!,$number:Int!,$after:String){repository(owner:$owner,name:$repo){pullRequest(number:$number){bodyHTML comments(first:100,after:$after){nodes{author{login} bodyHTML url createdAt} pageInfo{hasNextPage endCursor}}}}}"
  let comments : Array[@protocol.GithubComment] = []
  let seen : Array[String] = []
  let mut body_html : String? = None
  let mut cursor : String? = None
  while true {
    let args = [
      "api",
      "graphql",
      "--hostname",
      identity.host,
      "-f",
      "query=\{query_text}",
      "-f",
      "owner=\{identity.owner}",
      "-f",
      "repo=\{identity.repo}",
      "-F",
      "number=\{identity.number}",
    ]
    if cursor is Some(after) {
      args.append(["-f", "after=\{after}"])
    }
    let data = github_graphql_data(query(args))
    guard data
      is {
        "repository": {
          "pullRequest": { "bodyHTML": String(html), "comments": page, .. },
          ..
        },
        ..
      } else {
      raise HostError("GitHub returned invalid pull request content.")
    }
    if body_html is None {
      body_html = Some(html)
    }
    let (nodes, next) = github_review_page(page)
    comments.append(nodes.map(github_detail_comment))
    match next {
      None => break
      Some(after) => {
        guard !seen.contains(after) else {
          raise HostError("GitHub repeated a comment page. Refresh to retry.")
        }
        seen.push(after)
        cursor = next
      }
    }
  }
  guard body_html is Some(body_html) else {
    raise HostError("GitHub omitted the pull request body.")
  }
  (body_html, comments)
}

///|
fn github_comment_author(raw : Json) -> String? raise {
  match raw {
    Null => None
    { "login": String(login), .. } => Some(login)
    _ => raise HostError("GitHub returned an invalid comment author.")
  }
}

///|
fn github_detail_comment(raw : Json) -> @protocol.GithubComment raise {
  guard raw
    is {
      "author": author,
      "bodyHTML": String(body_html),
      "url": String(url),
      "createdAt": String(created_at),
      ..
    } else {
    raise HostError("GitHub returned an invalid comment.")
  }
  { author: github_comment_author(author), body_html, url, created_at, }
}

///|
fn github_check_url(raw : Json) -> String? raise {
  match raw {
    // GitHub uses null or an empty URL for checks without a details page.
    // Normalize it at the provider boundary; our protocol uses absence.
    Null | String("") => None
    String(url) => Some(url)
    _ => raise HostError("GitHub returned an invalid check URL.")
  }
}

///|
fn github_detail_check(raw : Json) -> @protocol.GithubCheck raise {
  match raw {
    {
      "__typename": String("CheckRun"),
      "name": String(name),
      "status": String(status),
      "conclusion": conclusion,
      "detailsUrl": url,
      "workflowName": workflow,
      ..
    } => {
      let state = if status == "COMPLETED" {
        guard conclusion is String(state) && !state.is_empty() else {
          raise HostError(
            "GitHub returned a completed check without a conclusion.",
          )
        }
        state
      } else {
        status
      }
      {
        name,
        state,
        url: github_check_url(url),
        workflow: match workflow {
          Null | String("") => None
          String(name) => Some(name)
          _ => raise HostError("GitHub returned an invalid workflow name.")
        },
      }
    }
    {
      "__typename": String("StatusContext"),
      "context": String(name),
      "state": String(state),
      "targetUrl": url,
      ..
    } => { name, state, url: github_check_url(url), workflow: None, }
    _ => raise HostError("GitHub returned an invalid status check.")
  }
}

///|
fn github_pull_request_detail(
  raw : Json,
  body_html : String,
  comments : Array[@protocol.GithubComment],
) -> @protocol.GithubPullRequestDetail raise {
  let item = github_panel_item(raw, AllOpen, Map([]))
  guard raw
    is {
      "state": String(state),
      "mergeable": String(mergeable),
      "baseRefName": String(base),
      "headRefName": String(head),
      "additions": additions,
      "deletions": deletions,
      "changedFiles": changed_files,
      "statusCheckRollup": rollup,
      "createdAt": String(created_at),
      "reviewRequests": Array(requests),
      "latestReviews": Array(reviews),
      "assignees": Array(assignees),
      "labels": Array(labels),
      "milestone": milestone,
      ..
    } else {
    raise HostError("GitHub returned invalid pull request details.")
  }
  let raw_checks = match rollup {
    Null => []
    Array(checks) => checks
    _ => raise HostError("GitHub returned invalid status checks.")
  }
  {
    item,
    state,
    mergeable,
    body_html,
    base,
    head,
    additions: @json.from_json(additions),
    deletions: @json.from_json(deletions),
    changed_files: @json.from_json(changed_files),
    comments,
    checks: raw_checks.map(github_detail_check),
    created_at,
    reviewers: github_detail_reviewers(reviews, requests),
    assignees: assignees.map(raw => {
      guard raw is { "login": String(login), .. } else {
        raise HostError("GitHub returned an invalid assignee.")
      }
      login
    }),
    labels: labels.map(raw => {
      guard raw is { "name": String(name), .. } else {
        raise HostError("GitHub returned an invalid label.")
      }
      name
    }),
    milestone: match milestone {
      Null => None
      { "title": String(title), .. } => Some(title)
      _ => raise HostError("GitHub returned an invalid milestone.")
    },
  }
}

///|
fn github_detail_reviewers(
  reviews : Array[Json],
  requests : Array[Json],
) -> Array[@protocol.GithubReviewer] raise {
  let reviewers : Map[String, @protocol.GithubReviewer] = Map([])
  for review in reviews {
    guard review is { "author": author, "state": String(state), .. } else {
      raise HostError("GitHub returned an invalid review.")
    }
    if github_comment_author(author) is Some(name) {
      reviewers[name] = { name, state, }
    }
  }
  for request in requests {
    let name = match request {
      { "login": String(login), .. } => login
      { "name": String(name), .. } => name
      _ => raise HostError("GitHub returned an invalid review request.")
    }
    reviewers[name] = { name, state: "REQUESTED", }
  }
  reviewers.values().to_array()
}
