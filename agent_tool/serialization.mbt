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
  // cancelled waiter. Recheck before entering any synchronous mutation, and
  // yield so the runtime raises its own cancellation signal: an ordinary
  // failure here would fail the waiter's whole task group.
  if @async.is_being_cancelled() {
    @async.pause()
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
  if definition.owns_file_access {
    return definition
  }
  {
    ..definition,
    execute: Async(arguments => {
      self.with_access(() => definition.execute.run(arguments))
    }),
  }
}

///|
/// Registered tools explicitly available to a program. Executors and their
/// captured session state are retained, rather than rebuilt for the client.
pub fn Tools::program_tools(self : Tools) -> Tools raise {
  Tools(
    [
      for tool in self.by_name.values() if tool.is_program_callable() => tool
    ],
  )
}

///|
/// Run human-paced IO outside the file gate, then reacquire it even on
/// cancellation so the enclosing with_access always releases its own lease.
/// Only call from an executor currently inside this map's with_access.
/// The caller must revalidate filesystem state after this returns.
pub async fn[T] FileStateMap::without_access(
  self : FileStateMap,
  operation : async () -> T,
) -> T {
  self.lock.release()
  defer @async.protect_from_cancel(() => self.lock.acquire())
  operation()
}
