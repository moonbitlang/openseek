///|
/// A platform PTY. Its owning task group controls process cancellation and
/// reaping. Transport failures remain errors, distinct from the exit code.
pub(all) struct Pty {
  pid : Int32
  read : async (FixedArray[Byte]) -> Int32
  write : async (Bytes) -> Unit
  resize : (Int32, Int32) -> Unit raise
  wait : async () -> Int32
}

///|
/// OS operations supplied by the process embedding the shared service.
pub(all) struct HostRuntime {
  spawn_pty : async (
    @async.TaskGroup[Unit],
    String,
    Array[String],
    String,
    Int32,
    Int32,
  ) -> Pty
}

///|
pub suberror UnsupportedRuntime {
  UnsupportedRuntime(String)
}

///|
/// A host without terminal support fails terminal creation explicitly. Useful
/// for headless consumers which do not install an OS adapter.
pub fn HostRuntime::without_terminal() -> HostRuntime {
  {
    spawn_pty: (_, _, _, _, _, _) => {
      raise UnsupportedRuntime("PTY adapter is not installed")
    },
  }
}
