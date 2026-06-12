// Launch diagnostics for the packaged app: a double-clicked bundle has no
// terminal, so startup problems would otherwise vanish. Every process
// start/exit appends a timestamped line to `openseek-desktop.log` beside the
// executable.

///|
fn launch_log_path(framework_command : String) -> String {
  let command_path : @mbpath.Path = framework_command
  command_path
  .dirname()
  .resolve()
  .join("openseek-desktop.log")
  .normalize()
  .to_string()
}

///|
fn append_launch_log(framework_command : String, message : String) -> Unit {
  let path = launch_log_path(framework_command)
  let previous = if @mbfs.path_exists(path) {
    @mbfs.read_file_to_string(path) catch {
      _ => ""
    }
  } else {
    ""
  }
  let line = @env.now().to_string() + " " + message + "\n"
  ignore(@mbfs.write_string_to_file(path, previous + line) catch { _ => () })
}
