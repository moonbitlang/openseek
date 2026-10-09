///|
/// The write confinement of a worker subagent's snippets, carried from the
/// worker controller (which computes the canonical geometry at provision
/// time) into every launch. When present, the snippet — and every process it
/// spawns — runs under the worker write profile, which denies the repository's
/// shared surfaces (`deny_roots`: the canonical common git dir plus every
/// enumerated worktree root) and re-allows only the worker's own tree and its
/// private git admin dir. All paths must be canonical (realpath'd): the kernel
/// matches profile rules against realpaths.
///
/// This replaces the workspace source-write profile rather than adding to it:
/// a worker is *supposed* to write source, just only its own.
///
/// On platforms without sandbox-exec the kernel layer is absent and a snippet
/// runs unconfined — the same best-effort posture as the rest of the sandbox
/// stack there. What still holds on every platform is the file tools'
/// `write_scope` (their paths are checked against the worker's `allowed_paths`)
/// and the worker controller's git-evidence validation before anything is
/// merged; the profile is the layer that also keeps a worker's *commands* out
/// of its siblings' trees.
pub(all) struct WorkerSandbox {
  deny_roots : Array[String]
  worker_root : String
  worker_admin_dir : String
}
