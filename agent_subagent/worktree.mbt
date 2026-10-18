///|
/// The worktree a worker is started in: a slice of the launching checkout
/// named `name`, in which it may change only `allowed_paths`
/// (repository-relative prefixes, disjoint from every other active slice's).
pub(all) struct Slice {
  name : String
  allowed_paths : Array[String]
}

///|
/// What can be done with a worker's worktree once its worker has ended.
pub(all) enum WorktreeAction {
  /// Merge its committed changes into the launching checkout.
  Integrate
  /// Commit a conflicted integration whose markers were resolved.
  Continue
  /// Abandon a conflicted integration; the branch and worktree stay.
  Abort
  /// Remove the worktree and branch without integrating.
  Discard
}

///|
/// What `Launcher::worktree` did.
pub(all) enum WorktreeResult {
  /// The worktree is now in this state (published as `WorkerChanged`), with
  /// what happened in words.
  Changed(@protocol.Worktree, detail~ : Array[String])
  /// Nothing changed, for this reason.
  Refused(String)
  /// The session has no worktree of a worker this session started.
  Unknown
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
      (Captured, _) => Unmergeable(defects=entry.defects().copy())
      (Committed, Some(commit)) => Committed(commit~)
      (Conflicted, Some(commit)) => Conflicted(commit~)
      (Committed | Conflicted, None) =>
        Unmergeable(defects=["the registry records no commit"])
      (Integrated, _) => Integrated
      (Discarded, _) => Discarded
      (NoChanges, _) => NoChanges
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
/// Decide from git what a worker left in its worktree: commit its changes
/// when they pass validation. Runs when its job ends, before the terminal
/// record, which therefore carries the worktree's state.
async fn capture(child : Child, provisioned : @subtask.Provisioned) -> Unit {
  child.workspace = Worktree(
    captured(@subtask.capture(provisioned.geometry, provisioned.entry)),
  )
}

///|
/// The record of a capture: when git itself failed, the worktree is left as
/// it was, to be captured again (`Launcher::worktrees`), and says why.
fn captured(outcome : @subtask.CaptureOutcome) -> @protocol.Worktree {
  let worktree = worktree_of(outcome.entry)
  match outcome.entry.state {
    Provisioning | Running =>
      { ..worktree, state: CaptureFailed(reasons=outcome.defects.copy()), }
    _ => worktree
  }
}

///|
/// The worktrees of the workers this session started, in any state.
///
/// A worktree whose worker is not running in this engine (it was ended with
/// an earlier engine) is recovered first: its changes are captured from git,
/// or, if the engine died while forking it, it is removed. Either change is
/// published as `WorkerChanged`.
pub async fn Launcher::worktrees(
  self : Launcher,
) -> Result[Array[(String, @protocol.Worktree)], String] {
  guard self.cwd is Some(root) else { return Ok([]) }
  let geometry = @subtask.resolve_geometry(root)
  guard geometry is Ok(geometry) else {
    // Not a git checkout: no worker could have been started here.
    return Ok([])
  }
  let found = []
  for found_entry in self.entries(geometry) {
    let (session, entry) = found_entry
    let entry = if self.working.contains(session) {
      entry
    } else {
      match entry.state {
        Running => {
          let worktree = captured(@subtask.capture(geometry, entry))
          (self.on_worker)(session, worktree)
          found.push((session, worktree))
          continue
        }
        Provisioning =>
          match @subtask.discard(geometry, entry) {
            Ok(entry) => {
              (self.on_worker)(session, worktree_of(entry))
              entry
            }
            Err(_) => entry
          }
        _ => entry
      }
    }
    found.push((session, worktree_of(entry)))
  }
  Ok(found)
}

///|
/// Integrate, continue or abort the integration of, or discard the worktree
/// of `worker`: the job id of a worker this engine ran, or the session of
/// any worker this session started.
pub async fn Launcher::worktree(
  self : Launcher,
  worker : String,
  action : WorktreeAction,
) -> WorktreeResult {
  guard self.find(worker) is Some((session, geometry, entry)) else {
    return Unknown
  }
  guard !self.working.contains(session) else {
    return Refused("its worker is still running; stop it or wait for it first")
  }
  // A worktree that is gone is not touched again: a newer slice may have
  // reused its name and directory.
  guard !entry.state.is_terminal() else {
    return Refused("it is already \{describe_state(worktree_of(entry).state)}")
  }
  let result = match action {
    Integrate => outcome(@subtask.integrate(geometry, entry))
    Continue => outcome(@subtask.integrate_continue(geometry, entry))
    Abort => outcome(@subtask.integrate_abort(geometry, entry))
    Discard =>
      match @subtask.discard(geometry, entry) {
        Ok(entry) => Ok((entry, ["discarded"]))
        Err(reason) => Err(reason)
      }
  }
  match result {
    Ok((entry, detail)) => {
      let worktree = worktree_of(entry)
      (self.on_worker)(session, worktree)
      Changed(worktree, detail~)
    }
    Err(reason) => Refused(reason)
  }
}

///|
/// The worktree of `worker` (a job id of this engine, or a session): its
/// worker's session, the repository it is in, and its registry entry.
async fn Launcher::find(
  self : Launcher,
  worker : String,
) -> (String, @subtask.Geometry, @subtask.SubtaskEntry)? {
  let session = match self.runtime.snapshot(worker) {
    Some({ subagent: Some(info), .. }) => info.session
    _ => worker
  }
  guard self.cwd is Some(root) &&
    @subtask.resolve_geometry(root) is Ok(geometry) else {
    return None
  }
  self
  .entries(geometry)
  .iter()
  .filter(found => found.0 == session)
  .last()
  .map(found => (session, geometry, found.1))
}

///|
/// What `worker` changed, as git shows it, in at most `limit` characters:
/// a committed worktree's commit against its base, or, before a commit, its
/// working tree against its base. `None` when the session has no such
/// worker; `Err` when there is nothing to show or git failed.
pub async fn Launcher::changes(
  self : Launcher,
  worker : String,
  limit~ : Int32 = 40_000,
) -> Result[String, String]? {
  guard self.find(worker) is Some((_, geometry, entry)) else { return None }
  let (cwd, range) = match (entry.state, entry.commit_oid) {
    (Committed | Conflicted, Some(commit)) =>
      (geometry.origin_root, [entry.base_oid, commit])
    (Running | Captured, _) => (entry.worker_root, [entry.base_oid])
    _ =>
      return Some(
        Err(
          "its worktree is \{describe_state(worktree_of(entry).state)}; there is nothing to show",
        ),
      )
  }
  let text = StringBuilder()
  let diff = ["diff", "--no-ext-diff", "--no-color"]
  for args in [[..diff, "--stat", ..range], [..diff, ..range]] {
    match @subtask.git_require(["--no-pager", ..args], cwd~) {
      Ok(output) => text.write_string(output)
      Err(reason) => return Some(Err(reason))
    }
  }
  if range.length() == 1 {
    match
      @subtask.git_require(["ls-files", "--others", "--exclude-standard"], cwd~) {
      Ok(untracked) if !untracked.is_blank() =>
        text.write_string("\nuntracked:\n\{untracked}")
      _ => ()
    }
  }
  let text = text.to_string()
  Some(
    Ok(
      if text.length() <= limit {
        text
      } else {
        String::from_iter(text.iter().take(limit)) +
        "\n… (\{text.length() - limit} more characters: run git diff \{range.join(" ")} in \{cwd} for the rest)"
      },
    ),
  )
}

///|
fn outcome(
  outcome : @subtask.IntegrateOutcome,
) -> Result[(@subtask.SubtaskEntry, Array[String]), String] {
  if outcome.result == "refused" {
    Err(outcome.detail.join("; "))
  } else {
    Ok((outcome.entry, [outcome.result, ..outcome.detail]))
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
/// A worktree's state, in words for the model.
pub fn describe_state(state : @protocol.WorktreeState) -> String {
  match state {
    Working => "being worked on"
    CaptureFailed(reasons~) =>
      "not captured: \{reasons.join("; ")} (listing worktrees captures it again)"
    Committed(commit~) => "committed as \{commit}, ready to integrate"
    NoChanges => "unchanged; its worktree is gone"
    Unmergeable(defects~) =>
      "not mergeable: \{defects.join("; ")}; its worktree is kept for inspection"
    Conflicted(commit~) =>
      "conflicted while integrating \{commit}: resolve the markers in this checkout, then continue (or abort)"
    Integrated => "integrated; its worktree is gone"
    Discarded => "discarded; its worktree is gone"
  }
}
