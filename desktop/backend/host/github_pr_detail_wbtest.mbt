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

  let intended = github_pr_detail_environment(
    "GHE.Example.com",
    env(Some("ghe.example.com")),
  )
  assert_eq(intended.get("GH_ENTERPRISE_TOKEN"), Some("gh-token"))
  assert_eq(intended.get("GITHUB_ENTERPRISE_TOKEN"), Some("github-token"))
  for
    stripped in [
      github_pr_detail_environment(
        "attacker.example",
        env(Some("ghe.example.com")),
      ),
      github_pr_detail_environment("attacker.example", env(None)),
      github_pr_detail_environment("github.com", env(None)),
    ] {
    assert_true(stripped.get("GH_ENTERPRISE_TOKEN") is None)
    assert_true(stripped.get("GITHUB_ENTERPRISE_TOKEN") is None)
    assert_eq(stripped.get("GH_TOKEN"), Some("dotcom-token"))
    assert_eq(stripped.get("PATH"), Some("/usr/bin"))
  }
}
