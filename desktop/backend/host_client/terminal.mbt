///|
/// A separate interactive SSH session. Only sshd allocates the remote PTY;
/// the app-server transport and its lifetime are not involved.
pub fn terminal_args(
  destination~ : String,
  cwd~ : String,
  command? : String,
) -> Array[String] raise {
  guard !destination.is_blank() &&
    !destination.has_prefix("-") &&
    !destination.contains("\u0000") &&
    !destination.contains("\n") &&
    !destination.contains("\r") else {
    raise HostClientError("Invalid SSH terminal destination")
  }
  guard cwd.has_prefix("/") && !cwd.contains("\u0000") else {
    raise HostClientError("SSH terminal requires an absolute remote directory")
  }
  let execute = match command {
    None => "exec \"$SHELL\" -i"
    Some(command) => {
      guard !command.is_blank() && !command.contains("\u0000") else {
        raise HostClientError(
          "SSH terminal command must not be blank or contain NUL",
        )
      }
      "exec \"$SHELL\" -c " + quote(command)
    }
  }
  [
    "-tt",
    "-o",
    "BatchMode=yes",
    "-o",
    "ControlMaster=no",
    "-o",
    "ControlPath=none",
    "-o",
    "ClearAllForwardings=yes",
    "-o",
    "EscapeChar=none",
    "-o",
    "ConnectTimeout=10",
    "-o",
    "ServerAliveInterval=15",
    "-o",
    "ServerAliveCountMax=4",
    "-o",
    "ForwardAgent=no",
    "--",
    destination,
    @ssh_shell.command(
      "cd " +
      quote(cwd) +
      " || exit; export TERM=xterm-256color COLORTERM=truecolor; " +
      execute,
    ),
  ]
}
