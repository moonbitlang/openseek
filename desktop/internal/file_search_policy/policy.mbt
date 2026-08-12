// Directory pruning belongs to file discovery rather than either of its Host
// or frontend consumers. Keeping the rule in this backend-neutral package
// makes scans, recursive watcher invalidation, and cached-index refreshes agree
// about which descendants can appear in a snapshot.

///|
/// Whether a candidate directory path is excluded from workspace file search.
pub fn excludes_directory(path : String) -> Bool {
  for segment in path.split("/") {
    match segment {
      ".git"
      | ".claude"
      | ".codex"
      | ".cursor"
      | ".moonagent"
      | ".openseek"
      | "target"
      | "_build"
      | "node_modules"
      | ".mooncakes"
      | ".repos"
      | ".worktrees" => return true
      _ => ()
    }
  }
  false
}

///|
/// Whether a path is below an excluded directory. The excluded basename itself
/// remains observable because it may be a regular file; discovery excludes it
/// only after learning that the directory entry is a directory.
pub fn excludes_descendant(path : String) -> Bool {
  let mut excluded_ancestor = false
  for segment in path.split("/") {
    if excluded_ancestor && !segment.is_empty() {
      return true
    }
    excluded_ancestor = excludes_directory(segment.to_owned())
  }
  false
}

///|
test "excluded directory policy distinguishes basenames from descendants" {
  assert_false(excludes_descendant("target"))
  assert_false(excludes_descendant("src/.git"))
  assert_true(excludes_descendant("target/cache"))
  assert_true(excludes_descendant("src/.git/config"))
  assert_false(excludes_descendant("src/main.mbt"))
}
