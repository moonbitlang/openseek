///|
pub(all) suberror SshCommandError {
  SshCommandError(String)
}

///|
/// Tokenize a connection command, never evaluate it as a shell program.
fn ssh_words(command : String) -> Array[String] raise {
  let words : Array[String] = []
  let mut word = ""
  let mut quote : Char? = None
  let mut escape = false
  let mut started = false
  for ch in command {
    if escape {
      word += ch.to_string()
      escape = false
      started = true
      continue
    }
    if ch == '\\' && quote != Some('\'') {
      escape = true
      continue
    }
    if quote is Some(q) {
      if ch == q {
        quote = None
      } else {
        word += ch.to_string()
      }
    } else if ch == '\'' || ch == '"' {
      quote = Some(ch)
      started = true
    } else if ch == ' ' || ch == '\t' {
      if started {
        words.push(word)
        word = ""
        started = false
      }
    } else {
      guard ch != '\n' && ch != '\r' else {
        raise SshCommandError("Enter one SSH connection command")
      }
      word += ch.to_string()
      started = true
    }
  }
  guard !escape && quote is None else {
    raise SshCommandError("Unclosed quote or escape in SSH command")
  }
  if started {
    words.push(word)
  }
  words
}

///|
/// Connection options only: remote commands, forwarding and terminal flags
/// would change the protocol's stdin/stdout ownership and are rejected.
pub fn ssh_connection_arguments(command : String) -> Array[String] raise {
  let tokens = ssh_words(command)
  guard tokens.length() >= 2 && tokens[0] == "ssh" else {
    raise SshCommandError(
      "Enter an SSH command such as ssh user@host or ssh -p 2222 host",
    )
  }
  let result : Array[String] = []
  let mut i = 1
  while i < tokens.length() - 1 {
    let option = tokens[i]
    guard ["-p", "-i", "-J", "-l", "-F"].contains(option) &&
      i + 1 < tokens.length() - 1 else {
      raise SshCommandError(
        "Supported SSH options: -p, -i, -J, -l, -F; put other connection settings in ~/.ssh/config",
      )
    }
    result.push(option)
    result.push(tokens[i + 1])
    i += 2
  }
  let destination = tokens[tokens.length() - 1]
  guard !destination.is_empty() && !destination.has_prefix("-") else {
    raise SshCommandError("Missing SSH destination")
  }
  result.push(destination)
  result
}

///|
/// Display metadata comes from the same tokenizer used for execution. A config
/// alias remains an alias: resolving ~/.ssh/config belongs to the native host.
pub fn SshProfile::display_label(self : SshProfile) -> String {
  if self.display_name is Some(name) && !name.trim().is_empty() {
    return name.trim().to_owned()
  }
  let options = ssh_connection_arguments(self.command) catch {
    _ => return "SSH host"
  }
  let destination = options[options.length() - 1]
  destination.split("@").last().unwrap_or(destination).to_owned()
}

///|
pub fn SshProfile::connection_label(self : SshProfile) -> String {
  let options = ssh_connection_arguments(self.command) catch {
    _ => return "Invalid SSH command"
  }
  let destination = options[options.length() - 1]
  let mut user : String? = None
  let mut port : String? = None
  for i = 0; i < options.length() - 1; i = i + 2 {
    match options[i] {
      "-l" => user = Some(options[i + 1])
      "-p" => port = Some(options[i + 1])
      _ => ()
    }
  }
  let address = if !destination.contains("@") && user is Some(user) {
    user + "@" + destination
  } else {
    destination
  }
  match port {
    Some(port) => address + " · Port " + port
    None => address
  }
}
