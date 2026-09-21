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
    let raw = github_panel_json(gh, dir, [
      "pr",
      "view",
      payload.number.to_string(),
      "--repo",
      payload.repository_url,
      "--json",
      "number,title,url,author,isDraft,state,body,baseRefName,headRefName,additions,deletions,changedFiles,statusCheckRollup,createdAt,reviewRequests,latestReviews,assignees,labels,milestone,mergeable",
    ])
    github_pull_request_detail(raw)
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
fn github_comment_author(raw : Json) -> String? raise {
  match raw {
    Null => None
    { "login": String(login), .. } => Some(login)
    _ => raise HostError("GitHub returned an invalid comment author.")
  }
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
) -> @protocol.GithubPullRequestDetail raise {
  let item = github_panel_item(raw, AllOpen, Map([]))
  guard raw
    is {
      "state": String(state),
      "mergeable": String(mergeable),
      "body": String(body),
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
    body,
    base,
    head,
    additions: @json.from_json(additions),
    deletions: @json.from_json(deletions),
    changed_files: @json.from_json(changed_files),
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
