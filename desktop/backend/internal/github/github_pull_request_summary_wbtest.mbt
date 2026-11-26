///|
test "an enterprise token goes only to the host it was set for" {
  fn env(gh_host : String?) -> Map[String, String] {
    let env : Map[String, String] = {
      "GH_ENTERPRISE_TOKEN": "gh-token",
      "GITHUB_ENTERPRISE_TOKEN": "github-token",
      "GH_TOKEN": "dotcom-token",
      "PATH": "/usr/bin",
    }
    if gh_host is Some(host) {
      env["GH_HOST"] = host
    }
    env
  }

  let intended = github_pull_request_summary_environment(
    "GHE.Example.com",
    env(Some("ghe.example.com")),
  )
  assert_eq(intended.get("GH_ENTERPRISE_TOKEN"), Some("gh-token"))
  assert_eq(intended.get("GITHUB_ENTERPRISE_TOKEN"), Some("github-token"))
  for
    stripped in [
      github_pull_request_summary_environment(
        "attacker.example",
        env(Some("ghe.example.com")),
      ),
      github_pull_request_summary_environment("attacker.example", env(None)),
      github_pull_request_summary_environment("github.com", env(None)),
    ] {
    assert_true(stripped.get("GH_ENTERPRISE_TOKEN") is None)
    assert_true(stripped.get("GITHUB_ENTERPRISE_TOKEN") is None)
    assert_eq(stripped.get("GH_TOKEN"), Some("dotcom-token"))
    assert_eq(stripped.get("PATH"), Some("/usr/bin"))
  }
  // Windows keeps whatever casing the variables were set with.
  let windows = github_pull_request_summary_environment("attacker.example", {
    "gh_enterprise_token": "gh-token",
    "Github_Enterprise_Token": "github-token",
    "Gh_Host": "ghe.example.com",
  })
  assert_true(windows.get("gh_enterprise_token") is None)
  assert_true(windows.get("Github_Enterprise_Token") is None)
  let windows = github_pull_request_summary_environment("ghe.example.com", {
    "gh_enterprise_token": "gh-token",
    "Gh_Host": "GHE.example.com",
  })
  assert_eq(windows.get("gh_enterprise_token"), Some("gh-token"))
}

///|
test "a pull request page's address names its pull request" {
  for
    url in [
      "https://github.com/o/r/pull/42", "https://github.com/o/r/pull/42?diff=split",
      "https://github.com/o/r/pull/42#issuecomment-123", "https://github.com/o/r/pull/42/files",
    ] {
    guard github_pull_request_summary_identity(url) is Some(identity) else {
      fail("\{url} names no pull request")
    }
    assert_eq(
      (identity.host, identity.owner, identity.repo, identity.number),
      ("github.com", "o", "r", 42),
    )
  }
  for
    url in [
      "https://github.com/o/r/tree/topic", "https://github.com/o/r/pull/x", "https://github.com/o/r/pull/0",
      "https://github.com/o/r?x=/pull/1",
    ] {
    assert_true(github_pull_request_summary_identity(url) is None)
  }
}

///|
test "batch PR summary decoder handles partial errors and URL aliases" {
  let pr1 = "https://github.com/o/r/pull/1"
  let pr1_files = "https://github.com/o/r/pull/1/files"
  let pr2 = "https://github.com/o/r/pull/2"
  let pr3 = "https://github.com/o/r/pull/3"
  guard github_pull_request_summary_identity(pr1) is Some(id1) &&
    github_pull_request_summary_identity(pr2) is Some(id2) &&
    github_pull_request_summary_identity(pr3) is Some(id3) else {
    fail("expected valid identities")
  }
  let targets : Array[(Array[String], GithubReviewIdentity)] = [
    ([pr1, pr1_files], id1),
    ([pr2], id2),
    ([pr3], id3),
  ]
  let response : Json = {
    "data": {
      "pr0": {
        "pullRequest": {
          "number": 1,
          "title": "First PR",
          "state": "OPEN",
          "isDraft": true,
          "url": pr1,
          "baseRefName": "main",
          "additions": 10,
          "deletions": 2,
          "changedFiles": 3,
        },
      },
      "pr1": null,
      "pr2": {
        "pullRequest": {
          "number": 3,
          "title": "Merged PR",
          "state": "MERGED",
          "isDraft": false,
          "url": pr3,
          "baseRefName": "main",
          "additions": 5,
          "deletions": 1,
          "changedFiles": 1,
        },
      },
    },
    "errors": [
      { "path": ["pr1"], "message": "Could not resolve to a PullRequest" },
    ],
  }
  let results : Map[String, @protocol.GitPullRequest] = Map([])
  decode_pull_request_summaries_batch(response, targets, results)
  assert_eq(
    results.get(pr1).map(pr => (pr.number, pr.state, pr.draft)),
    Some((1, "open", true)),
  )
  assert_eq(results.get(pr1_files).map(pr => pr.number), Some(1))
  assert_true(results.get(pr2) is None)
  assert_eq(
    results.get(pr3).map(pr => (pr.number, pr.state, pr.draft)),
    Some((3, "merged", false)),
  )
}
