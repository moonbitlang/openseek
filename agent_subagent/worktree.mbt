///|
/// The worktree a worker is started in: a slice of the launching checkout
/// named `name`, in which it may change only `allowed_paths`
/// (repository-relative prefixes, disjoint from every other active slice's).
pub(all) struct Slice {
  name : String
  allowed_paths : Array[String]
}

///|
/// The record of `entry` as a host shows it.
fn worktree_of(entry : @subtask.SubtaskEntry) -> @protocol.Worktree {
  {
    name: entry.name,
    path: entry.worker_root,
    branch: entry.branch,
    base: entry.base_oid,
    allowed_paths: entry.allowed_paths.copy(),
    state: match (entry.state, entry.commit_oid) {
      (Provisioning | Running, _) => Working
      (Committed, Some(commit)) => Committed(commit~)
      (NoChanges, _) => NoChanges
      (Captured, _) => Unmergeable(defects=entry.defects().copy())
      // States of the integration this engine no longer drives.
      (Committed | Conflicted, None) | (Integrated | Discarded, _) =>
        Unmergeable(defects=["the registry records no capture"])
      (Conflicted, Some(commit)) => Committed(commit~)
    },
  }
}

///|
/// `input` with the worktree a worker was given: where it is, what it may
/// change, what it must not touch, and the commit it starts from. The
/// worker enforces with what it is handed rather than deriving anything.
fn worker_input(
  input : Map[String, Json],
  provisioned : @subtask.Provisioned,
) -> Json {
  let entry = provisioned.entry
  let fields = Map::from_iter(input.iter())
  fields["worker_root"] = Json(entry.worker_root)
  fields["worker_admin_dir"] = Json(entry.worker_admin_dir)
  // Resolved before the worktree existed, so the worker's own root is not
  // among them.
  fields["deny_roots"] = Json(provisioned.geometry.worker_deny_roots())
  fields["allowed_paths"] = Json(entry.allowed_paths)
  fields["base_oid"] = Json(entry.base_oid)
  Json::object(fields)
}

///|
/// Fork a worktree for the child `claimed` from the launching checkout.
async fn Launcher::provision(
  self : Launcher,
  slice : Slice,
  claimed : @agent_subrun.ClaimedChild,
) -> Result[@subtask.Provisioned, String] {
  guard self.cwd is Some(root) else {
    return Err("this session has no checkout to fork a worktree from")
  }
  @subtask.provision(
    root,
    name=slice.name,
    allowed_paths=slice.allowed_paths,
    nonce="\{self.nonce_prefix()}\{claimed.subrun_id}",
    parent_session=self.children.parent(),
  )
}

///|
/// What starts the nonce of every worktree this session forks: a digest of
/// the parent session, so two sessions' `sr-N` never share a registry entry
/// or branch, and a name a branch can carry whatever the session is called.
/// The child's `sr-N` follows, so the entry alone names the worker's session.
fn Launcher::nonce_prefix(self : Launcher) -> String {
  let digest = @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(self.children.parent())),
  )
  "\{digest.view(end_offset=8)}-"
}

///|
/// How many times capture is tried when git itself fails (an index lock,
/// a slow disk), and how long apart.
const CaptureAttempts : Int32 = 3

///|
const CaptureRetryMs : Int32 = 1_000

///|
/// Decide from git what a worker left in its worktree, then hand it over.
/// Runs when its job ends, before the terminal record, which therefore
/// carries the result: its commit, that it changed nothing, or why it could
/// not be taken.
async fn capture(child : Child, provisioned : @subtask.Provisioned) -> Unit {
  child.workspace = Worktree(hand_over(provisioned.geometry, provisioned.entry))
}

///|
/// Capture `entry` (retrying while git itself fails) and release it to its
/// launcher: a committed slice keeps only its branch, an unmergeable or
/// uncaptured one keeps its worktree, and its paths are free again.
async fn hand_over(
  geometry : @subtask.Geometry,
  entry : @subtask.SubtaskEntry,
) -> @protocol.Worktree {
  let mut outcome = @subtask.capture(geometry, entry)
  for attempt = 1
      attempt < CaptureAttempts &&
     outcome.entry.state is (Provisioning | Running)
      attempt = attempt + 1 {
    @async.sleep(CaptureRetryMs)
    outcome = @subtask.capture(geometry, outcome.entry)
  }
  let worktree = captured(outcome)
  match @subtask.hand_off(geometry, outcome.entry) {
    Ok(_) => worktree
    Err(reason) =>
      {
        ..worktree,
        state: CaptureFailed(
          reasons=[
            ..failure_reasons(worktree.state),
            "it could not be released: \{reason}",
          ],
        ),
      }
  }
}

///|
fn failure_reasons(state : @protocol.WorktreeState) -> Array[String] {
  match state {
    CaptureFailed(reasons~) => reasons.copy()
    Unmergeable(defects~) => defects.copy()
    _ => []
  }
}

///|
/// The record of a capture: when git itself failed, the worktree is left as
/// the worker left it, and says why.
fn captured(outcome : @subtask.CaptureOutcome) -> @protocol.Worktree {
  let worktree = worktree_of(outcome.entry)
  match outcome.entry.state {
    Provisioning | Running =>
      { ..worktree, state: CaptureFailed(reasons=outcome.defects.copy()), }
    _ => worktree
  }
}

