///|
/// The canonical git geometry every subtask operation is decided against.
/// Resolved ONCE per operation from `git rev-parse` and `git worktree list`
/// output — never constructed from names (private admin dirs can carry
/// numeric suffixes; worktrees can live anywhere).
pub struct Geometry {
  /// Canonical toplevel of the worktree that launched the subtask. Captured
  /// changes integrate back into this exact worktree.
  origin_root : String
  /// Canonical common git dir (shared objects/refs/config).
  common_git_dir : String
  /// Every registered worktree root, canonicalized, origin included.
  priv worktree_roots : Array[String]
}

///|
/// Resolve and validate the geometry for `workspace_root`. Both the main
/// worktree and linked worktrees are valid integration targets, but the
/// workspace must be the selected worktree's repository toplevel.
pub async fn resolve_geometry(
  workspace_root : String,
) -> Result[Geometry, String] {
  let probe = git_run(
    ["rev-parse", "--show-toplevel", "--git-common-dir"],
    cwd=workspace_root,
  )
  guard probe.exit_code == 0 else {
    return Err("subtask needs a git repository: \{probe.output.trim()}")
  }
  let lines = probe.output
    .trim()
    .to_owned()
    .split("\n")
    .map(l => l.to_owned())
    .collect()
  guard lines.length() == 2 else {
    return Err("unexpected rev-parse output: \{probe.output}")
  }
  let toplevel = canonical(lines[0])
  let common = canonical(absolutize_against(lines[1], toplevel))
  let workspace = canonical(workspace_root)
  guard workspace == toplevel else {
    return Err(
      "subtask needs the repository toplevel as its workspace (got \{workspace}, toplevel \{toplevel})",
    )
  }
  let listing = git_run(["worktree", "list", "--porcelain", "-z"], cwd=toplevel)
  guard listing.exit_code == 0 else {
    return Err("git worktree list failed: \{listing.output.trim()}")
  }
  let worktree_roots : Array[String] = []
  for record in listing.output.split("\u{0}") {
    let record = record.to_owned()
    if record.has_prefix("worktree ") {
      worktree_roots.push(
        canonical(record.view(start_offset="worktree ".length()).to_owned()),
      )
    }
  }
  guard !worktree_roots.is_empty() else {
    return Err("git worktree list reported no worktrees")
  }
  Ok({ origin_root: toplevel, common_git_dir: common, worktree_roots, })
}

///|
/// Every repository-owned location a worker must not mutate. The common Git
/// directory is listed explicitly because it is not necessarily nested under
/// a worktree root (for example, repositories using `--separate-git-dir`).
pub fn Geometry::worker_deny_roots(self : Geometry) -> Array[String] {
  let roots = Set([self.common_git_dir])
  for root in self.worktree_roots {
    roots.add(root)
  }
  roots.to_array()
}

///|
/// A registry is shared by every worktree of a repository. Bind lifecycle
/// actions to the worktree that provisioned the worker so an action invoked
/// from a sibling worktree cannot merge or discard another worktree's slice.
/// The exact path is safe for schema-v1 entries because provision has always
/// created workers at `<integration-root>/.worktrees/<name>`.
pub fn Geometry::is_integration_target_for(
  self : Geometry,
  entry : SubtaskEntry,
) -> Bool {
  entry.worker_root == "\{self.origin_root}/.worktrees/\{entry.name}"
}

///|
/// realpath when possible; lexical normalization otherwise (a nonexistent
/// path cannot be part of live geometry, but error messages still read).
async fn canonical(path : String) -> String {
  let real = @fs.realpath(path) catch {
    error if @async.is_being_cancelled() => raise error
    _ => path
  }
  @workspace_path.strip_trailing_slash(real)
}

///|
/// `--git-common-dir` may print a path relative to the cwd of the probe.
fn absolutize_against(path : String, base : String) -> String {
  if @path.Path(path).is_absolute() {
    path
  } else {
    "\{base}/\{path}"
  }
}
