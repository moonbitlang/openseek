///|
/// A single-slot async task runner: a `Queue` hands submitted jobs to one
/// worker loop (`run`) that runs them one at a time, letting the TUI run a
/// single agent task at a time.
struct Queue {
  aq : @aqueue.Queue[async () -> Unit]
}

///|
/// Submit `f` to the queue and await its result, propagating any error it
/// raises. Blocks until the worker loop picks the job up and runs it.
pub async fn[T] Queue::wait(self : Queue, f : async () -> T) -> T {
  let result : @aqueue.Queue[Result[T, Error]] = Queue(kind=Blocking(1))
  self.aq.put(() => {
    let value : Result[T, Error] = try? f()
    result.put(value)
  })
  result.get().unwrap_or_error()
}

///|
/// Build a task queue whose submission slot follows `kind` (for example
/// `Blocking(1)` to accept at most one in-flight task).
pub fn Queue::Queue(kind~ : @aqueue.Kind) -> Queue {
  { aq: Queue(kind~) }
}

///|
/// Run the worker loop forever, pulling submitted jobs off the queue one at a
/// time and running each to completion. Spawn this once alongside the callers
/// of `wait`.
pub async fn Queue::run(self : Queue) -> Unit {
  for ;; {
    let task = self.aq.get()
    task()
  }
}
