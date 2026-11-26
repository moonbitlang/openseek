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
/// Spawn a supervised child. On cancellation, run `on_cancel` before asking
/// core to terminate it using `cancel_handler`. The hook may close an input
/// channel and wait for a graceful exit. If the child exits during the hook,
/// the hook is cancelled immediately. If the hook fails, termination still
/// runs and the task group joins the child before reporting the failure.
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
  on_cancel~ : async (Int32) -> Unit = _ => (),
  no_wait? : Bool,
) -> Process {
  let ready : @async.Queue[Result[@process.Process, Error]] = Queue(
    kind=Blocking(1),
  )
  let result = group.spawn(no_wait?, () => {
    let mut exit_code = 0
    ignore(
      @async.handle_cancellation(() => {
        @async.with_task_group(lifetime => {
          let started : @async.Queue[Result[@process.Process, Error]] = Queue(
            kind=Blocking(1),
          )
          let owner = lifetime.spawn(allow_failure=true, () => {
            @async.protect_from_cancel(() => {
              let mut code = 0
              @async.with_task_group(owned => {
                let child = @process.spawn(
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
                ) catch {
                  error => {
                    started.put(Err(error))
                    return
                  }
                }
                started.put(Ok(child))
                code = child.wait()
              })
              code
            })
          })
          // Finish the spawn handshake even if cancellation arrives while core
          // is opening the child. Both the caller and supervisor receive failure.
          let outcome = @async.protect_from_cancel(() => {
            let outcome = started.get()
            ready.put(outcome)
            outcome
          })
          let child = match outcome {
            Ok(child) => child
            Err(_) => return
          }
          match @async.handle_cancellation(() => owner.wait()) {
            Some(code) => exit_code = code
            None =>
              @async.protect_from_cancel(() => {
                @async.with_task_group(cancelling => {
                  cancelling.spawn_bg(no_wait=true, () => {
                    defer child.cancel()
                    on_cancel(child.pid)
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
  let child = ready.get().unwrap_or_error()
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
