///|
fn login_shell_quote(value : String) -> String {
  "'" + value.replace_all(old="'", new="'\\''") + "'"
}

///|
async fn login_executable(command : String, path : String?) -> String {
  if @pathx.Path(command).to_absolute() is Some(absolute) {
    guard @fs.can_execute(absolute.to_string()) else {
      raise CodexError::Unavailable("Codex is not executable: \{absolute}")
    }
    return absolute.to_string()
  }
  guard command == DefaultCodexCommand else {
    raise CodexError::Unavailable(
      "Codex command must be an absolute executable path",
    )
  }
  if path is Some(path) {
    for entry in path.split(":") {
      let candidate = @pathx.Path(entry.to_owned()).resolve().join(command)
      let executable = @fs.can_execute(candidate.to_string()) catch {
        @os_error.OSError(_) as error if error.is_ENOENT() || error.is_ENOTDIR() =>
          false
        error => raise error
      }
      if executable && @fs.kind(candidate.to_string()) is Regular {
        return candidate.to_string()
      }
    }
  }
  raise CodexError::Unavailable(
    "Codex was not found on the working host's service PATH. Install Codex there or select its absolute path with --codex-command, then restart the service.",
  )
}

///|
async fn login_help(command : String, home : @pathx.Path) -> String {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let (reader, output) = @process.read_from_process()
      group.add_defer(() => reader.close())
      let (input, writer) = @process.write_to_process()
      writer.close()
      let process = @process.spawn(
        group,
        command,
        ["login", "--help"],
        inherit_env=true,
        extra_env={ "CODEX_HOME": home.to_string() },
        stdin=input,
        stdout=output,
        stderr=output,
        no_wait=true,
        no_console_window=true,
        cancel_handler=@process.hard_cancel(),
      )
      defer process.cancel()
      let buffer = Buffer()
      while reader.read_some(max_len=4096) is Some(bytes) {
        guard buffer.length() + bytes.length() <= 65536 else {
          raise CodexError::Unavailable("Codex login help exceeded 64 KiB")
        }
        buffer.write_bytes(bytes)
      }
      guard process.wait() == 0 else {
        raise CodexError::Unavailable(
          "The selected Codex CLI could not provide login help",
        )
      }
      @utf8.decode_lossy(buffer.to_bytes())
    })
  }) catch {
    @async.TimeoutError =>
      raise CodexError::Unavailable(
        "The selected Codex CLI did not answer login --help within 5 seconds",
      )
    error => raise error
  }
}

///|
/// Produce a POSIX command for this service's CLI and isolated identity. This
/// only probes help: sign-in remains an explicit user action in a remote PTY.
pub async fn Actor::terminal_login_command(self : Actor) -> (String, Bool) {
  if @async.platform is Windows {
    raise CodexError::Unavailable(
      "Terminal login instructions require a POSIX working host",
    )
  }
  let home = self.prepare_config_home().resolve().to_path()
  let command = login_executable(self.settings.command, @env.get("PATH"))
  let help = login_help(command, home)
  let device_auth = help.contains("--device-auth")
  let command = "CODEX_HOME=" +
    login_shell_quote(home.to_string()) +
    " " +
    login_shell_quote(command) +
    " login" +
    (if device_auth { " --device-auth" } else { "" })
  (command, device_auth)
}
