///|
/// Hand a captured slice over to its launcher: the engine lets go of it, so
/// it reserves its paths and name no more, and what is left is the
/// launcher's to merge or inspect.
///
/// - A committed slice keeps its branch, which holds the validated commit;
///   its checkout is removed.
/// - A slice whose changes failed validation, or whose capture git itself
///   failed, keeps its worktree, with the files as the worker left them.
/// - A slice with no changes was already removed by its capture.
///
/// The release is what the next provisioning reads, so it is reported only
/// once it is saved.
pub async fn hand_off(
  geometry : Geometry,
  entry : SubtaskEntry,
) -> Result[SubtaskEntry, String] {
  let mutex = repo_mutex(geometry.common_git_dir)
  mutex.acquire()
  defer mutex.release()
  let entry = reload_entry(geometry.common_git_dir, entry)
  guard !entry.is_released() else { return Ok(entry) }
  if entry.state is Committed {
    @fs.rmdir(entry.worker_root, recursive=true) catch {
      _ => ()
    }
    let _ = git_run(["worktree", "prune"], cwd=geometry.origin_root)
  }
  let entry = { ..entry, handed_off: true, }
  save_entry(geometry.common_git_dir, entry).map(_ => entry)
}
