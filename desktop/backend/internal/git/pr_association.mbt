// The pull request a local branch was checked out from. The checkout records
// it in the branch's local Git config so Review keeps the PR's merge base
// across restarts and branch renames.

///|
pub struct PullRequestAssociation {
  url : String
  base : String
}

///|
pub fn PullRequestAssociation::PullRequestAssociation(
  url~ : String,
  base~ : String,
) -> PullRequestAssociation {
  { url, base, }
}

///|
/// Record `association` on `branch` once its merge base is in HEAD's history.
pub async fn save_pr_association(
  dir : @pathx.Absolute,
  branch~ : String,
  association : PullRequestAssociation,
) -> Unit {
  let _ = @gitx.output(dir, [
    "merge-base",
    "--is-ancestor",
    association.base,
    "HEAD",
  ])
  let metadata : Json = { "url": association.url, "base": association.base }
  let _ = @gitx.output(dir, [
    "config",
    "--local",
    "branch.\{branch}.openseek-pr",
    metadata.stringify(),
  ])
}

///|
pub async fn pr_association(dir : @pathx.Absolute) -> PullRequestAssociation? {
  guard current_branch(dir) is Some(branch) else { return None }
  let (code, stdout) = @gitx.output_with_status(dir, [
    "config",
    "--local",
    "--get",
    "branch.\{branch}.openseek-pr",
  ])
  if code == 1 {
    return None
  }
  let raw = @json.parse(stdout)
  guard raw is { "url": String(url), "base": String(base), .. } &&
    url.has_prefix("https://") &&
    valid_commit_identity(base) else {
    raise Failed("The current branch has invalid pull request metadata.")
  }
  let (code, _) = @gitx.output_with_status(dir, [
    "merge-base", "--is-ancestor", base, "HEAD",
  ])
  if code == 1 {
    return None
  }
  guard current_branch(dir) == Some(branch) else {
    raise Stale(
      "The branch changed while reading its pull request. Refresh GitHub to retry.",
    )
  }
  Some({ url, base, })
}

///|
pub async fn current_branch(dir : @pathx.Absolute) -> String? {
  let (code, stdout) = @gitx.output_with_status(dir, [
    "symbolic-ref", "--quiet", "--short", "HEAD",
  ])
  if code == 1 {
    return None
  }
  let branch = single_line(stdout)
  guard !branch.is_empty() else {
    raise Failed("Git returned an empty branch name.")
  }
  Some(branch)
}
