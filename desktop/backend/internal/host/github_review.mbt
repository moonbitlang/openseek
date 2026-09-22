///|
priv struct GithubReviewIdentity {
  host : String
  owner : String
  repo : String
  number : Int
}

///|
fn github_review_identity(url : String) -> GithubReviewIdentity raise {
  let parts = url.split("/").map(part => part.to_owned()).collect()
  guard parts is ["https:", "", host, owner, repo, "pull", number] &&
    !host.is_empty() &&
    !owner.is_empty() &&
    !repo.is_empty() else {
    raise HostError("Select a GitHub pull request.")
  }
  let number = @string.parse_int(number)
  guard number > 0 else { raise HostError("Invalid pull request number.") }
  { host, owner, repo, number, }
}

///|
const GithubReviewCommentFields : String = "fullDatabaseId body url author{login avatarUrl} createdAt viewerCanDelete"

///|
const GithubReviewThreadFields : String = "id path side:diffSide line original_line:originalLine resolved:isResolved outdated:isOutdated can_reply:viewerCanReply can_resolve:viewerCanResolve can_unresolve:viewerCanUnresolve"

///|
fn github_review_comment(raw : Json) -> @protocol.GithubReviewComment raise {
  guard raw
    is {
      "fullDatabaseId": database_id,
      "body": String(body),
      "url": String(url),
      "author": author,
      "createdAt": String(created_at),
      "viewerCanDelete": can_delete,
      ..
    } else {
    raise HostError("GitHub returned an invalid review comment.")
  }
  // GitHub comment IDs exceed a 32-bit MoonBit Int. Keep the decimal identity
  // intact across JS, native and the REST path, including BigInt's string form.
  let id = match database_id {
    String(id) if github_review_valid_id(id) => id
    Number(n, ..) if n > 0.0 && n <= 9007199254740991.0 && n.floor() == n =>
      n.to_int64().to_string()
    _ => raise HostError("GitHub returned an invalid review comment ID.")
  }
  let (author, avatar_url) = match author {
    Null => (None, None)
    { "login": String(login), "avatarUrl": String(avatar), .. } =>
      (Some(login), Some(avatar))
    _ => raise HostError("GitHub returned an invalid review author.")
  }
  {
    id,
    body,
    url,
    author,
    avatar_url,
    created_at,
    can_delete: @json.from_json(can_delete),
  }
}

///|
/// A null cursor is the sole end marker; malformed or repeated pagination is
/// an error, never a successful truncated discussion.
fn github_review_page(raw : Json) -> (Array[Json], String?) raise {
  guard raw
    is {
      "nodes": Array(nodes),
      "pageInfo": { "hasNextPage": more, "endCursor": cursor, .. },
      ..
    } else {
    raise HostError("GitHub returned invalid review pagination.")
  }
  match more {
    False => (nodes, None)
    True =>
      match cursor {
        String(cursor) if !cursor.is_empty() => (nodes, Some(cursor))
        _ => raise HostError("GitHub omitted the next review cursor.")
      }
    _ => raise HostError("GitHub returned invalid review pagination.")
  }
}

///|
async fn github_review_graphql(
  gh : @pathx.Absolute,
  dir : @pathx.Absolute,
  identity : GithubReviewIdentity,
  query : String,
  fields : Array[String],
) -> Json {
  let args = [
    "api",
    "graphql",
    "--hostname",
    identity.host,
    "-f",
    "query=\{query}",
  ]
  args.append(fields)
  let raw = github_panel_json(gh, dir, args)
  if raw is { "errors": Array(errors), .. } && !errors.is_empty() {
    raise HostError("GitHub review request failed: \{Json(errors).stringify()}")
  }
  guard raw is { "data": data, .. } else {
    raise HostError("GitHub omitted the review response.")
  }
  data
}

