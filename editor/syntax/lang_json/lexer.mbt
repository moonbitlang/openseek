///|
/// JSON (and JSONC comments) behind the `syntax.LineTokenizer` contract:
/// the trivial two-state machine. The empty state is normal; mode `b'c'` means
/// inside a `/* ... */` block comment, the one construct that carries across
/// lines.
struct JsonTokenizer {
  _unit : Unit
}

///|
/// JSON's two immutable carried states, allocated once and compared by value.
let json_normal_state : @syntax.TokenizerState = TokenizerState()

///|
let json_comment_state : @syntax.TokenizerState = json_normal_state.push_mode(
  b'c',
)

///|
/// Creates the JSON/JSONC tokenizer.
pub fn JsonTokenizer::JsonTokenizer() -> JsonTokenizer {
  { _unit: () }
}

///|
/// Initial JSON lexer state outside block comments.
pub impl @syntax.LineTokenizer for JsonTokenizer with fn initial_state(_self) {
  json_normal_state
}

///|
/// Tokenizes one JSON/JSONC line while carrying block-comment state.
pub impl @syntax.LineTokenizer for JsonTokenizer with fn tokenize_line(
  _self,
  line_text,
  state,
) {
  let tokens : Array[@syntax.LineToken] = []
  let in_comment = for at = 0, view = line_text[:], in_comment = state ==
                         json_comment_state; view.length() > 0; {
    let (op, rest) = if in_comment {
      comment_step(view)
    } else {
      normal_step(view)
    }
    let consumed = view.length() - rest.length()
    let next_in_comment = match op {
      EnterComment => true
      LeaveComment => false
      _ => in_comment
    }
    match op {
      Blank => ()
      Emit(tag) => tokens.push({ start: at, end: at + consumed, tag })
      EnterComment | LeaveComment =>
        tokens.push({ start: at, end: at + consumed, tag: Comment })
    }
    continue at + consumed, rest, next_in_comment
  } nobreak {
    in_comment
  }
  (tokens, if in_comment { json_comment_state } else { json_normal_state })
}

///|
priv enum StepOp {
  Blank
  Emit(@syntax.HighlightTag)
  EnterComment
  LeaveComment
}

///|
fn normal_step(view : StringView) -> (StepOp, StringView) {
  lexmatch view with longest {
    (re"^[ \t]+", after=rest) => (Blank, rest)
    (re"^//.*", after=rest) => (Emit(Comment), rest)
    (re"^/\*", after=rest) => (EnterComment, rest)
    // A terminated string is a property name when the next significant
    // character is a colon — the Monarch lookahead idiom done by peeking
    // the rest of the line instead.
    (re"^\"(?:\\.|[^\"\\])*\"", after=rest) =>
      (Emit(if colon_follows(rest) { Attribute } else { String }), rest)
    (re"^\"(?:\\.|[^\"\\])*", after=rest) => (Emit(String), rest)
    (re"^-?[0-9]+(?:\.[0-9]+)?(?:[eE][+\-]?[0-9]+)?", after=rest) =>
      (Emit(Number), rest)
    (re"^[a-zA-Z_][a-zA-Z0-9_]*" as word, after=rest) =>
      (
        Emit(
          match word {
            "true" | "false" | "null" => Constant
            _ => Invalid
          },
        ),
        rest,
      )
    (re"^[{}\[\],:]", after=rest) => (Emit(Delimiter), rest)
    (re"^.", after=rest) => (Emit(Punctuation), rest)
    // Unreachable while `.` covers the full charset (it includes lone
    // surrogates); consumes the rest defensively so the driver loop can
    // never stall on zero progress.
    _ => (Blank, ""[:])
  }
}

///|
fn comment_step(view : StringView) -> (StepOp, StringView) {
  lexmatch view with longest {
    (re"^\*/", after=rest) => (LeaveComment, rest)
    (re"^[^*]+", after=rest) => (Emit(Comment), rest)
    (re"^\*", after=rest) => (Emit(Comment), rest)
    _ => (Blank, ""[:])
  }
}

///|
fn colon_follows(rest : StringView) -> Bool {
  for unit in rest.code_units() {
    if unit is (' ' | '\t') {
      continue
    }
    return unit == ':'
  }
  false
}
