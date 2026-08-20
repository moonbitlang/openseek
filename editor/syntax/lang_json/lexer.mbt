///|
/// Strict JSON lexer behind the `syntax.LineTokenizer` contract.
/// JSON has no cross-line lexical constructs, so every line starts and finishes
/// in the canonical empty tokenizer state.
struct JsonTokenizer {
  _unit : Unit
}

///|
/// Shared immutable normal state for JSON files.
let json_normal_state : @syntax.TokenizerState = TokenizerState()

///|
/// Creates the strict JSON tokenizer.
pub fn JsonTokenizer::JsonTokenizer() -> JsonTokenizer {
  { _unit: () }
}

///|
/// Initial JSON lexer state.
pub impl @syntax.LineTokenizer for JsonTokenizer with fn initial_state(_self) {
  json_normal_state
}

///|
/// Tokenizes one strict JSON line.
pub impl @syntax.LineTokenizer for JsonTokenizer with fn tokenize_line(
  _self,
  line_text,
  _state,
) {
  let tokens : Array[@syntax.LineToken] = []
  for at = 0, view = line_text {
    lexmatch view with longest {
      re"^$" => break
      (re"^[ \t]+" as s, after=rest) => continue at + s.length(), rest
      (re"^\"(?:\\.|[^\"\\])*\"" as s, after=rest) => {
        let end = at + s.length()
        tokens.push({ start: at, end, tag: String })
        continue end, rest
      }
      (re"^\"(?:\\.|[^\"\\])*" as s, after=rest) => {
        let end = at + s.length()
        tokens.push({ start: at, end, tag: String })
        continue end, rest
      }
      (re"^-?[0-9]+(?:\.[0-9]+)?(?:[eE][+\-]?[0-9]+)?" as s, after=rest) => {
        let end = at + s.length()
        tokens.push({ start: at, end, tag: Number })
        continue end, rest
      }
      (re"^(?:true|false|null)" as s, after=rest) => {
        let end = at + s.length()
        tokens.push({ start: at, end, tag: Constant })
        continue end, rest
      }
      (re"^[a-zA-Z_][a-zA-Z0-9_]*" as s, after=rest) => {
        let end = at + s.length()
        tokens.push({ start: at, end, tag: Invalid })
        continue end, rest
      }
      (re"^[{}\[\],:]", after=rest) => {
        let end = at + 1
        tokens.push({ start: at, end, tag: Delimiter })
        continue end, rest
      }
      (re"^." as c, after=rest) => {
        let end = at + c.utf16_len()
        tokens.push({ start: at, end, tag: Punctuation })
        continue end, rest
      }
    }
  }
  (tokens, json_normal_state)
}

///|
pub extend JsonTokenizer with @syntax.LineTokenizer::{
  initial_state,
  tokenize_line,
}
