// The pseudo-terminal seam. Sessions, flow control and the pump stay here and
// build on every target; the operating-system PTY is supplied by the native
// executable at startup (`openseek_desktop/backend/terminal_pty`), so this
// package and the host packages above it do not depend on a native-only PTY
// library.

///|
/// One child process attached to a pseudo-terminal, as a session uses it.
/// The child and its handles belong to the task group passed to the spawner:
/// ending that group stops the child and releases the handles, after which
/// `wait` still reports the child's exit status.
pub(open) trait PtyProcess {
  /// The child's process id.
  fn pid(Self) -> Int32
  /// Read terminal output into the buffer and return the byte count; zero or
  /// an error ends the session's output.
  async fn read(Self, FixedArray[Byte]) -> Int32
  /// Write terminal input bytes to the child.
  async fn write(Self, Bytes) -> Unit
  /// Change the terminal's viewport.
  fn resize(Self, cols~ : Int32, rows~ : Int32) -> Unit raise
  /// The child's exit status; a signal is reported as its negated number.
  async fn wait(Self) -> Int32
}

///|
/// What a session asks the pseudo-terminal spawner to start: `file` with
/// `args`, its working directory applied by the platform spawn itself, and
/// the initial viewport.
pub(all) struct PtySpawn {
  file : String
  args : Array[String]
  cwd : String
  cols : Int32
  rows : Int32
}

///|
/// The installed pseudo-terminal spawner. A build without one still serves
/// every other terminal op, but each open fails with `TerminalError`.
let pty_spawner : Ref[
  (async (@async.TaskGroup[Unit], PtySpawn) -> &PtyProcess)?,
] = { val: None, }

///|
/// Install the process's pseudo-terminal spawner. Native executables call
/// this once at startup, before any connection opens a terminal. The spawner
/// must start the child inside `group` (see `PtyProcess`) and raise when the
/// child cannot be started.
pub fn install_pty_spawner(
  spawn : async (@async.TaskGroup[Unit], PtySpawn) -> &PtyProcess,
) -> Unit {
  pty_spawner.val = Some(spawn)
}
