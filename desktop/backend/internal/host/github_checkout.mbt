///|
async fn github_checkout_op(
  payload : @protocol.GithubCheckoutPayload,
) -> @protocol.GithubCheckoutReply {
  // Proton redacts raised handler errors. Carry actionable Git diagnostics in
  // a typed reply so local and remote clients receive the same explanation.
  checkout_pull_request(payload) catch {
    error => github_checkout_failure("\{error}")
  }
}

///|
async fn checkout_pull_request(
  payload : @protocol.GithubCheckoutPayload,
) -> @protocol.GithubCheckoutReply {
  guard payload.number > 0 && payload.repository_url.has_prefix("https://") else {
    raise HostError("Select a pull request from a GitHub repository.")
  }
  guard @pathx.Absolute::from_uri_path(payload.cwd) is Some(dir) else {
    raise HostError("Select a workspace with an absolute checkout path.")
  }
  guard resolve_gh() is Some(gh) else {
    raise HostError(
      "Install GitHub CLI (gh) and run gh auth login to check out pull requests.",
    )
  }
  let reply : @protocol.GithubCheckoutReply? = @async.with_timeout_opt(120000, () => {
    let branch = if payload.update {
      let current = github_checkout_status_op({ cwd: payload.cwd, })
      guard current.branch is Some(branch) &&
        current.pull_request_url ==
        Some("\{payload.repository_url}/pull/\{payload.number}") else {
        raise HostError(
          "The current pull request changed. Refresh GitHub before updating.",
        )
      }
      Some(branch)
    } else {
      None
    }
    if !github_prepare_checkout(dir.0, payload.number, payload.changes) {
      return CheckoutNeedsConfirmation
    }
    let association = github_checkout_association(gh, dir, payload)
    // gh owns fork remotes and branch tracking. Its ordinary checkout refuses
    // to overwrite conflicting edits or reset a diverged local branch.
    // Always pin the PR to the repository shown by the list, not gh's current
    // default repository, which can change while the panel is open.
    let args = [
      "pr",
      "checkout",
      payload.number.to_string(),
      "--repo",
      payload.repository_url,
    ]
    if branch is Some(branch) {
      guard github_checkout_branch(dir.0) == Some(branch) else {
        raise HostError(
          "The branch changed before updating. Refresh GitHub to retry.",
        )
      }
      // A locally renamed PR branch must be updated in place. Without this,
      // gh would switch to its default PR branch instead.
      args.append(["--branch", branch])
    }
    let _ = github_command(gh, dir, args)
    guard github_checkout_branch(dir.0) is Some(branch) else {
      raise HostError(
        "Checkout completed, but the current branch could not be read. Refresh the repository to check its state.",
      )
    }
    // The PR's merge base belongs to the fetched head history. Persist the
    // association on this branch, like VS Code does, so Review survives a
    // restart and does not inherit the task's previous comparison boundary.
    try {
      let _ = github_checkout_git(dir.0, [
        "merge-base",
        "--is-ancestor",
        association.base,
        "HEAD",
      ])
      let metadata : Json = { "url": association.url, "base": association.base }
      let _ = github_checkout_git(dir.0, [
        "config",
        "--local",
        "branch.\{branch}.openseek-pr",
        metadata.stringify(),
      ])
    } catch {
      error =>
        raise HostError(
          "Checked out PR #\{payload.number} on \{branch}, but could not prepare Review: \{error}",
        )
    }
    CheckoutSuccess(branch)
  })
  match reply {
    Some(reply) => reply
    None =>
      raise HostError(
        "Pull request checkout timed out. Check the repository state before retrying.",
      )
  }
}

///|
/// Only the explicit dialog choice can stash or discard. Ordinary checkout
/// lets Git keep non-conflicting edits and refuse overwrites; it never forces.
async fn github_prepare_checkout(
  dir : String,
  number : Int,
  changes : @protocol.GithubCheckoutChanges,
) -> Bool {
  let status = github_checkout_git(dir, [
    "status", "--porcelain", "--untracked-files=no",
  ])
  if status.is_empty() {
    return true
  }
  match changes {
    Ask => false
    Carry => true
    Stash => {
      let _ = github_checkout_git(dir, [
        "stash",
        "push",
        "--message",
        "Before checking out PR #\{number}",
      ])
      true
    }
    Discard => {
      let _ = github_checkout_git(dir, [
        "restore", "--source=HEAD", "--staged", "--worktree", "--", ":/",
      ])
      true
    }
  }
}

///|
async fn github_checkout_git(dir : String, args : Array[String]) -> String {
  let (code, stdout, stderr) = git_collect(dir, args)
  guard code == 0 else {
    let message = stderr.text().trim().to_owned()
    raise HostError(
      if message.is_empty() {
        "Git failed (exit \{code})."
      } else {
        message
      },
    )
  }
  stdout.text()
}

///|
fn github_checkout_failure(details : String) -> @protocol.GithubCheckoutReply {
  let message = if details.contains(
      "untracked working tree files would be overwritten",
    ) {
    "Untracked files would be overwritten. Move or commit them before switching branches."
  } else if details.contains("would be overwritten by checkout") ||
    details.contains("would be overwritten by merge") {
    "Your local changes would be overwritten. Commit or stash them before switching branches."
  } else if details.contains("already used by worktree") ||
    details.contains("already checked out at") {
    "This branch is already checked out in another worktree. Switch it there before trying again."
  } else {
    let diagnostic = details
      .split("\n")
      .filter(line => line.has_prefix("fatal:") || line.has_prefix("error:"))
      .next()
    match diagnostic {
      Some(line) => line.to_owned()
      None =>
        details
        .split("\n")
        .filter(line => !line.trim().is_empty())
        .next()
        .map(line => line.to_owned())
        .unwrap_or("Checkout failed.")
    }
  }
  CheckoutFailure(
    message,
    if message == details {
      None
    } else {
      Some(details)
    },
  )
}

