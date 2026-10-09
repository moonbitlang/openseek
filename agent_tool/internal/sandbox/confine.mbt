///|
/// Apply the task's OS write restrictions to an executable and its children.
/// Ordinary tasks have no OS profile. Unavailable sandbox-exec keeps the
/// existing best-effort behavior; moonrun policy is applied separately.
pub async fn confine(
  command : Command,
  workspace_root~ : String,
  read_only~ : Bool,
  worker_sandbox? : @write_scope.WorkerSandbox,
  profile_path~ : String,
  writable_subtree~ : String,
) -> SandboxedCommand? {
  match worker_sandbox {
    Some(scope) =>
      SandboxedCommand::create_worker_if_available(
        command,
        deny_roots=scope.deny_roots,
        worker_root=scope.worker_root,
        worker_admin_dir=scope.worker_admin_dir,
      )
    None if read_only =>
      SandboxedCommand::create_if_available(
        workspace_root,
        command,
        profile_path~,
        writable_subtree~,
      )
    None => None
  }
}
