///|
async fn github_pull_request_merge_base(
  gh : @pathx.Absolute,
  dir : @pathx.Absolute,
  host : String,
  owner : String,
  repo : String,
  base : String,
  head : String,
) -> String {
  if @gitx.probe(dir, ["merge-base", base, head]) is Some(local_base) &&
    @git.valid_commit_identity(local_base) {
    return local_base
  }
  // A newly pushed revision might not have been fetched locally yet. Resolve
  // its comparison boundary from GitHub without changing the checkout.
  let remote = github_command(gh, dir, [
      "api",
      "--hostname",
      host,
      "repos/\{owner}/\{repo}/compare/\{base}...\{head}",
      "--jq",
      ".merge_base_commit.sha",
    ])
    .trim()
    .to_owned()
  guard @git.valid_commit_identity(remote) else {
    raise InvalidResponse("GitHub returned an invalid merge base.")
  }
  remote
}
