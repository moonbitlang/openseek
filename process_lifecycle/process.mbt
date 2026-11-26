///|
/// A child whose cancellation first runs the application's shutdown hook.
/// The child remains owned by the task group until it exits; redirected
/// streams have the same ownership as `@process.Process` streams.
pub struct Process {
  pid : Int32
  stdin : @process.WriteToProcess
  stdout : @process.ReadFromProcess
  stderr : @process.ReadFromProcess
  priv result : @async.Task[Int32]
}

///|
/// Spawn a supervised child. On cancellation, `on_cancel` decides how and when
/// to stop it. Calling the supplied core child's `cancel()` starts the policy
/// selected by `cancel_handler`. Returning without cancelling keeps waiting
/// for the child. If the child exits during the hook, the hook is cancelled.
/// If the hook fails, terminate and join the child before reporting the error:
/// core's public Process API cannot relinquish ownership of a live child.
///
/// Protecting the child's owning group lets the application finish its hook
/// before core starts termination, without detaching the process from its
/// parent or changing Windows child-process ownership.
pub async fn spawn(
  group : @async.TaskGroup,
  cmd : StringView,
  args : ArrayView[String],
  extra_env~ : Map[String, String] = Map([]),
  inherit_env~ : Bool = true,
  stdin~ : @process.ProcessInput = Inherit,
  stdout~ : @process.ProcessOutput = Inherit,
  stderr~ : @process.ProcessOutput = Inherit,
  cwd? : StringView,
  no_console_window~ : Bool = false,
  cancel_handler~ : @process.CancellationHandler = @process.hard_cancel(),
  on_cancel~ : async (@process.Process) -> Unit = child => child.cancel(),
  no_wait? : Bool,
) -> Process {
  spawn_with(
    group,
    owned => {
      @process.spawn(
        owned,
        cmd,
        args,
        extra_env~,
        inherit_env~,
        stdin~,
        stdout~,
        stderr~,
        cwd?,
        no_console_window~,
        cancel_handler~,
      )
    },
    on_cancel~,
    no_wait?,
  )
}

///|
async fn spawn_with(
  group : @async.TaskGroup,
  launch : async (@async.TaskGroup) -> @process.Process,
  on_cancel~ : async (@process.Process) -> Unit,
  no_wait? : Bool,
) -> Process {
  let ready : @async.Queue[@async.TaskGroup] = Queue(kind=Blocking(1))
  let started = @async.Cond()
  let mut spawn_done = false
  let mut spawned : @process.Process? = None
  let result = group.spawn(no_wait?, () => {
    let mut exit_code = 0
    ignore(
      @async.handle_cancellation(() => {
        @async.with_task_group(lifetime => {
          let owner = lifetime.spawn(allow_failure=true, () => {
            @async.protect_from_cancel(() => {
              let mut code = 0
              @async.with_task_group(owned => {
                ignore(ready.try_put(owned))
                while !spawn_done {
                  started.wait()
                }
                if spawned is Some(child) {
                  code = child.wait()
                }
              })
              code
            })
          })
          // The caller performs the cancellable spawn and always publishes its
          // outcome. Only ownership and cleanup are shielded from cancellation.
          @async.protect_from_cancel(() => {
            while !spawn_done {
              started.wait()
            }
          })
          guard spawned is Some(child) else { return }
          match @async.handle_cancellation(() => owner.wait()) {
            Some(code) => exit_code = code
            None =>
              @async.protect_from_cancel(() => {
                @async.with_task_group(cancelling => {
                  cancelling.spawn_bg(no_wait=true, () => {
                    guard child.try_wait() is None else { return }
                    errdefer child.cancel()
                    // Early child exit cancels the hook normally. Only a hook
                    // error needs fallback termination before joining its owner.
                    ignore(@async.handle_cancellation(() => on_cancel(child)))
                  })
                  exit_code = owner.wait()
                })
              })
          }
        })
      }),
    )
    exit_code
  })
  // No suspension between successful spawn and publication: cancellation can
  // never leave a created child without a supervisor or a returned handle.
  defer {
    spawn_done = true
    started.broadcast()
  }
  let owned = ready.get()
  let child = launch(owned)
  spawned = Some(child)
  {
    pid: child.pid,
    stdin: child.stdin,
    stdout: child.stdout,
    stderr: child.stderr,
    result,
  }
}

///|
/// Request shutdown once; repeated cancellation does not rerun the hook.
pub fn Process::cancel(self : Process) -> Unit {
  self.result.cancel()
}

///|
/// Wait for the child and its cancellation hook to finish.
pub async fn Process::wait(self : Process) -> Int32 {
  self.result.wait()
}

///|
/// Return the exit code once the child and its cancellation hook have finished.
pub fn Process::try_wait(self : Process) -> Int32? raise {
  self.result.try_wait()
}
