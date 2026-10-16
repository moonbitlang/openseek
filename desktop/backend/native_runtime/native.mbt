///|
extern "C" fn known_folder_documents() -> Bytes = "openseek_desktop_documents_dir"

///|
/// Install process-level platform authorities and create the desktop PTY
/// adapter. The session task group retains native PTY's cancellation/reaping.
pub fn native() -> @runtime.HostRuntime {
  @userdirs.install_windows_documents(() => {
    let bytes = known_folder_documents()
    if bytes.is_empty() {
      None
    } else {
      Some(@pathx.Path(@utf8.decode_lossy(bytes)))
    }
  })
  @host_log.install((level, category, loc, fields) => {
    let level : @xlog.Level = match level {
      Debug => Debug
      Info => Info
      Warn => Warn
      Error => Error
    }
    if @xlog.event(level, category?, loc~) is Some(event) {
      event.write_object_begin()
      if fields is Object(fields) {
        for key, value in fields {
          event.write_object_field(key, value)
        }
      }
      event.write_object_end()
    }
  })
  {
    spawn_pty: (group, file, args, cwd, cols, rows) => {
      let pty = @pty.spawn(
        group,
        file.view(),
        args.map(arg => arg.view()),
        cwd~,
        cols~,
        rows~,
      )
      {
        pid: pty.pid(),
        read: buf => pty.read(buf),
        write: data => pty.write(data),
        resize: (cols, rows) => pty.resize(cols~, rows~),
        wait: () => pty.wait(),
      }
    },
  }
}
