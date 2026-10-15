///|
/// Read window event sources and deliver their messages serially until
/// cancellation or failure. Each source retains its own message order;
/// independent sources have no ordering guarantee relative to one another.
/// The bounded inbox applies backpressure while delivery is busy. Readers
/// belong to this call and are cancelled and joined when it ends.
pub async fn[T] run(
  sources : Array[async () -> T],
  deliver : async (T) -> Unit,
) -> Unit {
  let inbox : @async.Queue[T] = Queue(kind=Blocking(64))
  @async.with_task_group(group => {
    for source in sources {
      group.spawn_bg(() => {
        for ;; {
          // Racing destructive reads with async.any can consume multiple
          // ready messages while returning only one. Every completed read
          // here has its own delivery into the shared inbox instead.
          inbox.put(source())
        }
      })
    }
    for ;; {
      deliver(inbox.get())
    }
  })
}