///|
/// Hand over what an earlier engine of this session left, and report it:
/// a worktree whose worker it never captured, or captured and never
/// released; and one it handed over that no notice of this engine carried
/// (it ended as that engine shut down) and whose result is still there.
/// Each comes back with its worker's session, since its job is not this
/// engine's to read, until `reported` says the caller delivered it. A
/// worktree the engine died forking is removed. Run before a worker starts, so what it left no longer holds
/// paths the new worker may need.
pub async fn Launcher::recover(
  self : Launcher,
) -> Array[(String, @protocol.Worktree)] {
  guard self.cwd is Some(root) &&
    @subtask.resolve_geometry(root) is Ok(geometry) else {
    return []
  }
  let recovered = []
  for found in self.entries(geometry) {
    let (session, entry) = found
    guard !self.working.contains(session) && !self.known.contains(session) else {
      continue
    }
    if !entry.is_released() {
      if entry.state is Provisioning {
        ignore(@subtask.discard(geometry, entry))
        continue
      }
      recovered.push((session, hand_over(geometry, entry)))
    } else if left_over(geometry, entry) is Some(worktree) {
      recovered.push((session, worktree))
    }
  }
  recovered
}

///|
/// The caller delivered what `recover` returned for these worker sessions:
/// it is not reported again by this engine.
pub fn Launcher::reported(self : Launcher, sessions : Array[String]) -> Unit {
  for session in sessions {
    self.known[session] = ()
  }
}

///|
/// What a handed-over entry still holds for its launcher: its committed
/// branch, unless the change was taken and the branch deleted; or the files
/// it kept. `None` once nothing is left.
async fn left_over(
  geometry : @subtask.Geometry,
  entry : @subtask.SubtaskEntry,
) -> @protocol.Worktree? {
  let worktree = worktree_of(entry)
  match (entry.state, entry.commit_oid) {
    (Committed, Some(commit)) => {
      let tip = @subtask.git_require(
        ["rev-parse", "--verify", "refs/heads/\{entry.branch}"],
        cwd=geometry.origin_root,
      )
      guard tip is Ok(tip) && tip.trim() == commit else { return None }
      Some(worktree)
    }
    (Captured | Running, _) => {
      guard (@fs.exists(entry.worker_root) catch { _ => false }) else {
        return None
      }
      Some(
        if entry.state is Running {
          {
            ..worktree,
            state: CaptureFailed(reasons=[
              "git could not capture it before its engine ended",
            ]),
          }
        } else {
          worktree
        },
      )
    }
    _ => None
  }
}

///|
/// This session's registry entries in `geometry`'s repository, each with
/// the session of the worker it was forked for.
async fn Launcher::entries(
  self : Launcher,
  geometry : @subtask.Geometry,
) -> Array[(String, @subtask.SubtaskEntry)] {
  let parent = self.children.parent()
  let prefix = self.nonce_prefix()
  let (entries, _) = @subtask.load_entries(geometry.common_git_dir)
  entries
  .iter()
  .filter_map(entry => {
    guard entry.parent_session() is Some(owner) &&
      owner == parent &&
      entry.nonce().strip_prefix(prefix) is Some(subrun) else {
      return None
    }
    Some(("\{parent}-\{subrun}", entry))
  })
  .to_array()
}

///|
/// Where a worker's change is and what to do with it, in words for the
/// model: the commands are plain git, run through mbtx.
pub fn describe_worktree(worktree : @protocol.Worktree) -> String {
  let name = worktree.name
  match worktree.state {
    Working =>
      "worktree \{name} at \{worktree.path}: its worker is still running"
    Committed(commit~) =>
      (
        $|worktree \{name}: its change is commit \{commit} on branch \{worktree.branch} (forked from \{worktree.base}; the checkout was removed).
        $|Review it with `git diff \{worktree.base} \{commit}`, then take it with `git cherry-pick \{commit}` (on a conflict, resolve the markers, `git add` them, then `git cherry-pick --continue`, or `--abort`), and delete the branch with `git branch -D \{worktree.branch}`.
      )
    NoChanges =>
      "worktree \{name}: its worker changed nothing; its worktree and branch were removed"
    Unmergeable(defects~) =>
      "worktree \{name}: not mergeable (\{defects.join("; ")}); its files are kept at \{worktree.path} for inspection, on branch \{worktree.branch}"
    CaptureFailed(reasons~) =>
      "worktree \{name}: git could not capture it (\{reasons.join("; ")}); its files are kept at \{worktree.path}, on branch \{worktree.branch}"
  }
}

///|
/// Where a subagent's change is and what to do with it, for `job_output`:
/// `None` for a child that works in the session's checkout and changes
/// nothing there.
pub fn describe_workspace(workspace : @protocol.SubagentWorkspace) -> String? {
  match workspace {
    InPlace => None
    Worktree(worktree) => Some(describe_worktree(worktree))
    Directory(path~) =>
      Some(
        "directory \{path}: the worker changes files there in place and leaves what it changed uncommitted. Once it has ended, review it there (in a git repository: `git -C \{path} status` and `git -C \{path} diff`, which also show anything uncommitted there before it started), then commit it or restore it.",
      )
  }
}

///|
/// An ended subagent's change in a few words, for a notice or a wait:
/// `describe_workspace` says what to do with it.
pub fn brief_workspace(workspace : @protocol.SubagentWorkspace) -> String? {
  match workspace {
    InPlace => None
    Worktree(worktree) => Some(brief_worktree(worktree))
    Directory(path~) => Some("its change is left uncommitted in \{path}")
  }
}

///|
/// A worker's handed-over worktree in a few words.
fn brief_worktree(worktree : @protocol.Worktree) -> String {
  match worktree.state {
    Working => "its worktree \{worktree.name} is still being worked on"
    Committed(commit~) =>
      "its change is commit \{commit} on branch \{worktree.branch}"
    NoChanges => "it changed nothing"
    Unmergeable(..) =>
      "its change is not mergeable; its files are kept at \{worktree.path}"
    CaptureFailed(..) =>
      "git could not capture its change; its files are kept at \{worktree.path}"
  }
}
