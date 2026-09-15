///|
/// Serialize a complete file operation, including its checks and rollback.
/// Never hold this gate while waiting for a program that may call file tools.
pub async fn[T] FileStateMap::with_access(
  self : FileStateMap,
  operation : async () -> T,
) -> T {
  self.lock.acquire()
  defer self.lock.release()
  // A mutex release can win against cancellation and grant the lock to its
  // cancelled waiter. Recheck before entering any synchronous mutation.
  guard !@async.is_being_cancelled() else {
    fail("File operation cancelled before execution")
  }
  operation()
}

///|
/// Bind a definition to the session's shared file-operation gate. Both direct
/// and programmatic dispatch must use this same wrapped definition.
pub fn FileStateMap::serialize(
  self : FileStateMap,
  definition : AgentToolDefinition,
) -> AgentToolDefinition {
  {
    ..definition,
    execute: Async(arguments => {
      self.with_access(() => definition.execute.run(arguments))
    }),
  }
}