///|
async fn github_review_threads_page(
  gh : @pathx.Absolute,
  dir : @pathx.Absolute,
  identity : GithubReviewIdentity,
  cursor : String?,
) -> Json {
  let query = "query($owner:String!,$repo:String!,$number:Int!,$after:String){repository(owner:$owner,name:$repo){pullRequest(number:$number){url head:headRefOid base:baseRefOid reviewThreads(first:50,after:$after){nodes{\{GithubReviewThreadFields} comments(first:100){nodes{\{GithubReviewCommentFields}} pageInfo{hasNextPage endCursor}}} pageInfo{hasNextPage endCursor}}}}}"
  let fields = [
    "-f",
    "owner=\{identity.owner}",
    "-f",
    "repo=\{identity.repo}",
    "-F",
    "number=\{identity.number}",
  ]
  if cursor is Some(cursor) {
    fields.append(["-f", "after=\{cursor}"])
  }
  let data = github_review_graphql(gh, dir, identity, query, fields)
  guard data is { "repository": { "pullRequest": pr, .. }, .. } else {
    raise HostError("The pull request is unavailable to your GitHub account.")
  }
  pr
}

///|
async fn github_review_thread(
  gh : @pathx.Absolute,
  dir : @pathx.Absolute,
  identity : GithubReviewIdentity,
  raw : Json,
) -> @protocol.GithubReviewThread {
  guard raw is Object(fields) &&
    fields.get("id") is Some(String(id)) &&
    fields.get("comments") is Some(page) else {
    raise HostError("GitHub returned an invalid review thread.")
  }
  let (nodes, first_cursor) = github_review_page(page)
  let comments = nodes.map(github_review_comment)
  let mut cursor = first_cursor
  let seen : Array[String] = []
  while cursor is Some(after) {
    guard !seen.contains(after) else {
      raise HostError("GitHub repeated a comment page. Refresh to retry.")
    }
    seen.push(after)
    let query = "query($id:ID!,$after:String!){node(id:$id){... on PullRequestReviewThread{comments(first:100,after:$after){nodes{\{GithubReviewCommentFields}} pageInfo{hasNextPage endCursor}}}}}"
    let data = github_review_graphql(gh, dir, identity, query, [
      "-f",
      "id=\{id}",
      "-f",
      "after=\{after}",
    ])
    guard data is { "node": { "comments": page, .. }, .. } else {
      raise HostError("The review thread changed. Refresh to retry.")
    }
    let (nodes, next) = github_review_page(page)
    comments.append(nodes.map(github_review_comment))
    cursor = next
  }
  let normalized = fields.copy()
  normalized["comments"] = comments.to_json()
  let thread : @protocol.GithubReviewThread = @json.from_json(Json(normalized))
  guard thread.side == "LEFT" || thread.side == "RIGHT" else {
    raise HostError("GitHub returned an unknown diff side.")
  }
  thread
}

///|
async fn github_review_file(
  dir : @pathx.Absolute,
  path : String,
  base : String,
  head : String,
) -> @protocol.GithubReviewFile? {
  // Both revisions are immutable. File navigation only needs local Git, not
  // another round-trip through every PR file and every review thread.
  let changes = github_checkout_git(dir.0, [
    "diff", "--name-status", "-z", "--no-ext-diff", "--find-renames", base, head,
    "--",
  ])
  for change in parse_git_diff_name_status_z(changes) {
    guard change.path == path else { continue }
    let old_path = change.original_path.unwrap_or(path)
    let original = if change.kind == "added" {
      None
    } else {
      Some(github_checkout_git(dir.0, ["show", "\{base}:\{old_path}"]))
    }
    let modified = if change.kind == "deleted" {
      None
    } else {
      Some(github_checkout_git(dir.0, ["show", "\{head}:\{path}"]))
    }
    for content in [original, modified] {
      if content is Some(text) && text.contains("\u{0}") {
        raise HostError("Inline comments are unavailable for binary files.")
      }
    }
    return Some({ path, original, modified, })
  }
  None
}

///|
async fn github_review_file_op(
  payload : @protocol.GithubReviewFilePayload,
) -> @protocol.GithubReviewFileReply {
  try {
    guard @pathx.Absolute::from_uri_path(payload.cwd) is Some(dir) &&
      valid_commit_identity(payload.base) &&
      valid_commit_identity(payload.head) else {
      raise HostError("Select a checkout and a valid PR revision.")
    }
    ReviewFileLoaded(
      github_review_file(dir, payload.path, payload.base, payload.head),
    )
  } catch {
    error =>
      ReviewFileFailed(
        "Could not load this file at the GitHub PR revision. \{error}",
      )
  }
}

