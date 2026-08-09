///|
/// JSON (and JSONC comments) behind the `syntax.LineTokenizer` contract:
/// the trivial two-state machine. A block comment is the one construct that
/// carries across lines.
struct JsonTokenizer {
  _unit : Unit
}

///|
/// Language-owned lexer state. Its serialized `TokenizerState` representation
/// is confined to `decode_state` and `encode_state` below.
priv enum JsonState {
  Normal
  BlockComment
}

///|
/// Creates the JSON/JSONC tokenizer.
pub fn JsonTokenizer::JsonTokenizer() -> JsonTokenizer {
  { _unit: () }
}

///|
/// Initial JSON lexer state outside block comments.
pub impl @syntax.LineTokenizer for JsonTokenizer with fn initial_state(_self) {
  encode_state(Normal)
}

///|
/// Tokenizes one JSON/JSONC line while carrying block-comment state.
pub impl @syntax.LineTokenizer for JsonTokenizer with fn tokenize_line(
  _self,
  line_text,
  state,
) {
  let tokens : Array[@syntax.LineToken] = []
  let start_state = decode_state(state)
  let end_state = for at = 0, view = line_text[:], lexer_state = start_state; view.length() >
                     0; {
    let (op, rest) = match lexer_state {
      Normal => normal_step(view)
      BlockComment => comment_step(view)
    }
    let consumed = view.length() - rest.length()
    let next_state = match op {
      EnterComment => BlockComment
      LeaveComment => Normal
      _ => lexer_state
    }
    match op {
      Blank => ()
      Emit(tag) => tokens.push({ start: at, end: at + consumed, tag })
      EnterComment | LeaveComment =>
        tokens.push({ start: at, end: at + consumed, tag: Comment })
    }
    continue at + consumed, rest, next_state
  } nobreak {
    lexer_state
  }
  (tokens, encode_state(end_state))
}

///|
/// Decodes the public, language-neutral state carrier. Unknown payloads retain
/// the previous fail-closed behavior and start JSON tokenization in normal
/// mode.
fn decode_state(state : @syntax.TokenizerState) -> JsonState {
  if state == TokenizerState("c") {
    BlockComment
  } else {
    Normal
  }
}

///|
/// Encodes JSON's private state for the language-neutral tokenizer contract.
fn encode_state(state : JsonState) -> @syntax.TokenizerState {
  match state {
    Normal => TokenizerState("n")
    BlockComment => TokenizerState("c")
  }
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
  lexscan view with longest {
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
  lexscan view with longest {
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
