///|
/// Hand-written MoonBit lexer behind the `syntax.LineTokenizer` contract.
/// Monarch's state-machine structure, but every rule set is a `lexmatch`
/// compiled to a tagged DFA at build time — no runtime regexes, no
/// grammar data.
///
/// The carried `TokenizerState` is empty because no MoonBit string construct
/// survives a line end. A per-line persistent list records lexical modes,
/// top first: normal expression code, string text, `$|` multiline-string text,
/// string interpolation, and nested interpolation braces.
/// No MoonBit string construct survives a line end, so every line both
/// enters and leaves in normal mode; the mode list only drives within-line lexing.
struct MoonBitTokenizer {
  _unit : Unit
}

///|
/// Lexical modes used only by one `tokenize_line` invocation.
priv enum MoonBitMode {
  Normal
  StringText
  MultilineStringText
  Interpolation
  InterpolationBrace
}

///|
/// Classifies one identifier lexeme by spelling only. This is lexical
/// classification: it does not inspect surrounding tokens or source text.
fn classify_word(word : StringView) -> @syntax.HighlightTag {
  match word {
    "fn"
    | "let"
    | "mut"
    | "var"
    | "const"
    | "pub"
    | "priv"
    | "struct"
    | "enum"
    | "extend"
    | "trait"
    | "impl"
    | "with"
    | "derive"
    | "type"
    | "typealias"
    | "traitalias"
    | "fnalias"
    | "suberror"
    | "raise"
    | "try"
    | "catch"
    | "noraise"
    | "defer"
    | "errdefer"
    | "async"
    | "test"
    | "if"
    | "else"
    | "match"
    | "guard"
    | "while"
    | "for"
    | "in"
    | "loop"
    | "break"
    | "continue"
    | "return"
    | "as"
    | "is"
    | "not"
    | "using"
    | "import"
    | "extern"
    | "declare"
    | "where"
    | "nobreak" => Keyword
    "true" | "false" => Constant
    _ => if @syntax.is_capitalized(word) { Type } else { Identifier }
  }
}

///|
/// Shared immutable normal state; MoonBit's lexer always returns to it at the
/// end of a line.
let moonbit_normal_state : @syntax.TokenizerState = TokenizerState()

///|
/// Creates the MoonBit tokenizer.
pub fn MoonBitTokenizer::MoonBitTokenizer() -> MoonBitTokenizer {
  { _unit: (), }
}

///|
/// Initial MoonBit lexer state.
pub impl @syntax.LineTokenizer for MoonBitTokenizer with fn initial_state(_) {
  moonbit_normal_state
}

///|
/// Tokenizes one MoonBit source line and resets to normal mode at line end.
pub impl @syntax.LineTokenizer for MoonBitTokenizer with fn tokenize_line(
  _,
  line_text,
  _state,
) {
  let tokens : Array[@syntax.LineToken] = []
  for at = 0, view = line_text, modes = @list.singleton(Normal) {
    match modes {
      More(StringText, tail~) =>
        lexmatch view with longest {
          re"^$" => break
          (re"^\\u[{][0-9a-fA-F]+[}]" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, StringEscape)
            continue end, rest, modes
          }
          (re"^\\[{]", after=rest) => {
            let end = at + 2
            @syntax.push_token(tokens, at, end, StringEscape)
            continue end, rest, modes.prepend(Interpolation)
          }
          (re"^\\." as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, StringEscape)
            continue end, rest, modes
          }
          (re"^\"", after=rest) => {
            let end = at + 1
            @syntax.push_token(tokens, at, end, String)
            continue end, rest, tail
          }
          (re"^[^\"\\]+" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, String)
            continue end, rest, modes
          }
          (re"^." as c, after=rest) => {
            let end = at + c.utf16_len()
            @syntax.push_token(tokens, at, end, String)
            continue end, rest, modes
          }
        }
      More(MultilineStringText, tail=_) =>
        lexmatch view with longest {
          re"^$" => break
          (re"^\\[{]", after=rest) => {
            let end = at + 2
            @syntax.push_token(tokens, at, end, StringEscape)
            continue end, rest, modes.prepend(Interpolation)
          }
          (re"^\\." as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, StringEscape)
            continue end, rest, modes
          }
          (re"^[^\\]+" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, String)
            continue end, rest, modes
          }
          (re"^." as c, after=rest) => {
            let end = at + c.utf16_len()
            @syntax.push_token(tokens, at, end, String)
            continue end, rest, modes
          }
        }
      More(top, tail~) =>
        lexmatch view with longest {
          re"^$" => break
          (re"^[ \t]+" as s, after=rest) =>
            continue at + s.length(), rest, modes
          (re"^///.*" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, CommentDoc)
            continue end, rest, modes
          }
          (re"^//.*" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, Comment)
            continue end, rest, modes
          }
          (re"^#\|.*" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, String)
            continue end, rest, modes
          }
          (re"^\$\|", after=rest) => {
            let end = at + 2
            @syntax.push_token(tokens, at, end, String)
            continue end, rest, modes.prepend(MultilineStringText)
          }
          (re"^#[a-zA-Z_][a-zA-Z0-9_.]*" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, Attribute)
            continue end, rest, modes
          }
          (re"^b?\"" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, String)
            continue end, rest, modes.prepend(StringText)
          }
          (re"^b?'(?:\\.|[^'\\])+'" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, String)
            continue end, rest, modes
          }
          (re"^0[xX][0-9a-fA-F_]+[UL]*" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, Number)
            continue end, rest, modes
          }
          (re"^0[oO][0-7_]+[UL]*" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, Number)
            continue end, rest, modes
          }
          (re"^0[bB][01_]+[UL]*" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, Number)
            continue end, rest, modes
          }
          (
            re"^[0-9][0-9_]*(?:\.[0-9_]+)?(?:[eE][+\-]?[0-9]+)?[ULN]*" as s,
            after=rest,
          ) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, Number)
            continue end, rest, modes
          }
          (re"^@[a-zA-Z_][a-zA-Z0-9_/]*" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, Type)
            continue end, rest, modes
          }
          (re"^[a-zA-Z_][a-zA-Z0-9_]*" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, classify_word(s))
            continue end, rest, modes
          }
          (re"^[+\-*/%=<>!&^~?\|]+" as s, after=rest) => {
            let end = at + s.length()
            @syntax.push_token(tokens, at, end, Operator)
            continue end, rest, modes
          }
          (re"^[()\[\],;:.]", after=rest) => {
            let end = at + 1
            @syntax.push_token(tokens, at, end, Delimiter)
            continue end, rest, modes
          }
          (re"^[{]", after=rest) => {
            let end = at + 1
            @syntax.push_token(tokens, at, end, Delimiter)
            if top is (Interpolation | InterpolationBrace) {
              continue end, rest, modes.prepend(InterpolationBrace)
            }
            continue end, rest, modes
          }
          (re"^[}]", after=rest) => {
            let end = at + 1
            if top is Interpolation {
              @syntax.push_token(tokens, at, end, StringEscape)
              continue end, rest, tail
            } else {
              @syntax.push_token(tokens, at, end, Delimiter)
              if top is InterpolationBrace {
                continue end, rest, tail
              }
              continue end, rest, modes
            }
          }
          (re"^." as c, after=rest) => {
            let end = at + c.utf16_len()
            @syntax.push_token(tokens, at, end, Punctuation)
            continue end, rest, modes
          }
        }
      Empty => break
    }
  }
  (tokens, moonbit_normal_state)
}

///|
pub extend MoonBitTokenizer with @syntax.LineTokenizer::{
  initial_state,
  tokenize_line,
}
