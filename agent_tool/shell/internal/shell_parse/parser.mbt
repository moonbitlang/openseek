///|
/// Conservatively parse a shell command for policy decisions.
///
/// The parser only accepts a subset where argv can be known statically. It is a
/// parser for agent policy, not a shell interpreter. Commands using expansion,
/// command substitution, subshells, command groups, heredocs, or glob expansion
/// return `TooComplex`.
pub fn parse_for_policy(command : String) -> ParseResult {
  match lex(command) {
    LexOk(tokens) => parse_tokens(tokens)
    LexTooComplex(reason) => TooComplex(reason)
    LexSyntaxError(message) => SyntaxError(message)
  }
}

///|
fn parse_tokens(tokens : Array[Token]) -> ParseResult {
  let commands : Array[SimpleCommand] = []
  let mut env : Array[EnvAssignment] = []
  let mut argv : Array[String] = []
  let mut redirects : Array[Redirect] = []
  let mut saw_part = false
  let mut pending_separator : String? = None
  let mut separator_before : String? = None
  let mut index = 0
  while index < tokens.length() {
    match tokens[index] {
      Word(word, meta) => {
        pending_separator = None
        if !meta.has_quote_or_escape &&
          is_fd_word(word) &&
          index + 1 < tokens.length() {
          match tokens[index + 1] {
            Op(next_op, true) if is_fd_redirect_op(next_op) => {
              let op = "\{word}\{next_op}"
              match parse_redirect_target(tokens, index + 2) {
                Some((target, next_index)) => {
                  redirects.push({ op, target, })
                  saw_part = true
                  index = next_index
                  continue
                }
                None =>
                  return SyntaxError("redirection \{op} requires a target")
              }
            }
            _ => ()
          }
        }
        if argv.length() == 0 && is_env_assignment_word(word) {
          if meta.quote_or_escape_before_equals {
            return TooComplex(
              "quoted environment assignment name is not supported",
            )
          }
          match split_env_assignment(word) {
            Some(assignment) => {
              if meta.has_assignment_tilde_expansion {
                return TooComplex(
                  "tilde expansion in environment assignment is not supported",
                )
              }
              env.push(assignment)
            }
            None => argv.push(word)
          }
        } else {
          if argv.length() == 0 && is_too_complex_command_word(word) {
            return TooComplex("shell control command is not supported: \{word}")
          }
          argv.push(word)
        }
        saw_part = true
        index += 1
      }
      Op(op, _) if is_separator(op) => {
        if !saw_part {
          return SyntaxError("operator \{op} has no preceding command")
        }
        if too_complex_shell_control_word(argv) is Some(word) {
          return TooComplex("shell control command is not supported: \{word}")
        }
        push_command(commands, env, argv, redirects, separator_before)
        env = []
        argv = []
        redirects = []
        saw_part = false
        pending_separator = Some(op)
        separator_before = Some(op)
        index += 1
      }
      Op(op, _) if is_redirect_op(op) => {
        pending_separator = None
        match parse_redirect_target(tokens, index + 1) {
          Some((target, next_index)) => {
            redirects.push({ op, target, })
            saw_part = true
            index = next_index
          }
          None => return SyntaxError("redirection \{op} requires a target")
        }
      }
      Op(op, _) => return TooComplex("unsupported shell operator: \{op}")
    }
  }
  if !saw_part {
    match pending_separator {
      Some(";") | None => ()
      Some(op) => return SyntaxError("operator \{op} has no following command")
    }
  } else {
    if too_complex_shell_control_word(argv) is Some(word) {
      return TooComplex("shell control command is not supported: \{word}")
    }
    push_command(commands, env, argv, redirects, separator_before)
  }
  Simple(commands)
}

///|
fn parse_redirect_target(tokens : Array[Token], index : Int) -> (String, Int)? {
  if index >= tokens.length() {
    None
  } else {
    match tokens[index] {
      Word(target, _) => Some((target, index + 1))
      Op(_, _) => None
    }
  }
}

///|
fn push_command(
  commands : Array[SimpleCommand],
  env : Array[EnvAssignment],
  argv : Array[String],
  redirects : Array[Redirect],
  separator_before : String?,
) -> Unit {
  commands.push({
    argv,
    env,
    redirects,
    separator_before,
    source: render_source(env, argv, redirects),
  })
}

///|
fn render_source(
  env : Array[EnvAssignment],
  argv : Array[String],
  redirects : Array[Redirect],
) -> String {
  [
    ..env.map(assignment => "\{assignment.name}=\{assignment.value}"),
    ..argv,
    ..redirects.map(redirect => "\{redirect.op} \{redirect.target}"),
  ].join(" ")
}

///|
fn is_separator(op : String) -> Bool {
  op == "&&" || op == "||" || op == ";" || op == "|"
}

///|
fn is_redirect_op(op : String) -> Bool {
  op is (">" | ">|" | ">>" | "<>" | "<" | "&>" | "&>>" | ">&" | "<&")
}

///|
fn is_fd_redirect_op(op : String) -> Bool {
  op is (">" | ">|" | ">>" | ">&" | "<>" | "<" | "<&")
}

///|
fn is_fd_word(word : String) -> Bool {
  lexmatch word {
    re"^[0-9]+$" => true
    _ => false
  }
}

///|
fn split_env_assignment(word : String) -> EnvAssignment? {
  guard [..word.split("=")] is [first, .. values] && !values.is_empty() else {
    return None
  }
  let name = first.to_owned()
  if !is_valid_env_name(name) {
    return None
  }
  Some({ name, value: values.join("="), })
}

///|
fn is_env_assignment_word(word : String) -> Bool {
  split_env_assignment(word) is Some(_)
}

///|
fn is_valid_env_name(name : String) -> Bool {
  lexmatch name {
    re"^[A-Za-z_][A-Za-z0-9_]*$" => true
    _ => false
  }
}

///|
fn is_too_complex_command_word(word : String) -> Bool {
  match word {
    "!"
    | "{"
    | "}"
    | "."
    | "case"
    | "coproc"
    | "do"
    | "done"
    | "elif"
    | "else"
    | "esac"
    | "eval"
    | "exit"
    | "exec"
    | "fi"
    | "for"
    | "function"
    | "if"
    | "in"
    | "select"
    | "source"
    | "then"
    | "time"
    | "trap"
    | "until"
    | "while" => true
    _ => false
  }
}

///|
fn too_complex_shell_control_word(argv : Array[String]) -> String? {
  match effective_shell_control_word_index(argv) {
    Some(index) if is_too_complex_command_word(argv[index]) => Some(argv[index])
    _ => None
  }
}

///|
fn effective_shell_control_word_index(argv : Array[String]) -> Int? {
  // Unlike `effective_command_index`, a wrapper with nothing to run is no
  // control word at all rather than the wrapper itself — hence `None` for both
  // `builtin` and `builtin --`, which the `_ ..` arms below fall through to.
  match argv {
    ["command", ..] => command_payload_index(argv)
    ["builtin", "--", _, ..] => Some(2)
    ["builtin", "--"] | ["builtin"] | [] => None
    ["builtin", _, ..] => Some(1)
    _ => Some(0)
  }
}

///|
fn command_payload_index(argv : Array[String]) -> Int? {
  let mut index = 1
  while index < argv.length() {
    match argv[index] {
      "--" =>
        if index + 1 < argv.length() {
          return Some(index + 1)
        } else {
          return None
        }
      "-p" => index += 1
      "-v" | "-V" => return None
      arg if arg.has_prefix("-") => return None
      _ => return Some(index)
    }
  }
  None
}
