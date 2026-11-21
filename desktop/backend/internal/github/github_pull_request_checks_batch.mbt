///|
pub(all) enum PullRequestCheckSnapshot {
  ChecksOpen(head~ : String, checks~ : PullRequestChecks)
  ChecksClosed
  ChecksUnavailable(String)
}

///|
const PullRequestChecksBatchSize : Int32 = 20

///|
const PullRequestChecksFragment : String =
  #|fragment PRChecks on PullRequest {
  #|  state headRefOid
  #|  commits(last: 1) {
  #|    nodes { commit {
  #|      oid
  #|      statusCheckRollup {
  #|        contexts(first: 100) {
  #|          pageInfo { hasNextPage }
  #|          nodes {
  #|            __typename
  #|            ... on CheckRun { id name status conclusion startedAt completedAt }
  #|            ... on StatusContext { id context state createdAt }
  #|          }
  #|        }
  #|      }
  #|    } }
  #|  }
  #|}

///|
/// Callers pass canonical PR URLs. Provider errors belong to the affected
/// PRs so one unavailable repository does not interrupt unrelated watches.
pub async fn pull_request_checks_batch(
  urls : Array[String],
) -> Map[String, PullRequestCheckSnapshot] {
  let results : Map[String, PullRequestCheckSnapshot] = Map([])
  let batches : Map[String, Array[(String, GithubReviewIdentity)]] = Map([])
  for url in urls {
    let identity = github_review_identity(url) catch {
      error => {
        results[url] = ChecksUnavailable("\{error}")
        continue
      }
    }
    batches.get_or_init(identity.host, () => []).push((url, identity))
  }
  guard resolve_gh() is Some(gh) else {
    for url in urls {
      results[url] = ChecksUnavailable(
        "Install GitHub CLI (gh) and sign in to monitor pull request checks.",
      )
    }
    return results
  }
  let queries : @async.Semaphore = Semaphore(4)
  @async.with_task_group(group => {
    for host, targets in batches {
      for start = 0
          start < targets.length()
          start = start + PullRequestChecksBatchSize {
        let chunk = targets[start:(start + PullRequestChecksBatchSize).min(
            targets.length(),
          )]
        group.spawn_bg(() => {
          queries.acquire()
          defer queries.release()
          read_pull_request_checks_batch(gh, host, chunk, results) catch {
            error =>
              for (url, _) in chunk {
                results[url] = ChecksUnavailable("\{error}")
              }
          }
        })
      }
    }
  })
  results
}

///|
async fn read_pull_request_checks_batch(
  gh : @pathx.Absolute,
  host : String,
  targets : ArrayView[(String, GithubReviewIdentity)],
  results : Map[String, PullRequestCheckSnapshot],
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
      "pr\{index}:repository(owner:$owner\{index},name:$repo\{index}){pullRequest(number:$number\{index}){...PRChecks}}",
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
    "query=query(\{variables.join(",")}){\{aliases.join(" ")}}\n\{PullRequestChecksFragment}",
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
    raise Unavailable("PR check lookup timed out.")
  }
  let response = @json.parse(text)
  guard response is { "data": Object(data), .. } else {
    raise InvalidResponse("GitHub omitted the PR checks response.")
  }
  let errors : Map[String, String] = Map([])
  if response is { "errors": Array(entries), .. } {
    for entry in entries {
      guard entry
        is { "path": [String(key), ..], "message": String(message), .. } else {
        raise InvalidResponse("GitHub returned an unscoped PR checks error.")
      }
      errors[key] = message
    }
  }
  for index, target in targets {
    let (url, identity) = target
    let key = "pr\{index}"
    results[url] = match (errors.get(key), data.get(key)) {
      (Some(error), _) => ChecksUnavailable(error)
      (None, Some({ "pullRequest": pr, .. })) =>
        decode_pull_request_check_snapshot(pr, identity) catch {
          error => ChecksUnavailable("\{error}")
        }
      _ => ChecksUnavailable("GitHub omitted the pull request.")
    }
  }
}

///|
async fn decode_pull_request_check_snapshot(
  pr : Json,
  identity : GithubReviewIdentity,
) -> PullRequestCheckSnapshot {
  if pr is { "state": String("CLOSED" | "MERGED"), .. } {
    return ChecksClosed
  }
  guard pr
    is {
      "state": String("OPEN"),
      "headRefOid": String(head),
      "commits": {
        "nodes": [
          {
            "commit": { "oid": String(oid), "statusCheckRollup": rollup, .. },
            ..
          },
        ],
        ..
      },
      ..
    } &&
    valid_check_head(head) &&
    oid == head else {
    raise InvalidResponse("GitHub returned an invalid PR checks snapshot.")
  }
  match rollup {
    Null => ChecksOpen(head~, checks=ChecksWaiting(retrying=false))
    { "contexts": { "pageInfo": { "hasNextPage": True, .. }, .. }, .. } =>
      pull_request_checks_paginated(identity)
    {
      "contexts": {
        "pageInfo": { "hasNextPage": False, .. },
        "nodes": Array(rows),
        ..
      },
      ..
    } => ChecksOpen(head~, checks=classify_pull_request_checks(rows))
    _ => raise InvalidResponse("GitHub returned an invalid check rollup.")
  }
}
