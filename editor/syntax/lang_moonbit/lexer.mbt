///|
/// Hand-written MoonBit lexer behind the `syntax.LineTokenizer` contract.
/// Monarch's state-machine structure, but every rule set is a `lexmatch`
/// compiled to a tagged DFA at build time — no runtime regexes, no
/// grammar data.
///
/// The carried `TokenizerState` is empty because no MoonBit string construct
/// survives a line end. A mutable per-line scratch stack uses one byte per
/// mode, bottom first:
///   b'n' normal expression code (always the bottom)
///   b's' inside a `"` string
///   b'm' inside a `$|` multiline-string line
///   b'i' inside a `\{ ... }` string interpolation
///   b'b' inside a plain `{ ... }` brace pair nested in an interpolation
/// No MoonBit string construct survives a line end, so every line both
/// enters and leaves at b'n'; the stack only drives the within-line modes.
struct MoonBitTokenizer {
  _unit : Unit
}

///|
/// Shared immutable base stack; MoonBit's lexer always returns to it at the
/// end of a line.
let moonbit_normal_state : @syntax.TokenizerState = TokenizerState()

///|
/// Creates the MoonBit tokenizer.
pub fn MoonBitTokenizer::MoonBitTokenizer() -> MoonBitTokenizer {
  { _unit: () }
}

///|
/// Initial MoonBit lexer mode stack.
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
  let stack : Array[Byte] = [b'n']
  let tokens : Array[@syntax.LineToken] = []
  for at = 0, view = line_text[:]; view.length() > 0; {
    let top = stack[stack.length() - 1]
    let (op, rest) = match top {
      b's' => string_step(view)
      b'm' => dollar_step(view)
      _ => normal_step(view, top)
    }
    let consumed = view.length() - rest.length()
    match op {
      Blank => ()
      Emit(tag) => @syntax.push_token(tokens, at, at + consumed, tag)
      Push(tag, mode) => {
        @syntax.push_token(tokens, at, at + consumed, tag)
        stack.push(mode)
      }
      Pop(tag) => {
        @syntax.push_token(tokens, at, at + consumed, tag)
        if stack.length() > 1 {
          ignore(stack.pop())
        }
      }
    }
    continue at + consumed, rest
  }
  (tokens, moonbit_normal_state)
}

///|
/// What one lexeme does to the token stream and the mode stack.
priv enum StepOp {
  Blank
  Emit(@syntax.HighlightTag)
  Push(@syntax.HighlightTag, Byte)
  Pop(@syntax.HighlightTag)
}

///|
/// Expression code: the rules for modes b'n', b'i', and b'b'. The brace
/// arms need the current mode because `}` closes an interpolation in b'i'
/// but is a plain delimiter elsewhere.
fn normal_step(view : StringView, top : Byte) -> (StepOp, StringView) {
  lexmatch view with longest {
    (re"^[ \t]+", after=rest) => (Blank, rest)
    (re"^///.*", after=rest) => (Emit(CommentDoc), rest)
    (re"^//.*", after=rest) => (Emit(Comment), rest)
    (re"^#\|.*", after=rest) => (Emit(String), rest)
    (re"^\$\|", after=rest) => (Push(String, b'm'), rest)
    (re"^#[a-zA-Z_][a-zA-Z0-9_.]*", after=rest) => (Emit(Attribute), rest)
    (re"^b?\"", after=rest) => (Push(String, b's'), rest)
    (re"^b?'(?:\\.|[^'\\])+'", after=rest) => (Emit(String), rest)
    (re"^0[xX][0-9a-fA-F_]+[UL]*", after=rest) => (Emit(Number), rest)
    (re"^0[oO][0-7_]+[UL]*", after=rest) => (Emit(Number), rest)
    (re"^0[bB][01_]+[UL]*", after=rest) => (Emit(Number), rest)
    (re"^[0-9][0-9_]*(?:\.[0-9_]+)?(?:[eE][+\-]?[0-9]+)?[ULN]*", after=rest) =>
      (Emit(Number), rest)
    (re"^@[a-zA-Z_][a-zA-Z0-9_/]*", after=rest) => (Emit(Type), rest)
    (re"^[a-zA-Z_][a-zA-Z0-9_]*" as word, after=rest) =>
      (Emit(classify_word(word)), rest)
    (re"^[+\-*/%=<>!&^~?\|]+", after=rest) => (Emit(Operator), rest)
    (re"^[()\[\],;:.]", after=rest) => (Emit(Delimiter), rest)
    (re"^[{]", after=rest) =>
      if top == b'i' || top == b'b' {
        (Push(Delimiter, b'b'), rest)
      } else {
        (Emit(Delimiter), rest)
      }
    (re"^[}]", after=rest) =>
      match top {
        b'i' => (Pop(StringEscape), rest)
        b'b' => (Pop(Delimiter), rest)
        _ => (Emit(Delimiter), rest)
      }
    (re"^.", after=rest) => (Emit(Punctuation), rest)
    // Unreachable while `.` covers the full charset (it includes lone
    // surrogates); consumes the rest defensively so the driver loop can
    // never stall on zero progress.
    _ => (Blank, ""[:])
  }
}

///|
/// Inside a `"` string: chunks, escapes, `\{` opening an interpolation,
/// and the closing quote. An unterminated string falls to the `.` arm
/// one character at a time and the line-end reset recovers the mode.
fn string_step(view : StringView) -> (StepOp, StringView) {
  lexmatch view with longest {
    (re"^\\u[{][0-9a-fA-F]+[}]", after=rest) => (Emit(StringEscape), rest)
    (re"^\\[{]", after=rest) => (Push(StringEscape, b'i'), rest)
    (re"^\\.", after=rest) => (Emit(StringEscape), rest)
    (re"^\"", after=rest) => (Pop(String), rest)
    (re"^[^\"\\]+", after=rest) => (Emit(String), rest)
    (re"^.", after=rest) => (Emit(String), rest)
    _ => (Blank, ""[:])
  }
}

///|
/// The rest of a `$|` multiline-string line: literal text plus the same
/// escape and interpolation forms as `"` strings, terminated only by the
/// line end.
fn dollar_step(view : StringView) -> (StepOp, StringView) {
  lexmatch view with longest {
    (re"^\\[{]", after=rest) => (Push(StringEscape, b'i'), rest)
    (re"^\\.", after=rest) => (Emit(StringEscape), rest)
    (re"^[^\\]+", after=rest) => (Emit(String), rest)
    (re"^.", after=rest) => (Emit(String), rest)
    _ => (Blank, ""[:])
  }
}

///|
/// The Monarch `@keywords` idiom: the identifier rule binds the word and
/// classification is a word-set lookup, so no `\b` boundary is needed.
fn classify_word(word : StringView) -> @syntax.HighlightTag {
  match word {
    "fn"
    | "let"
    | "mut"
    | "const"
    | "pub"
    | "priv"
    | "struct"
    | "enum"
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
    "self" => Variable
    _ => if @syntax.is_capitalized(word) { Type } else { Identifier }
  }
}