///|
async fn github_review_load(
  payload : @protocol.GithubWorkspacePayload,
) -> @protocol.GithubReview? {
  guard @pathx.Absolute::from_uri_path(payload.cwd) is Some(dir) else {
    raise HostError("Select a checkout with an absolute path.")
  }
  let current = github_checkout_status_op({ cwd: payload.cwd, })
  guard current.has_open_pull_request && current.pull_request_url is Some(url) else {
    return None
  }
  let identity = github_review_identity(url)
  guard resolve_gh() is Some(gh) else {
    raise HostError(
      "Install GitHub CLI and run gh auth login to load comments.",
    )
  }
  let first = github_review_threads_page(gh, dir, identity, None)
  guard first
    is {
      "url": String(url),
      "head": String(head),
      "base": String(base),
      "reviewThreads": page,
      ..
    } &&
    valid_commit_identity(head) &&
    valid_commit_identity(base) else {
    raise HostError("GitHub returned an invalid pull request revision.")
  }
  let merge_base = github_pull_request_merge_base(
    gh,
    dir,
    identity.host,
    identity.owner,
    identity.repo,
    base,
    head,
  )
  let (nodes, first_cursor) = github_review_page(page)
  let threads : Array[@protocol.GithubReviewThread] = []
  for raw in nodes {
    threads.push(github_review_thread(gh, dir, identity, raw))
  }
  let mut cursor = first_cursor
  let seen : Array[String] = []
  while cursor is Some(after) {
    guard !seen.contains(after) else {
      raise HostError("GitHub repeated a thread page. Refresh to retry.")
    }
    seen.push(after)
    let pr = github_review_threads_page(gh, dir, identity, cursor)
    guard pr is { "head": String(next_head), "reviewThreads": page, .. } &&
      next_head == head else {
      raise HostError(
        "The pull request changed while loading comments. Refresh to retry.",
      )
    }
    let (nodes, next) = github_review_page(page)
    for raw in nodes {
      threads.push(github_review_thread(gh, dir, identity, raw))
    }
    cursor = next
  }
  let commentable = github_review_commentable_files(
    github_panel_json(gh, dir, [
      "api",
      "--hostname",
      identity.host,
      "--paginate",
      "--slurp",
      "repos/\{identity.owner}/\{identity.repo}/pulls/\{identity.number}/files?per_page=100",
    ]),
  )
  let latest = github_panel_json(gh, dir, [
    "api",
    "--hostname",
    identity.host,
    "repos/\{identity.owner}/\{identity.repo}/pulls/\{identity.number}",
  ])
  guard latest
    is {
      "state": String("open"),
      "head": { "sha": String(latest_head), .. },
      "base": { "sha": String(latest_base), .. },
      ..
    } &&
    latest_head == head &&
    latest_base == base else {
    raise HostError(
      "The pull request changed while loading comments. Refresh to retry.",
    )
  }
  guard github_checkout_branch(dir.0) == current.branch else {
    raise HostError(
      "The checkout changed while loading comments. Refresh to retry.",
    )
  }
  Some({ url, head, base: merge_base, threads, commentable, })
}

///|
async fn github_review_op(
  payload : @protocol.GithubWorkspacePayload,
) -> @protocol.GithubReviewReply {
  try {
    match @async.with_timeout_opt(45000, () => github_review_load(payload)) {
      Some(review) => ReviewLoaded(review)
      None =>
        ReviewLoadFailed(
          "Loading GitHub comments timed out. Check your connection and refresh.",
        )
    }
  } catch {
    error => ReviewLoadFailed("\{error}")
  }
}

