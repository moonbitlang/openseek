///|
/// Tie the whole process tree of `proc` to the lifetime of `proc` itself, so
/// that once `proc` exits — killed or not — nothing it started outlives it.
///
/// Call it right after `@process.spawn`, in the same task group.
///
/// On native Windows, `proc` and any descendants it already spawned are placed
/// in a dedicated kill-on-close Job Object that disallows breakaway. A
/// background task in `group` terminates the job when `proc` exits or when
/// `group` is torn down. Containment is best effort: if the job cannot be set
/// up, `proc` runs as usual.
#cfg(all(target="native", platform="windows"))
pub fn contain_process_tree(
  group : @async.TaskGroup,
  proc : @process.Process,
) -> Unit {
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
/// A no-op on Unix and wasm.
#cfg(not(all(target="native", platform="windows")))
pub fn contain_process_tree(
  _group : @async.TaskGroup,
  _proc : @process.Process,
) -> Unit {
  ()
}

///|
/// Put process `pid` and its existing descendants in a new kill-on-close Job
/// Object; returns the job handle, or 0 when containment is unavailable.
#cfg(all(target="native", platform="windows"))
extern "C" fn contain_ffi(pid : Int32) -> UInt64 = "openseek_desktop_process_tree_contain"

///|
/// Terminate every process in the job and close its handle.
#cfg(all(target="native", platform="windows"))
extern "C" fn terminate_ffi(job : UInt64) = "openseek_desktop_process_tree_terminate"
