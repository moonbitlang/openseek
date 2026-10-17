///|
/// Exact gitlink paths from `git ls-tree -z` or `git ls-files --stage -z`.
/// Reading Git metadata keeps paths with spaces unambiguous and still sees
/// submodules whose working directories are absent.
fn gitlink_paths(metadata : String) -> Array[String] {
  let paths : Array[String] = []
  for record in metadata.split("\u{0}") {
    guard record.has_prefix("160000 ") &&
      record.split_once("\t") is Some((_, path)) else {
      continue
    }
    let path = path.to_owned()
    // A conflicted index can carry several stages for one gitlink.
    if !paths.contains(path) {
      paths.push(path)
    }
  }
  paths
}

///|
/// Populate the new checkout with the same top-level submodules that are
/// initialized in the attached main checkout. Optional, uninitialized
/// submodules stay opt-in. `--checkout` deliberately overrides any configured
/// `!command` update procedure; recursive children use the ordinary checkout
/// strategy too. The timeout is the caller's validated workspace-settings
/// snapshot; expiry raises into the existing create-or-repair rollback path.
async fn provision_initialized_submodules(
  origin : @pathx.Absolute,
  checkout : @pathx.Absolute,
  timeout_seconds : Int32,
) -> Unit {
  // Worktrees branch from HEAD, not the main checkout's staged index.
  let tree = @gitx.output(origin, ["ls-tree", "-r", "-z", "HEAD"])
  let initialized : Array[String] = []
  for path in gitlink_paths(tree) {
    guard @gitx.probe(origin, ["submodule", "status", "--", path])
      is Some(status) &&
      !status.is_empty() &&
      !status.has_prefix("-") else {
      continue
    }
    initialized.push(path)
  }
  guard !initialized.is_empty() else { return }
  let args : Array[String] = []
  // `git submodule` does not forward repository-local protocol policy to the
  // clone helper. Preserve an explicit user opt-in for local submodule URLs;
  // never relax the default on the app's own authority.
  if @gitx.probe(origin, ["config", "--get", "protocol.file.allow"])
    is Some("always") {
    args.append(["-c", "protocol.file.allow=always"])
  }
  args.append([
    "submodule", "update", "--init", "--checkout", "--recursive", "--",
  ])
  args.append(initialized)
  guard @async.with_timeout_opt(timeout_seconds * 1_000, () => {
      @gitx.run(checkout, args)
    })
    is Some(_) else {
    raise WorktreeError(
      "Submodules did not finish initializing within \{timeout_seconds} seconds. Increase the checkout timeout in Workspace Settings or leave submodules uninitialized.",
    )
  }
}
