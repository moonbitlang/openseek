///|
/// A small stateless `LineTokenizer` implementation for examples and tests.
/// It is not installed automatically when a language has no registered
/// tokenizer.
struct PlainTokenizer {
  _unit : Unit
}

///|
/// Creates the example tokenizer.
pub fn PlainTokenizer::PlainTokenizer() -> PlainTokenizer {
  { _unit: () }
}

///|
/// Entry state for the stateless example tokenizer.
pub impl @syntax.LineTokenizer for PlainTokenizer with fn initial_state(_self) {
  TokenizerState()
}

///|
/// Tokenizes one line with simple MoonBit-ish lexical classes.
pub impl @syntax.LineTokenizer for PlainTokenizer with fn tokenize_line(
  _self,
  line_text,
  state,
) {
  let tokens : Array[@syntax.LineToken] = []
  for offset = 0; offset < line_text.length(); {
    let unit = line_text[offset].to_int()
    if is_space(unit) {
      continue offset + 1
    } else if unit == '/' &&
      offset + 1 < line_text.length() &&
      line_text[offset + 1].to_int() == '/' {
      tokens.push({ start: offset, end: line_text.length(), tag: Comment })
      continue line_text.length()
    } else if unit == '"' {
      let start = offset
      let end = consume_string(line_text, offset)
      tokens.push({ start, end, tag: String })
      continue end
    } else if is_digit(unit) {
      let start = offset
      let end = consume_while(line_text, offset, is_digit)
      tokens.push({ start, end, tag: Number })
      continue end
    } else if is_ident_start(unit) {
      let start = offset
      let end = consume_while(line_text, offset, is_ident_continue)
      tokens.push({
        start,
        end,
        tag: if is_keyword(line_text[start:end]) {
          Keyword
        } else {
          Identifier
        },
      })
      continue end
    } else {
      // A surrogate pair is one punctuation token: token boundaries must
      // stay on whole characters or downstream text slicing panics.
      let start = offset
      let end = if @base_common.is_high_surrogate(unit) &&
        offset + 1 < line_text.length() &&
        @base_common.is_low_surrogate(line_text[offset + 1].to_int()) {
        offset + 2
      } else {
        offset + 1
      }
      tokens.push({ start, end, tag: Punctuation })
      continue end
    }
  }
  (tokens, state)
}

///|
fn consume_string(text : StringView, offset : Int) -> Int {
  for at = offset + 1, escaped = false; at < text.length(); {
    let unit = text[at].to_int()
    if escaped {
      continue at + 1, false
    } else if unit == '\\' {
      continue at + 1, true
    } else if unit == '"' {
      break at + 1
    }
    continue at + 1, false
  } nobreak {
    at
  }
}

///|
fn consume_while(text : StringView, offset : Int, pred : (Int) -> Bool) -> Int {
  for at = offset; at < text.length() && pred(text[at].to_int()); {
    continue at + 1
  } nobreak {
    at
  }
}

///|
fn is_space(unit : Int) -> Bool {
  unit is ('\t' | '\n' | '\r' | ' ')
}

///|
fn is_digit(unit : Int) -> Bool {
  unit is ('0'..='9')
}

///|
fn is_ident_start(unit : Int) -> Bool {
  unit is ('A'..='Z' | 'a'..='z' | '_')
}

///|
fn is_ident_continue(unit : Int) -> Bool {
  is_ident_start(unit) || is_digit(unit)
}

///|
fn is_keyword(text : StringView) -> Bool {
  text
  is ("fn"
  | "let"
  | "pub"
  | "struct"
  | "enum"
  | "match"
  | "if"
  | "else"
  | "while"
  | "for"
  | "return"
  | "test"
  | "import")
}

///|
pub extend PlainTokenizer with @syntax.LineTokenizer::{
  initial_state,
  tokenize_line,
}
