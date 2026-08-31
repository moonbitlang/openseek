///|
/// Result of conservatively analyzing one shell command string.
///
/// `Simple` means the parser produced a trustworthy flat list of top-level
/// simple commands. `TooComplex` means the command uses shell behavior whose
/// runtime argv cannot be known statically. `SyntaxError` means the command is
/// malformed even within the supported subset.
pub(all) enum ParseResult {
  Simple(Array[SimpleCommand])
  TooComplex(String)
  SyntaxError(String)
} derive(Debug, Eq)

///|
/// One statically analyzable shell simple command.
///
/// `argv` contains the command name and arguments after shell quoting and
/// backslash escaping are resolved. `env` contains leading `NAME=value`
/// assignments that apply to this command. `redirects` contains basic
/// redirections attached to the command. `separator_before` records the
/// top-level operator before this command (`&&`, `||`, `;`, or `|`), if any.
/// `source` is a compact normalized rendering for diagnostics; it is not
/// guaranteed to byte-match the input.
pub struct SimpleCommand {
  argv : Array[String]
  env : Array[EnvAssignment]
  redirects : Array[Redirect]
  separator_before : String?
  priv source : String
} derive(Debug, Eq)

///|
/// Leading environment assignment such as `FOO=bar` before a command word.
pub(all) struct EnvAssignment {
  name : String
  value : String
} derive(Debug, Eq)

///|
/// Basic shell redirection parsed from a simple command.
///
/// The parser only returns `Simple` for redirections whose target is a static
/// word. Unsupported redirection forms are classified as `TooComplex`.
pub(all) struct Redirect {
  op : String
  target : String
} derive(Debug, Eq)

///|
/// Internal lexer token used by the shell policy parser.
priv enum Token {
  Word(String, WordMeta)
  Op(String, Bool)
}

///|
priv struct WordMeta {
  has_quote_or_escape : Bool
  quote_or_escape_before_equals : Bool
  has_assignment_tilde_expansion : Bool
}

///|
priv enum LexResult {
  LexOk(Array[Token])
  LexTooComplex(String)
  LexSyntaxError(String)
}

///|
priv enum LexState {
  Plain
  SingleQuoted
  DoubleQuoted
  Comment
}

///|
pub extend EnvAssignment with Debug::{to_repr}

///|
pub extend EnvAssignment with Eq::{equal, not_equal}

///|
pub extend ParseResult with Debug::{to_repr}

///|
pub extend ParseResult with Eq::{equal, not_equal}

///|
pub extend Redirect with Debug::{to_repr}

///|
pub extend Redirect with Eq::{equal, not_equal}

///|
pub extend SimpleCommand with Debug::{to_repr}

///|
pub extend SimpleCommand with Eq::{equal, not_equal}