///|
async fn github_checkout_status_op(
  payload : @protocol.GithubWorkspacePayload,
) -> @protocol.GithubCheckoutStatus {
  guard @pathx.Absolute::from_uri_path(payload.cwd) is Some(dir) else {
    raise HostError("Select a workspace with an absolute checkout path.")
  }
  let result = @async.with_timeout_opt(GithubRequestTimeoutMs, () => {
    github_checkout_status(dir, args => {
      guard resolve_gh() is Some(gh) else {
        raise HostError(
          "Install GitHub CLI to identify the current pull request.",
        )
      }
      github_panel_json(gh, dir, args)
    })
  })
  guard result is Some(status) else {
    raise HostError(
      "Could not read the current pull request. Refresh GitHub to retry.",
    )
  }
  status
}

///|
async fn github_checkout_status(
  dir : @pathx.Absolute,
  query : async (Array[String]) -> Json,
) -> @protocol.GithubCheckoutStatus {
  // pr status resolves the current local branch (including fork tracking) and
  // represents a branch with no PR by omitting currentBranch. CLI failures
  // remain errors rather than being mistaken for a successful empty lookup.
  let branch = github_checkout_branch(dir.0)
  guard branch is Some(_) else {
    return { branch, pull_request_url: None, has_open_pull_request: false, }
  }
  // Local metadata identifies the PR even after a branch rename. Its lifecycle
  // still belongs to GitHub: a saved association may have closed or merged.
  let pr = if github_local_checkout_association(dir.0) is Some(association) {
    let result = query(["pr", "view", association.url, "--json", "url,state"])
    guard result is Object(_) else {
      raise HostError("GitHub returned an invalid current pull request.")
    }
    Some(result)
  } else {
    let result = query(["pr", "status", "--json", "url,state"])
    guard result is Object(object) else {
      raise HostError("GitHub returned an invalid current pull request.")
    }
    object.get("currentBranch")
  }
  let (url, has_open_pull_request) = match pr {
    None | Some(Null) => (None, false)
    Some({ "url": String(url), "state": String(state), .. }) if url.has_prefix(
        "https://",
      ) &&
      (state == "OPEN" || state == "CLOSED" || state == "MERGED") =>
      (Some(url), state == "OPEN")
    _ => raise HostError("GitHub returned an invalid current pull request.")
  }
  guard github_checkout_branch(dir.0) == branch else {
    raise HostError(
      "The branch changed while reading its pull request. Refresh GitHub to retry.",
    )
  }
  { branch, pull_request_url: url, has_open_pull_request, }
}

///|
priv struct GithubCheckoutAssociation {
  url : String
  base : String
}

///|
async fn github_checkout_association(
  gh : @pathx.Absolute,
  dir : @pathx.Absolute,
  payload : @protocol.GithubCheckoutPayload,
) -> GithubCheckoutAssociation {
  let parts = [
    for part in payload.repository_url.split("/") => part.to_owned()
  ]
  guard parts is ["https:", "", host, owner, repo] else {
    raise HostError("Select a pull request from a GitHub repository.")
  }
  let raw = github_panel_json(gh, dir, [
    "api",
    "--hostname",
    host,
    "repos/\{owner}/\{repo}/pulls/\{payload.number}",
  ])
  guard raw
    is {
      "base": { "sha": String(base), .. },
      "head": { "sha": String(head), .. },
      "html_url": String(url),
      ..
    } &&
    valid_commit_identity(base) &&
    valid_commit_identity(head) else {
    raise HostError("GitHub returned an invalid pull request comparison.")
  }
  let merge_base = github_pull_request_merge_base(
    gh, dir, host, owner, repo, base, head,
  )
  { url, base: merge_base, }
}

///|
async fn github_local_checkout_association(
  dir : String,
) -> GithubCheckoutAssociation? {
  guard github_checkout_branch(dir) is Some(branch) else { return None }
  let (code, stdout, stderr) = git_collect(dir, [
    "config",
    "--local",
    "--get",
    "branch.\{branch}.openseek-pr",
  ])
  if code == 1 {
    return None
  }
  guard code == 0 else { raise HostError(stderr.text()) }
  let raw = @json.parse(stdout.text())
  guard raw is { "url": String(url), "base": String(base), .. } &&
    url.has_prefix("https://") &&
    valid_commit_identity(base) else {
    raise HostError("The current branch has invalid pull request metadata.")
  }
  let (code, _, stderr) = git_collect(dir, [
    "merge-base", "--is-ancestor", base, "HEAD",
  ])
  if code == 1 {
    return None
  }
  guard code == 0 else { raise HostError(stderr.text()) }
  guard github_checkout_branch(dir) == Some(branch) else {
    raise HostError(
      "The branch changed while reading its pull request. Refresh GitHub to retry.",
    )
  }
  Some({ url, base, })
}

///|
async fn github_checkout_branch(dir : String) -> String? {
  let (code, stdout, stderr) = git_collect(dir, [
    "symbolic-ref", "--quiet", "--short", "HEAD",
  ])
  if code == 1 {
    return None
  }
  guard code == 0 else { raise HostError(stderr.text()) }
  let branch = git_single_line(stdout.text())
  guard !branch.is_empty() else {
    raise HostError("Git returned an empty branch name.")
  }
  Some(branch)
}
