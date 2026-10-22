///|
/// Tie the whole process tree of `proc` to the lifetime of `proc` itself, so
/// that once `proc` exits — killed or not — nothing it started outlives it.
///
/// Call it right after `@process.spawn`, in the same task group.
///
/// On Unix this is a no-op. `@process.Process::cancel` signals only the spawned
/// PID there too, so a child that forks rather than `exec`s still leaves its
/// own children behind; containing those would take a process group, which
/// the process library does not set up.
///
/// On native Windows the process library's hard kill is `TerminateProcess`
/// on the spawned PID alone, and the runtime's own Job Object lets grandchildren
/// silently break away. So `proc` is placed in a dedicated Job Object that
/// disallows breakaway — everything it starts stays inside — together with
/// any children it started before the assignment. A background task in
/// `group` terminates the job as soon as `proc` exits, for whatever reason:
/// after a graceful exit the job is already empty, while a killed `proc`
/// takes its orphaned descendants down with it. The job also kills its
/// members if this program dies without cleaning up, and the task terminates
/// it if `group` is torn down first.
///
/// Containment is best effort: if the job cannot be set up, `proc` runs
/// exactly as it would without it.
#cfg(all(target="native", platform="windows"))
pub fn[G] contain(group : @async.TaskGroup[G], proc : @process.Process) -> Unit {
  let job = contain_ffi(proc.pid)
  guard job != 0UL else { return }
  group.spawn_bg(no_wait=true) <| () => {
    // Also runs if the task is cancelled by the group's teardown.
    defer terminate_ffi(job)
    proc.wait() |> ignore
  }
}

///|
/// Tie the whole process tree of `proc` to the lifetime of `proc` itself.
///
/// A no-op on Unix and wasm. Wasm has no host API for Windows Job Objects;
/// cancellation there only guarantees termination of the spawned process.
#cfg(not(all(target="native", platform="windows")))
pub fn[G] contain(
  _group : @async.TaskGroup[G],
  _proc : @process.Process,
) -> Unit {
  ()
}

///|
/// Put process `pid` and its existing descendants in a new kill-on-close Job
/// Object; returns the job handle, or 0 when containment is unavailable.
#cfg(all(target="native", platform="windows"))
extern "C" fn contain_ffi(pid : Int32) -> UInt64 = "moonbitlang_openseek_tui_process_tree_contain"

///|
/// Terminate every process in the job and close its handle.
#cfg(all(target="native", platform="windows"))
extern "C" fn terminate_ffi(job : UInt64) = "moonbitlang_openseek_tui_process_tree_terminate"
