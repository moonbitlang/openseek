///|
/// The kernel-enforced write scope of a snippet run: nothing outside the
/// workspace and the toolchain's own directories.
///
/// This is the INVERSE of `source_write_profile`, and the two answer different
/// questions. That one is `(allow default)` plus "no writing source under the
/// workspace" — it protects the user's files from a command that should have
/// been an `edit`, and lets everything else through, including `rm -rf` on a
/// home directory. This one denies writes globally and re-allows an enumerated
/// set, so `moon fmt` and `git checkout` do their job while nothing reaches
/// outside the tree being worked on.
///
/// Which one is right depends on what else constrains the run. A shell can run
/// any program, so "don't touch source" is the only rule that can be stated
/// without enumerating the world. A snippet's programs come from an allowlist
/// that admits no shell, no interpreter, and no ad-hoc rewriter — so the reason
/// to forbid source writes is already covered, and the boundary worth drawing
/// is the workspace itself.
///
/// Reads are left alone: a run legitimately reads the toolchain, system
/// libraries, and configuration, and enumerating that is the "cooperative
/// model" problem this profile exists to avoid.
fn workspace_boundary_profile_data(
  real_workspace_root : String,
  writable_roots : Array[String],
) -> String {
  let profile = StringBuilder()
  // SBPL is last-match-wins: deny every write, then re-open the roots this run
  // needs. `file-write*` covers creation, rewriting, and unlink alike.
  //
  // `/dev` is re-allowed unconditionally because a global write deny takes down
  // ordinary programs, not just escapes: `git` opens `/dev/null` for writing and
  // dies with `fatal: could not open '/dev/null'` without it. Device nodes are
  // not what this boundary is about, and as an unprivileged user the reachable
  // ones are the null/tty/random set anyway.
  profile <+
    $|(version 1)
    $|(allow default)
    $|(deny file-write*)
    $|(allow file-write* (subpath "/dev"))
    $|(allow file-write* (subpath "\{sbpl_string_escape(real_workspace_root)}"))
    $|
  for root in writable_roots {
    if root != "" {
      profile <+
        $|(allow file-write* (subpath "\{sbpl_string_escape(root)}"))
        $|
    }
  }
  profile.to_string()
}

///|
/// Wrap `command` so its process tree may write only inside `workspace_root`
/// and `writable_roots`. Returns `None` where the kernel layer is unavailable
/// (not macOS, or a nested sandbox that cannot apply a profile), which is the
/// same best-effort posture as the rest of this module — there the cross-platform
/// half of the confinement is whatever the caller's own policy states.
///
/// `denial_subjects` are the paths a denial message may name, so a caller can
/// recognize its own denial in a child's output.
pub async fn SandboxedCommand::create_workspace_boundary_if_available(
  workspace_root : String,
  command : Command,
  writable_roots? : Array[String] = [],
) -> SandboxedCommand? {
  let real_workspace_root = @fs.realpath(workspace_root)
  guard sandbox_exec_available() else { return None }
  let real_writable = []
  for root in writable_roots {
    let real = @fs.realpath(root) catch { _ => continue }
    real_writable.push(real)
  }
  let profile = workspace_boundary_profile_data(
    real_workspace_root, real_writable,
  )
  let args = match command {
    Shell(cmd) => sandbox_exec_args(profile, cmd)
    Exec(program, args) => ["-p", profile, program, ..args]
  }
  Some({
    program: SandboxExecPath,
    args,
    // Not the plain source-readonly profile: there is no trusted-writer retry
    // that could succeed here, because nothing about this profile depends on
    // how the command was spelled.
    plain_source_readonly: false,
    denial_shape: OutsideRoots([real_workspace_root, ..real_writable]),
  })
}
