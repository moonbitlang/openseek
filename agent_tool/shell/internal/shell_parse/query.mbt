///|
/// Return the effective command name for this simple command.
///
/// This strips leading environment assignments represented in `env`, and also
/// recognizes common `env` wrappers such as `env NAME=value command ...` and
/// `env -u NAME command ...`. More complex option forms remain `env`.
pub fn SimpleCommand::command_name(self : SimpleCommand) -> String? {
  match self.command_index() {
    Some(index) if index < self.argv.length() => Some(self.argv[index])
    _ => None
  }
}

///|
/// Return the index in `argv` of this command's effective command word.
///
/// This is the index-aware counterpart of `command_name()`, so consumers that
/// need to continue scanning command flags do not have to duplicate wrapper
/// grammar.
pub fn SimpleCommand::command_index(self : SimpleCommand) -> Int? {
  effective_command_index(self.argv)
}

///|
/// True when the parsed result contains a simple command with the requested
/// effective command name.
pub fn contains_command(result : ParseResult, name : String) -> Bool {
  match result {
    Simple(commands) =>
      commands.any(command => {
        command.command_name() is Some(cmd_name) && cmd_name == name
      })
    _ => false
  }
}

///|
fn effective_command_index(argv : Array[String]) -> Int? {
  // Each arm is the argv shape it handles. The `builtin --` arm has to precede
  // the general `builtin` one: `--` with nothing behind it is not an
  // end-of-options marker for a command, it leaves the wrapper as the command.
  match argv {
    [] => None
    ["env", ..] => env_wrapped_command_index(argv)
    ["command", ..] => command_wrapped_command_index(argv)
    ["builtin", "--", _, ..] => Some(2)
    ["builtin", "--"] => Some(0)
    ["builtin", _, ..] => Some(1)
    _ => Some(0)
  }
}

///|
fn command_wrapped_command_index(argv : Array[String]) -> Int? {
  let mut index = 1
  while index < argv.length() {
    let arg = argv[index]
    if arg == "--" {
      index += 1
      break
    }
    if arg == "-p" {
      index += 1
      continue
    }
    if arg == "-v" || arg == "-V" || arg.has_prefix("-") {
      return Some(0)
    }
    return Some(index)
  }
  if index < argv.length() {
    Some(index)
  } else {
    Some(0)
  }
}

///|
fn env_wrapped_command_index(argv : Array[String]) -> Int? {
  let mut index = 1
  let mut scanning_options = true
  while index < argv.length() {
    let arg = argv[index]
    if scanning_options && arg == "--" {
      scanning_options = false
      index += 1
      continue
    }
    if scanning_options && (arg == "-i" || arg == "-") {
      index += 1
      continue
    }
    if scanning_options && env_option_consumes_next(arg) {
      index += 2
      continue
    }
    if scanning_options &&
      (env_option_with_attached_value(arg) || env_no_arg_option(arg)) {
      index += 1
      continue
    }
    if scanning_options && arg.has_prefix("-") {
      return Some(0)
    }
    if is_env_assignment_word(arg) {
      scanning_options = false
      index += 1
      continue
    }
    return Some(index)
  }
  if index < argv.length() {
    Some(index)
  } else {
    Some(0)
  }
}

///|
fn env_option_consumes_next(arg : String) -> Bool {
  arg == "-u" || arg == "--unset"
}

///|
fn env_option_with_attached_value(arg : String) -> Bool {
  (arg.has_prefix("-u") && arg != "-u") || arg.has_prefix("--unset=")
}

///|
fn env_no_arg_option(arg : String) -> Bool {
  match arg {
    "--ignore-environment" | "-0" | "--null" | "--debug" => true
    _ => false
  }
}
