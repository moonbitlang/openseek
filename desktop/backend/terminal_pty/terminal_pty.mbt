// The native pseudo-terminal behind the integrated terminal. The session
// table and pump in `internal/terminal` build on every target; native
// executables install this spawner at startup so their terminals run real
// PTY children through `moonbit-community/pty`.

///|
/// A `moonbit-community/pty` child as the terminal sessions use it.
priv struct NativePty(@pty.Pty)

///|
impl @terminal.PtyProcess for NativePty with fn pid(self) {
  self.0.pid()
}

///|
impl @terminal.PtyProcess for NativePty with fn read(self, buf) {
  self.0.read(buf)
}

///|
impl @terminal.PtyProcess for NativePty with fn write(self, data) {
  self.0.write(data)
}

///|
impl @terminal.PtyProcess for NativePty with fn resize(self, cols~, rows~) {
  self.0.resize(cols~, rows~)
}

///|
impl @terminal.PtyProcess for NativePty with fn wait(self) {
  self.0.wait()
}

///|
/// Start `request` as a PTY child owned by `group`.
async fn spawn(
  group : @async.TaskGroup[Unit],
  request : @terminal.PtySpawn,
) -> &@terminal.PtyProcess {
  let pty = @pty.spawn(
    group,
    request.file,
    request.args.map(arg => arg.clamped_view()),
    cwd=request.cwd,
    cols=request.cols,
    rows=request.rows,
  )
  NativePty(pty)
}

///|
/// Serve this process's terminals with native pseudo-terminals. Native
/// executables call this once at startup; repeated calls are harmless.
pub fn install() -> Unit {
  @terminal.install_pty_spawner(spawn)
}
