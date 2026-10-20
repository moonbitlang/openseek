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
