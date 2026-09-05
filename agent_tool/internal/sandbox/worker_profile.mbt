///|
/// The kernel-enforced write scope of one worker subagent: everything the
/// repository shares is denied, the worker's own tree is re-allowed.
///
/// Rule order is load-bearing (SBPL is last-match-wins):
///
///   (allow default)                       — cooperative model: the layer
///                                           confines against THIS repository
///                                           and its worktrees, not the wider
///                                           filesystem
///   (deny  file-write* <each deny root>)  — canonical common git dir + every
///                                           enumerated worktree root,
///                                           including the origin toplevel
///   (allow file-write* <worker root>)     — the worker's own linked worktree,
///                                           nested inside a denied root
///   (allow file-write* <worker admin>)    — the worktree's PRIVATE admin dir
///                                           (resolved via rev-parse, never
///                                           constructed), so status/diff can
///                                           write their index and locks
///   (deny  file-write* literal <worker root>/.git)
///                                         — the gitfile pointer, last so it
///                                           wins over the worker-root allow
///
/// Net effect: moon writes `wt/_build` and shared caches; `git status`/`diff`
/// work; `git commit` and every shared object/ref/config/worktree mutation
/// fail; sibling and origin writes fail. Worker-private HEAD/index mutation
/// remains possible by design and is detected at capture time by the
/// controller.
priv struct WorkerWriteProfileData {
  profile : String
  denial_subjects : Array[String]
}

///|
/// Build the worker profile from canonical (realpath'd) inputs. Validation
/// raises on caller bugs rather than failing open: the worker root must sit
/// strictly below one of the denied roots (that nesting is what the re-allow
/// exists to carve out), and no denied root may sit at or below the worker
/// root (the allow would re-open it wholesale).
fn worker_write_profile_data(
  deny_roots : Array[String],
  worker_root~ : String,
  worker_admin_dir~ : String,
) -> WorkerWriteProfileData raise {
  guard !deny_roots.is_empty() else {
    fail("worker profile needs at least one denied root")
  }
  guard deny_roots.any(root => {
    @workspace_path.is_under_workspace_root(root, worker_root) &&
    root != worker_root
  }) else {
    fail("worker_root must be nested below a denied root")
  }
  for root in deny_roots {
    if @workspace_path.is_under_workspace_root(worker_root, root) {
      fail("a denied root sits at or below worker_root: \{root}")
    }
  }
  // The admin allow is a carve-out INSIDE a denied root (the common git
  // dir's worktrees/<name> subdirectory). A miscomputed admin path that sits
  // at a denied root — or above one — would re-open shared objects, refs,
  // and config wholesale, because SBPL is last-match-wins.
  guard deny_roots.any(root => {
    @workspace_path.is_under_workspace_root(root, worker_admin_dir) &&
    root != worker_admin_dir
  }) else {
    fail("worker_admin_dir must be nested below a denied root")
  }
  for root in deny_roots {
    if @workspace_path.is_under_workspace_root(worker_admin_dir, root) {
      fail("worker_admin_dir covers a denied root: \{root}")
    }
  }
  let profile = StringBuilder()
  profile <+
    $|(version 1)
    $|(allow default)
    $|
  // Same path-then-basename subjects the source-write profile names, in the
  // same order; the `.git` literal below still appends after them.
  let denial_subjects = source_write_denial_subjects(deny_roots)
  for root in deny_roots {
    profile <+
      $|(deny file-write* (subpath "\{sbpl_string_escape(root)}"))
      $|
  }
  profile <+
    $|(allow file-write* (subpath "\{sbpl_string_escape(worker_root)}"))
    $|(allow file-write* (subpath "\{sbpl_string_escape(worker_admin_dir)}"))
    $|
  let gitfile = "\{worker_root}/.git"
  profile <+
    $|(deny file-write* (literal "\{sbpl_string_escape(gitfile)}"))
    $|
  denial_subjects.push(gitfile)
  { profile: profile.to_string(), denial_subjects, }
}

///|
/// Prepare `command` under a worker write profile, or `None` when this
/// process cannot enforce one (same availability contract as
/// `create_if_available`). All paths must already be canonical: the caller
/// (the subtask controller) realpaths them at provision time, and the kernel
/// matches rules against realpaths.
pub async fn SandboxedCommand::create_worker_if_available(
  command : Command,
  deny_roots~ : Array[String],
  worker_root~ : String,
  worker_admin_dir~ : String,
) -> SandboxedCommand? {
  // Validate before the availability probe so caller bugs surface on every
  // platform (see create_if_available).
  let data = worker_write_profile_data(
    deny_roots,
    worker_root~,
    worker_admin_dir~,
  )
  guard sandbox_exec_available() else { return None }
  let args = match command {
    Shell(cmd) => sandbox_exec_args(data.profile, cmd)
    Exec(program, args) => ["-p", data.profile, program, ..args]
  }
  Some({
    program: SandboxExecPath,
    args,
    denial_subjects: data.denial_subjects,
    plain_source_readonly: false,
    denial_feedback: worker_write_denial_feedback,
  })
}