///|
fn github_review_mutation_args(
  identity : GithubReviewIdentity,
  action : @protocol.GithubReviewAction,
) -> Array[String] raise {
  let root = "repos/\{identity.owner}/\{identity.repo}/pulls"
  let args = ["api", "--hostname", identity.host]
  match action {
    Post(path~, side~, line~, body~, head~) => {
      guard (side == "LEFT" || side == "RIGHT") &&
        line > 0 &&
        !path.is_empty() &&
        valid_commit_identity(head) &&
        !body.trim().is_empty() else {
        raise HostError("Choose a valid PR line and enter a comment.")
      }
      args.append([
        "--method",
        "POST",
        "\{root}/\{identity.number}/comments",
        "-f",
        "path=\{path}",
        "-f",
        "side=\{side}",
        "-F",
        "line=\{line}",
        "-f",
        "body=\{body}",
        "-f",
        "commit_id=\{head}",
      ])
    }
    Reply(comment~, body~) => {
      guard github_review_valid_id(comment) && !body.trim().is_empty() else {
        raise HostError("Enter a reply to an existing comment.")
      }
      args.append([
        "--method",
        "POST",
        "\{root}/\{identity.number}/comments/\{comment}/replies",
        "-f",
        "body=\{body}",
      ])
    }
    Delete(comment~) => {
      guard github_review_valid_id(comment) else {
        raise HostError("Invalid GitHub comment ID.")
      }
      args.append(["--method", "DELETE", "\{root}/comments/\{comment}"])
    }
    Resolve(thread~, resolved~) => {
      guard !thread.is_empty() else {
        raise HostError("Invalid GitHub thread ID.")
      }
      let mutation = if resolved {
        "resolveReviewThread"
      } else {
        "unresolveReviewThread"
      }
      args.append([
        "graphql",
        "-f",
        "query=mutation($id:ID!){\{mutation}(input:{threadId:$id}){thread{id isResolved}}}",
        "-f",
        "id=\{thread}",
      ])
    }
  }
  args
}

///|
fn github_review_valid_id(id : String) -> Bool {
  !id.is_empty() &&
  id.iter().all(c => c is ('0'..='9')) &&
  id.iter().any(c => c != '0')
}

///|
async fn github_review_mutate_op(
  payload : @protocol.GithubReviewMutationPayload,
) -> @protocol.GithubReviewMutationReply {
  try {
    let result = @async.with_timeout_opt(30000, () => {
      let identity = github_review_identity(payload.url)
      guard @pathx.Absolute::from_uri_path(payload.cwd) is Some(dir) else {
        raise HostError("Select a checkout with an absolute path.")
      }
      guard resolve_gh() is Some(gh) else {
        raise HostError("Install GitHub CLI and run gh auth login.")
      }
      if payload.action is Post(head~, ..) {
        let latest = github_panel_json(gh, dir, [
          "api",
          "--hostname",
          identity.host,
          "repos/\{identity.owner}/\{identity.repo}/pulls/\{identity.number}",
        ])
        guard latest is { "head": { "sha": String(current), .. }, .. } &&
          current == head else {
          raise HostError(
            "The pull request changed. Refresh comments before sending; your draft is kept locally.",
          )
        }
      }
      let output = github_command(
        gh,
        dir,
        github_review_mutation_args(identity, payload.action),
      )
      if payload.action is Resolve(thread~, resolved~) {
        let response = @json.parse(output)
        if response is { "errors": Array(errors), .. } && !errors.is_empty() {
          raise HostError(
            "GitHub could not update the conversation: \{Json(errors).stringify()}",
          )
        }
        let field = if resolved {
          "resolveReviewThread"
        } else {
          "unresolveReviewThread"
        }
        guard response is { "data": Object(data), .. } &&
          data.get(field)
          is Some(
            { "thread": { "id": String(id), "isResolved": confirmed, .. }, .. }
          ) &&
          id == thread &&
          confirmed == resolved.to_json() else {
          raise HostError(
            "GitHub did not confirm the conversation update. Refresh before retrying.",
          )
        }
      }
    })
    match result {
      Some(_) => ReviewMutationSuccess
      None =>
        ReviewMutationFailure(
          "GitHub did not confirm the operation before timeout. Refresh comments to check whether it succeeded before retrying. Your draft is kept locally.",
        )
    }
  } catch {
    error => ReviewMutationFailure("\{error}")
  }
}
